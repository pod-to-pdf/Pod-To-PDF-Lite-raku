unit class Pod::To::PDF::Lite:ver<0.1.2>;
use PDF::Lite;
use PDF::Content;
use PDF::Content::FontObj;
use PDF::Content::PageTree;
use File::Temp;
use Pod::To::PDF::Lite::Scheduler;
use Pod::To::PDF::Lite::Style;
use Pod::To::PDF::Lite::Writer;

has PDF::Lite $.pdf .= new;
has Str %!metadata;
has PDF::Content::FontObj %.font-map;
has Lock:D $!lock .= new;

method pdf {
    $!pdf;
}

method !init-pdf(Str :$lang) {
    $!pdf.Root<Lang> //= $_ with $lang;
    given $!pdf.Info //= {} {
        .CreationDate //= DateTime.now;
        .Producer //= "{self.^name}-{self.^ver}";
        .Creator //= "Raku-{$*RAKU.version}, PDF::Lite-{PDF::Lite.^ver}; PDF::Content-{PDF::Content.^ver}; PDF-{PDF.^ver}";
    }
}

method !preload-fonts(@fonts) {
    my $loader = (require ::('PDF::Font::Loader'));
    for @fonts -> % ( Str :$file!, Bool :$bold, Bool :$italic, Bool :$mono ) {
        # font preload
        my Pod::To::PDF::Lite::Style $style .= new: :$bold, :$italic, :$mono;
        if $file.IO.e {
            %!font-map{$style.font-key} = $loader.load-font: :$file;
        }
        else {
            warn "no such font file: $file";
        }
    }
}

method !read-sequential($pod, PDF::Content::PageTree:D $pages, |c) is hidden-from-backtrace {
    my Pod::To::PDF::Lite::Writer $writer .= new: :%!font-map, :$pages, |c;
    $writer.write($pod);
    self.metadata(.key) = .value for $writer.metadata.pairs;
}

# 'sequential' single-threaded processing mode
multi method read($pod, :sequential($)! where .so, |c) {
    self!read-sequential: $pod, $!pdf.Pages, |c;
}

# multi-threaded processing mode
multi method read(@pod, |c) {
    my List @batches = Pod::To::PDF::Lite::Scheduler.divvy(@pod).map: -> $pod {
        ($pod, PDF::Content::PageTree.pages-fragment);
    }

    if +@batches == 1 {
        self!read-sequential: @pod, $!pdf.Pages, |c;
    }
    else {
        @batches.race(:batch(1)).map: {
            self!read-sequential: |$_, |c;
        }

        $!pdf.add-pages(.[1]) for @batches;
    }
}

submethod TWEAK(Str :$lang = 'en', :$pod, :%metadata, :@fonts, |c) {
    self!init-pdf(:$lang);
    self!preload-fonts(@fonts)
        if @fonts;
    self.metadata(.key.lc) = .value for %metadata.pairs;
    self.read($_, |c) with $pod;
}

method render(
    $class: $pod,
    IO() :$pdf-file = tempfile("pod2pdf-lite-****.pdf", :!unlink)[1],
    UInt:D :$width  = 612,
    UInt:D :$height = 792,
    |c,
) {
    state %cache{Any};
    %cache{$pod} //= do {
        # render method may be called more than once: Rakudo #2588
        my $renderer = $class.new(|c, :$pod);
        my PDF::Lite $pdf = $renderer.pdf;
        $pdf.media-box = 0, 0, $width, $height;
        # save to a file, since PDF is a binary format
        $pdf.save-as: $pdf-file;
        $pdf-file.path;
    }
}

our sub pod2pdf($pod, :$class = $?CLASS, |c) is export {
    $class.new(|c, :$pod).pdf;
}

subset PodMetaType of Str where 'title'|'subtitle'|'author'|'name'|'version';

