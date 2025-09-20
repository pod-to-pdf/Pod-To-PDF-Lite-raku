unit class Pod::To::PDF::Lite:ver<0.1.16>;
use PDF::Lite;
use PDF::Content;
use PDF::Content::FontObj;
use PDF::Content::PageTree;
use File::Temp;


use PDF;
use Pod::To::PDF::Lite::Style;
use Pod::To::PDF::Lite::Writer;
use Pod::To::PDF::Lite::Async::Scheduler;

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

method !paginate(
    $pdf,
    Numeric:D :$margin = 20,
    Numeric :$margin-right is copy,
    Numeric :$margin-bottom is copy,
) {
    my $page-count = $pdf.Pages.page-count;
    my $font = $pdf.core-font: "Helvetica";
    my $font-size := 9;
    my $align := 'right';
    my $page-num;
    $margin-right //= $margin;
    $margin-bottom //= $margin;
    if $margin-bottom < 10 && $!page-numbers {
        note "omitting page-numbers for margin-bottom < 10pt";
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

# asynchronous pod processing
multi method read(@pod, Bool :$async! where .so, |c) {
    my List @batches = Pod::To::PDF::Lite::Async::Scheduler.divvy(@pod).map: -> $pod {
        ($pod, PDF::Content::PageTree.pages-fragment);
    }

    nextsame if @batches == 1;

    {
        my @results = @batches.hyper(:batch(1)).map: {
            self.read-batch: |$_, |c;
        }

        $.pdf.add-pages(.[1]) for @batches;
        $.merge-batch($_) for @results;

        self!paginate($!pdf, |c)
            if $!page-numbers;
    }
}

# 'sequential' single-threaded processing mode
multi method read(@pod, |c) {
    self.merge-batch: self.read-batch(@pod, $!pdf.Pages, |c);
    self!paginate($!pdf, |c)
        if $!page-numbers;
}

submethod TWEAK(Str :$lang = 'en', :%metadata, :@fonts, |c) {
    self!init-pdf(:$lang);
    self!preload-fonts(@fonts)
        if @fonts;
    self.metadata(.key.lc) = .value for %metadata.pairs;
}

sub apply-page-styling($style, *%props) {
    CATCH {
        when X::CompUnit::UnsatisfiedDependency {
            note "Ignoring --page-style argument; Please install CSS::Properties"
        }
    }
    my $css = (require ::('CSS::Properties')).new: :$style;
    %props{.key} = .value for $css.Hash;
}

sub get-opts(%opts) {
    my Bool $show-usage;
    for @*ARGS {
        when /^'--'('/')?(page\-numbers|async)$/         { %opts{$1} = ! $0.so }
        when /^'--'('/')?[toc|['table-of-']?contents]$/  { %opts<contents>  = ! $0.so }
        when /^'--'(page\-style|save\-as)'='(.+)$/       { %opts{$0} = $1.Str }
        when /^'--'(width|height|margin[\-[top|bottom|left|right]]?)'='(\d+)$/
                                                         { %opts{$0}  = $1.Int }
        default {  $show-usage = True; note "ignoring $_ argument" }
    }
    note '(valid options are: --save-as= --page-numbers --width= --height= --margin[-left|-right|-top|-bottom]?= --page-style --async=)'
        if $show-usage;
    %opts;
}

sub pod-render(
    $pod,
    :$class!,
    IO()   :$save-as,
    Numeric:D :$width  = 612,
    Numeric:D :$height = 792,
    Numeric:D :$margin = 20,
    Numeric   :$margin-left   = $margin,
    Numeric   :$margin-top    = $margin ,
    Numeric   :$margin-right  = $margin-left,
    Numeric   :$margin-bottom = $margin-top,
    Bool      :$page-numbers,
    Bool      :$async,
    Str       :$page-style,
    |c,
) {
    apply-page-styling(
        $_,
        :$width, :$height,
        :$margin-top, :$margin-bottom, :$margin-left, :$margin-right,
    ) with $page-style;

    # render method may be called more than once: Rakudo #2588
    my $renderer = $class.new: |c, :$pod, :$width, :$height, :$margin, :$page-numbers,
                   :$margin-left, :$margin-right, :$margin-top, :$margin-bottom;
    my PDF::Lite $pdf = $renderer.pdf;
    $renderer.read($pod, :$async);
    # save to a file, since PDF is a binary format
    $pdf.save-as: $_ with $save-as;
    $renderer;
}

method render(::?CLASS $class: $pod, Str :$save-as, |c) {
    my %opts .= &get-opts;
    %opts<save-as> = $_ with $save-as;
    %opts<save-as> //= tempfile("pod2pdf-lite-****.pdf", :!unlink)[1];
    state $rendered //= pod-render($pod, :$class, |%opts, |c);
    %opts<save-as>;
}

our sub pod2pdf($pod, :$class = $?CLASS, |c) is export {
    my $renderer = pod-render($pod, :$class, |c);
    $renderer.pdf;
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

=defn --page-style

=begin code :lang<raku>
-raku --doc=PDF::Lite lib/to/class.rakumod --page-style='margin:10px 20px; width:200pt; height:500pt" --save-as=class.pdf
=end code

Perform CSS C<@page> like styling of pages. At the moment, only margins (C<margin>, C<margin-left>, C<margin-top>, C<margin-bottom>, C<margin-right>) and the page C<width> and C<height> can be set. The optional [CSS::Properties](https://css-raku.github.io/CSS-Properties-raku/) module needs to be installed to use this option.

=defn --async

Perform asynchronous processing. This may be useful for larger PoD documents,
that have multiple sections, seperated by level-1 headers, or titles.

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

=defn `Bool :$async`

Process a document in asynchronous batches.

This is only useful for a large Pod document that has multiple sections, each beginning with a title, or level-1 heading.

=head2 Restrictions

L<PDF::Lite> minimalism, including:

=item no Table of Contents or Index
=item no Links
=item no Marked Content/Accessibility

=head2 See Also

=item L<Pod::To::PDF> - PDF rendering via L<Cairo>

=end pod
