unit class Pod::To::PDF::Lite:ver<0.1.10>;
use PDF::Lite;
use PDF::Content;
use PDF::Content::FontObj;
use File::Temp;

use PDF;
use Pod::To::PDF::Lite::Style;
use Pod::To::PDF::Lite::Writer;

subset PodMetaType of Str where 'title'|'subtitle'|'author'|'name'|'version';

has PDF::Lite $.pdf .= new;
has Str %!metadata;
has PDF::Content::FontObj %.font-map;
has Lock:D $!lock .= new;
has Numeric $.width  = 612;
has Numeric $.height = 792;
has Bool $.page-numbers;

method lang is rw { $!pdf.Root<Lang>; }

method !init-pdf(Str :$lang) {
    $!pdf.media-box = 0, 0, $!width, $!height;
    self.lang = $_ with $lang;

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

method read-batch($pod, PDF::Content::PageTree:D $pages, |c) is hidden-from-backtrace {
    $pages.media-box = 0, 0, $!width, $!height;
    my $finish = ! $!page-numbers;
    my Pod::To::PDF::Lite::Writer $writer .= new: :%!font-map, :$pages, :$finish, |c;
    $writer.write($pod);
    $writer.metadata;
}

method merge-batch(%metadata) {
    self.metadata(.key) = .value for %metadata;
}

method !paginate($pdf,
                 UInt:D :$margin = 20,
                 UInt :$margin-right is copy,
                 UInt :$margin-bottom is copy,
                ) {
    my $page-count = $pdf.Pages.page-count;
    my $font = $pdf.core-font: "Helvetica";
    my $font-size := 9;
    my $align := 'right';
    my $page-num;
    $margin-right //= $margin;
    $margin-bottom //= $margin;
    if $margin-bottom < 10 && $!page-numbers {
        note "omitting page-numbers for margin-bottom < 10";
    }
    else {
        for $pdf.Pages.iterate-pages -> $page {
            my PDF::Content $gfx = $page.gfx;
            my @position = $gfx.width - $margin-right, $margin-bottom - $font-size;
            my $text = "Page {++$page-num} of $page-count";
            $gfx.print: $text, :@position, :$font, :$font-size, :$align;
            $page.finish;
        }
    }
}

# 'sequential' single-threaded processing mode
method read($pod, |c) {
    self.read-batch: $pod, $!pdf.Pages, |c;
    self!paginate($!pdf, |c)
        if $!page-numbers;
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
    IO() :$save-as is copy = tempfile("pod2pdf-lite-****.pdf", :!unlink)[1],
    UInt:D :$width  is copy = 612,
    UInt:D :$height is copy = 792,
    UInt:D :$margin is copy = 20,
    UInt   :$margin-left   is copy,
    UInt   :$margin-right  is copy,
    UInt   :$margin-top    is copy,
    UInt   :$margin-bottom is copy,
    Bool :$page-numbers is copy,
    |c,
) {
    state %cache{Any};
    %cache{$pod} //= do {
        my Bool $usage;
        for @*ARGS {
            when /^'--page-numbers'$/  { $page-numbers = True }
            when /^'--width='(\d+)$/   { $width  = $0.Int }
            when /^'--height='(\d+)$/  { $height = $0.Int }
            when /^'--margin='(\d+)$/  { $margin = $0.Int }
            when /^'--margin-top='(\d+)$/     { $margin-top = $0.Int }
            when /^'--margin-bottom='(\d+)$/  { $margin-bottom = $0.Int }
            when /^'--margin-left='(\d+)$/    { $margin-left = $0.Int }
            when /^'--margin-right='(\d+)$/   { $margin-right = $0.Int }
            when /^'--save-as='(.+)$/  { $save-as = $0.Str }
            default { $usage=True; note "ignoring $_ argument" }
        }
        note '(valid options are: --save-as= --page-numbers --width= --height= --margin[-left|-right|-top|-bottom]=)'
            if $usage;

        # render method may be called more than once: Rakudo #2588
        my $renderer = $class.new: |c, :$width, :$height, :$pod, :$margin, :$page-numbers,
                       :$margin-left, :$margin-right, :$margin-top, :$margin-bottom;
        my PDF::Lite $pdf = $renderer.pdf;
        # save to a file, since PDF is a binary format
        $pdf.save-as: $save-as;
        $save-as.path;
    }
}

our sub pod2pdf($pod, :$class = $?CLASS, |c) is export {
    $class.new(|c, :$pod).pdf;
}

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
            %!metadata{$t} = $v;
            self!set-pdf-info($t, $v);
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

    $ raku --doc=PDF::Lite lib/To/Class.rakumod --save-as=To-Class.pdf

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
$ raku --doc=PDF::Lite lib/to/class.rakumod --save-as=class.pdf

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

=head3 Command Line Options:

=defn --save-as=pdf-filename

File-name for the PDF output file. If not given, the
output will be saved to a temporary file. The file-name
is echoed to C<stdout>.

=defn --width=n

Page width in points (default: 592)

=defn --height=n

Page height in points (default: 792)

=defn --margin=n --margin-left=n --margin-right=n --margin-top=n --margin-bottom=n

Page margins in points (default: 20)

=defn --page-numbers

Output page numbers (format C<Page n of m>, bottom right)

=head2 Subroutines

### sub pod2pdf()

```raku
sub pod2pdf(
    Pod::Block $pod,
) returns PDF::Lite;
```

Renders the specified Pod to a PDF::Lite object, which can then be
further manipulated or saved.

=defn `PDF::Lite :$pdf`
An existing PDF::Lite object to add pages to.

=defn `UInt:D :$width, UInt:D :$height`
The page size in points (default 612 x 792).

=defn `UInt:D :$margin`
The page margin in points (default 20).

=defn `Hash :@fonts`
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

=head2 Asynchronous Rendering (Experimental)

    $ raku --doc=PDF::Lite::Async lib/to/class.rakumod | xargs evince

Also included in this module is class `Pod::To::PDF::Lite::Async`. This extends the `Pod::To::PDF::Lite` Pod renderer, adding the
ability to render larger documents concurrently.

For this mode to be useful, the document is likely to be of the order of dozens of pages
and include multiple level-1 headers (for batching purposes).

=head2 Restrictions

L<PDF::Lite> minimalism, including:

=item no Table of Contents or Index
=item no Links
=item no Marked Content/Accessibility

=head2 See Also

=item L<Pod::To::PDF::Lite::Async> - Multi-threaded rendering mode (experimental)
=item L<Pod::To::PDF> - PDF rendering via L<Cairo>

=end pod