method !build-metadata-title {
    my @title = $_ with %!metadata<title>;
    with %!metadata<name> {
        @title.push: '-' if @title;
        @title.push: $_;
    }
    @title.push: 'v' ~ $_ with %!metadata<version>;
    @title.join: ' ';
}

method !set-pdf-info(PodMetaType $key, $value) {

    my Str:D $pdf-key = do given $key {
        when 'title'|'version'|'name' { 'Title' }
        when 'subtitle' { 'Subject' }
        when 'author' { 'Author' }
    }

    my $pdf-value = $pdf-key eq 'Title'
        ?? self!build-metadata-title()
        !! $value;

    my $info = ($!pdf.Info //= {});
    $info{$pdf-key} = $pdf-value;
}

method metadata(PodMetaType $t) is rw {
    Proxy.new(
        FETCH => { $!lock.protect: { %!metadata{$t} } },
        STORE => -> $, Str:D() $v {
            $!lock.protect: {
                %!metadata{$t} = $v;
                self!set-pdf-info($t, $v);
            }
        }
    )
}

=begin pod
=TITLE Pod::To::PDF::Lite
=SUBTITLE  Pod to PDF draft renderer

=head2 Description

Renders Pod to PDF draft documents via PDF::Lite.

=head2 Usage

From command line:

    $ raku --doc=PDF::Lite lib/to/class.rakumod | xargs evince

From Raku:
    =begin code :lang<raku>
    use Pod::To::PDF::Lite;

    =NAME
    foobar.pl

    =SYNOPSIS
        foobar.pl <options> files ...

    pod2pdf($=pod).save-as: "foobar.pdf";
    =end code

=head2 Exports

    class Pod::To::PDF::Lite;
    sub pod2pdf; # See below

From command line:
=for code :lang<shell>
$ raku --doc=PDF::Lite lib/to/class.rakumod | xargs evince

From Raku code, the C<pod2pdf> function returns a L<PDF::Lite> object which can
be further manipulated, or saved to a PDF file.

    =begin code :lang<raku>
    use Pod::To::PDF::Lite;
    use PDF::Lite;
 
    =NAME
    foobar.raku

    =SYNOPSIS
        foobarraku <options> files ...

    my PDF::Lite $pdf = pod2pdf($=pod);
    $pdf.save-as: "foobar.pdf"
    =end code


=head2 Subroutines

### sub pod2pdf()

```raku
sub pod2pdf(
    Pod::Block $pod
) returns PDF::Lite;
```

Renders the specified Pod to a PDF::Lite object, which can then be
further manipulated or saved.

=defn `PDF::Lite :$pdf`
An existing PDF::Lite object to add pages to.

=defn `UInt:D :$width, UInt:D :$height`
The page size in points (there are 72 points per inch).

=defn `UInt:D :$margin`
The page margin in points (default 20).

=defn `Hash :@fonts
By default, Pod::To::PDF::Lite uses core fonts. This option can be used to preload selected fonts.

Note: L<PDF::Font::Loader> must be installed, to use this option.

=begin code :lang<raku>
use PDF::Lite;
use Pod::To::PDF::Lite;
need PDF::Font::Loader; # needed to enable this option

my @fonts = (
    %(:file<fonts/Raku.ttf>),
    %(:file<fonts/Raku-Bold.ttf>, :bold),
    %(:file<fonts/Raku-Italic.ttf>, :italic),
    %(:file<fonts/Raku-BoldItalic.ttf>, :bold, :italic),
    %(:file<fonts/Raku-Mono.ttf>, :mono),
);

PDF::Lite $pdf = pod2pdf($=pod, :@fonts);
$pdf.save-as: "pod.pdf";
=end code

=head2 Restrictions

L<PDF::Lite> minimalism, including:

=item no Table of Contents or Index
=item no Links
=item no Marked Content/Accessibility

=head2 See Also

=item L<Pod::To::PDF> - PDF rendering via L<Cairo>

=end pod
