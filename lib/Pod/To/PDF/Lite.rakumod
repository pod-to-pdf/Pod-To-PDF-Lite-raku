unit class Pod::To::PDF::Lite:ver<0.0.12>;
use PDF::Lite;
use PDF::Content;
use PDF::Content::Color :&color;
use PDF::Content::Text::Box;
use Pod::To::PDF::Lite::Style;
use File::Temp;

subset Level of Int:D where 0..6;
my constant Gutter = 1;

has PDF::Lite $.pdf .= new;
has PDF::Lite::Page $!page;
has PDF::Content $!gfx;
has UInt $!indent = 0;
has Pod::To::PDF::Lite::Style $.style handles<font-size leading line-height bold italic mono underline lines-before link verbatim> .= new;
has $.margin = 20;
has $!gutter = Gutter;
has $!tx = $!margin; # text-flow x
has $!ty; # text-flow y
has UInt $!pad = 0;
has @!footnotes;
has Str %!metadata;
has UInt:D $!level = 1;
has %.replace;
has Numeric $!code-start-y;
has PDF::Content::FontObj %.font-map;

method pdf {
    $!pdf;
}

method read($pod) {
    self.pod2pdf($pod);
    self!finish-page;
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

submethod TWEAK(Str :$lang = 'en', :$pod, :%metadata, :@fonts) {
    self!init-pdf(:$lang);
    self!preload-fonts(@fonts)
        if @fonts;
    self.metadata(.key.lc) = .value for %metadata.pairs;
    self.read($_) with $pod;
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

my constant vpad = 2;
my constant hpad = 10;

# a simple algorithm for sizing table column widths
sub fit-widths($width is copy, @widths) {
    my $cell-width = $width / +@widths;
    my @idx;

    for @widths.pairs {
        if .value <= $cell-width {
            $width -= .value;
        }
        else {
            @idx.push: .key;
        }
    }

    if @idx {
        if @idx < @widths {
            my @over;
            my $i = 0;
            @over[$_] := @widths[ @idx[$_] ]
                for  ^+@idx;
            fit-widths($width, @over);
        }
        else {
            $_ = $cell-width
                for @widths;
        }
    }
}

method !table-row(@row, @widths, Bool :$header) {
    if +@row -> \cols {
        my @overflow;
        # simple fixed column widths, for now
        my $tab = self!indent;
        my $row-height = 0;
        my $height = $!ty - $!margin;
        my $head-space = $.line-height - $.font-size;

        for ^cols {
            my $width = @widths[$_];

            if @row[$_] -> $tb is rw {
                if $tb.width > $width || $tb.height > $height {
                    $tb .= clone: :$width, :$height;
                }

                self!gfx.print: $tb, :position[$tab, $!ty];
                if $header {
                    # draw underline
                    my $y = $!ty + $tb.underline-position - $head-space;
                    self!draw-line: $tab, $y, $tab + $width;
                }
                given $tb.content-height {
                    $row-height = $_ if $_ > $row-height;
                }
                if $tb.overflow -> $overflow {
                    my $text = $overflow.join;
                    @overflow[$_] = $tb.clone: :$text, :$width, :height(0);
                }
            }
            $tab += $width + hpad;
        }
        if @overflow {
            # continue table
            self!style: :lines-before(3), {
                self!table-row(@overflow, @widths, :$header);
            }
        }
        else {
            $!ty -= $row-height + vpad;
            $!ty -= $head-space if $header;
        }
    }
}

# generate content of a single table cell
method !table-cell($pod) {
    my $text = $.pod2text-inline($pod);
    self!text-box: $text, :width(0), :height(0), :indent(0);
}

# prepare a table as a grid of text boxes. compute column widths
method !build-table($pod, @table) {
    my $x0 = self!indent;
    my \total-width = self!gfx.canvas.width - $x0 - $!margin;
    @table = ();

    self!style: :bold, :lines-before(3), {
        my @row = $pod.headers.map: { self!table-cell($_) }
        @table.push: @row;
    }

    $pod.contents.map: {
        my @row = .map: { self!table-cell($_) }
        @table.push: @row;
    }

    my $cols = @table.max: *.Int;
    my @widths = (^$cols).map: -> $col { @table.map({.[$col].?width // 0}).max };
   fit-widths(total-width - hpad * (@widths-1), @widths);
   @widths;
}

multi method pod2pdf(Pod::Block::Table $pod) {
    my @widths = self!build-table: $pod, my @table;

    self!style: :lines-before(3), :pad, {
        if $pod.caption -> $caption {
            temp $.italic = True;
            $.say: $caption;
        }
        self!pad-here;
        my PDF::Content::Text::Box @header = @table.shift.List;
        if @header {
            self!table-row: @header, @widths, :header;
        }

        if @table {
            for @table {
                my @row = .List;
                if @row {
                    self!table-row: @row, @widths;
                }
            }
        }
    }
}

multi method pod2pdf(Pod::Block::Named $pod) {
    $.pad: {
        given $pod.name {
            when 'pod'  { $.pod2pdf($pod.contents)     }
            when 'para' {
                $.pod2pdf: $pod.contents;
            }
            when 'config' { }
            when 'nested' {
                self!style: :indent, {
                    $.pod2pdf: $pod.contents;
                }
            }
            when  'TITLE'|'SUBTITLE' {
                temp $!level = $_ eq 'TITLE' ?? 0 !! 2;
                self.metadata(.lc) ||= $.pod2text-inline($pod.contents);
                self!heading($pod.contents, :pad(1));
            }

            default {
                my $name = $_;
                temp $!level += 1;
                if $name eq $name.uc {
                    if $name ~~ 'VERSION'|'NAME'|'AUTHOR' {
                        self.metadata(.lc) ||= $.pod2text-inline($pod.contents);
                    }
                    $!level = 2;
                    $name = .tclc;
                }
                $.pod2pdf($pod.contents);
            }
        }
    }
}

multi method pod2pdf(Pod::Block::Code $pod) {
    self!style: :pad, :lines-before(3), {
        self!code: $pod.contents;
    }
}

multi method pod2pdf(Pod::Heading $pod) {
    $.pad: {
        $!level = min($pod.level, 6);
        self!heading: $pod.contents;
    }
}

multi method pod2pdf(Pod::Block::Para $pod) {
    $.pad: {
        $.pod2pdf($pod.contents);
    }
}

has %!replacing;
method !replace(Pod::FormattingCode $pod where .type eq 'R', &continue) {
    my $place-holder = $.pod2text($pod.contents);

    die "unable to recursively replace R\<$place-holder\>"
         if %!replacing{$place-holder}++;

    my $new-pod = %!replace{$place-holder};
    without $new-pod {
        note "replacement not specified for R\<$place-holder\>";
        $_ = $pod.contents;
    }

    my $rv := &continue($new-pod);

    %!replacing{$place-holder}:delete;;
    $rv;
}

multi method pod2pdf(Pod::FormattingCode $pod) {
    given $pod.type {
         when 'B' {
            self!style: :bold, {
                $.pod2pdf($pod.contents);
            }
         }
         when 'C' {
             my $font-size = $.font-size * .85;
             self!style: :mono, :$font-size, {
                 $.print: $.pod2text($pod);
             }
        }
        when 'T' {
            self!style: :mono, {
                $.pod2pdf($pod.contents);
            }
        }
        when 'K' {
            self!style: :italic, :mono, {
                $.pod2pdf($pod.contents);
            }
        }
        when 'I' {
            self!style: :italic, {
                $.pod2pdf($pod.contents);
            }
        }
        when 'N' {
            my $ind = '[' ~ @!footnotes+1 ~ ']';
            self!style: :link, {  $.pod2pdf($ind); }
            do {
                # pre-compute footnote size
                temp $!style .= new;
                temp $!tx = $!margin;
                temp $!ty = $!page.height;
                my $draft-footnote = $ind ~ $.pod2text-inline($pod.contents);
                $!gutter += self!text-box($draft-footnote).lines;
            }
        }
        when 'U' {
            self!style: :underline, {
                $.pod2pdf($pod.contents);
            }
        }
        when 'E' {
            $.pod2pdf($pod.contents);
        }
        when 'Z' {
            # invisable
        }
        when 'X' {
            # indexing
            $.pod2pdf($pod.contents);
        }
        when 'L' {
            my $text = $.pod2text-inline($pod.contents);
            self!style: :link, {
                $.print($text);
            }
        }
        when 'P' {
            if $.pod2text-inline($pod.contents) -> $url {
                $.pod2pdf('(see: ');
                self!style: :link, {
                    $.print($url);
                }
                $.pod2pdf(')');
            }
        }
        when 'R' {
            self!replace: $pod, {$.pod2pdf($_)};
        }
        default {
            warn "unhandled POD formatting code: $_\<\>";
            $.pod2pdf($pod.contents);
        }
    }
}

multi method pod2pdf(Pod::Defn $pod) {
    $.pad;
    self!style: :bold, {
        $.pod2pdf($pod.term);
    }
    $.pod2pdf($pod.contents);
}

multi method pod2pdf(Pod::Item $pod) {
    $.pad: {
        my Level $list-level = min($pod.level // 1, 3);
        self!style: :indent($list-level), {
            my constant BulletPoints = ("\c[BULLET]",
                                        "\c[MIDDLE DOT]",
                                        '-');
            my $bp = BulletPoints[$list-level - 1];
            $.print: $bp;

            # slightly iffy $!ty fixup
            $!ty += 2 * $.line-height;

            self!style: :indent, {
                $.pod2pdf($pod.contents);
            }
        }
    }
}

multi method pod2pdf(Pod::Block::Declarator $pod) {
    my $w := $pod.WHEREFORE;
    my Level $level = 3;
    my ($type, $code, $name, $decl) = do given $w {
        when Method {
            my @params = .signature.params.skip(1);
            @params.pop if @params.tail.name eq '%_';
            (
                (.multi ?? 'multi ' !! '') ~ 'method',
                .name ~ signature2text(@params, .returns),
            )
        }
        when Sub {
            (
                (.multi ?? 'multi ' !! '') ~ 'sub',
                .name ~ signature2text(.signature.params, .returns)
            )
        }
        when Attribute {
            my $gist = .gist;
            my $name = .name.subst('$!', '');
            $gist .= subst('!', '.')
                if .has_accessor;

            ('attribute', $gist, $name, 'has');
        }
        when .HOW ~~ Metamodel::EnumHOW {
            ('enum', .raku() ~ signature2text($_.enums.pairs));
        }
        when .HOW ~~ Metamodel::ClassHOW {
            $level = 2;
            ('class', .raku, .^name);
        }
        when .HOW ~~ Metamodel::ModuleHOW {
            $level = 2;
            ('module', .raku, .^name);
        }
        when .HOW ~~ Metamodel::SubsetHOW {
            ('subset', .raku ~ ' of ' ~ .^refinee().raku);
        }
        when .HOW ~~ Metamodel::PackageHOW {
            ('package', .raku)
        }
        default {
            '', ''
        }
    }

    $name //= $w.?name // '';
    $decl //= $type;

    self!style: :lines-before(3), :pad, {
        self!heading($type.tclc ~ ' ' ~ $name, :$level);

       if $pod.leading -> $pre-pod {
            self!style: :pad, {
                $.pad;
                $.pod2pdf($pre-pod);
            }
        }

        if $code {
            self!style: :pad, {
                self!code([$decl ~ ' ' ~ $code]);
            }
        }

        if $pod.trailing -> $post-pod {
            $.pad;
            self!style: :pad, {
                $.pod2pdf($post-pod);
            }
        }
    }
}

multi method pod2pdf(Pod::Block::Comment) {
    # ignore comments
}

sub signature2text($params, Mu $returns?) {
    my constant NL = "\n    ";
    my $result = '(';

    if $params.elems {
        $result ~= NL ~ $params.map(&param2text).join(NL) ~ "\n";
    }
    $result ~= ')';
    unless $returns<> =:= Mu {
        $result ~= " returns " ~ $returns.raku
    }
    $result;
}
sub param2text($p) {
    $p.raku ~ ',' ~ ( $p.WHY ?? ' # ' ~ $p.WHY !! ' ')
}

multi method pod2pdf(Array $pod) {
    for $pod.list {
        $.pod2pdf($_);
    };
}

multi method pod2pdf(Str $pod) {
    $.print($pod);
}

multi method pod2pdf(List:D $pod) {
    $.pod2pdf($_) for $pod.List;
}

multi method pod2pdf($pod) {
    warn "fallback render of {$pod.WHAT.raku}";
    $.say: $.pod2text($pod);
}

multi method say {
    $!tx = $!margin;
    $!ty -= $.line-height;
}
multi method say(Str $text, |c) {
    @.print($text, :nl, |c);
}

method font { $!style.font: :%!font-map }

multi method pad(&codez) { $.pad; &codez(); $.pad}
multi method pad($!pad = 2) { }
method !text-box(
    Str $text,
    :$width = self!gfx.canvas.width - self!indent - $!margin,
    :$height = self!height-remaining,
    |c) {
    PDF::Content::Text::Box.new: :$text, :indent($!tx - $!margin), :$.leading, :$.font, :$.font-size, :$width, :$height, :$.verbatim, |c;
}

method !pad-here {
    $.say for ^$!pad;
    $!pad = 0;
}
method print(Str $text, Bool :$nl, :$reflow = True, |c) {
    self!pad-here;
    my PDF::Content::Text::Box $tb = self!text-box: $text, |c;
    my $w = $tb.content-width;
    my $h = $tb.content-height;
    my Pair $pos = self!text-position();
    my $gfx = self!gfx;
    if $.link {
        use PDF::Content::Color :ColorName;
        $gfx.Save;
        given color Blue {
            $gfx.FillColor = $_;
            $gfx.StrokeColor = $_;
        }
    }

    $gfx.print: $tb, |$pos, :$nl;
    self!underline: $tb
        if $.underline || $.link;

    $gfx.Restore if $.link;

    # update text position ($!tx, $!ty)
    if $nl {
        # advance to next line
        $!tx = $!margin;
    }
    else {
        $!tx = $!margin if $tb.lines > 1;
        # continue this line
        with $tb.lines.pop {
            $w = .content-width - .indent;
            $!tx += $w;
        }
    }
    $!ty -= $tb.content-height;

    if $tb.overflow {
        my $in-code-block = $!code-start-y.defined;
        self!new-page;
        $!code-start-y = $!ty if $in-code-block;
        self.print($tb.overflow.join, :$nl);
    }
}

method !text-position {
    :position[self!indent, $!ty]
}

method !style(&codez, Int :$indent, Bool :$pad, |c) {
    temp $!style .= clone: |c;
    temp $!indent;
    $!indent += $indent if $indent;
    $pad ?? $.pad(&codez) !! &codez();
}

method !heading($pod is copy, Level :$level = $!level, :$underline = $level <= 1, :$!pad = 2) {
    my constant HeadingSizes = 24, 20, 16, 13, 11.5, 10, 10;
    my $font-size = HeadingSizes[$level];
    my Bool $bold   = $level <= 4;
    my Bool $italic;
    my $lines-before = $.lines-before;

    given $level {
        when 0|1 { self!new-page; }
        when 2   { $lines-before = 3; }
        when 3   { $lines-before = 2; }
        when 5   { $italic = True; }
    }

    self!style: :$font-size, :$bold, :$italic, :$underline, :$lines-before, {
        $.pod2pdf: strip-para($pod);
   }
}

method !finish-code {
    my constant pad = 5;
    with $!code-start-y -> $y0 {
        my $x0 = self!indent;
        my $width = self!gfx.canvas.width - $!margin - $x0;
        $!gfx.graphics: {
            .FillColor = color 0;
            .StrokeColor = color 0;
            .FillAlpha = 0.1;
            .StrokeAlpha = 0.25;
            .Rectangle: $x0 - pad, $!ty - pad, $width + pad*2, $y0 - $!ty + pad*3;
            .paint: :fill, :stroke;
        }
        $!code-start-y = Nil;
    }
}

method !code(@contents is copy) {
    @contents.pop if @contents.tail ~~ "\n";
    my $font-size = $.font-size * .85;

    self!gfx;

    self!style: :mono, :indent, :$font-size, :lines-before(0), :pad, :verbatim, {
        self!pad-here;
        my @plain-text;

        for 0 ..^ @contents -> $i {
            $!code-start-y //= $!ty;
            given @contents[$i] {
                when Str {
                    @plain-text.push: $_;
                }
                default  {
                    # presumably formatted
                    if @plain-text {
                        $.print: @plain-text.join;
                        @plain-text = ();
                    }

                    $.pod2pdf($_);
                }
            }
        }
        if @plain-text {
            $.print: @plain-text.join;
        }
        self!finish-code;
    }
}

method !draw-line($x0, $y0, $x1, $y1 = $y0, :$linewidth = 1) {
    given $!gfx {
        .Save;
        .SetLineWidth: $linewidth;
        .MoveTo: $x0, $y0;
        .LineTo: $x1, $y1;
        .Stroke;
        .Restore;
    }
}

method !underline(PDF::Content::Text::Box $tb, :$tab = self!indent, ) {
    my $y = $!ty + $tb.underline-position;
    my $linewidth = $tb.underline-thickness;
    for $tb.lines {
        my $x0 = $tab + .indent;
        my $x1 = $tab + .content-width;
        self!draw-line($x0, $y, $x1, :$linewidth);
        $y -= .height * $tb.leading;
    }
}

method !gfx {
    if !$!gfx.defined || self!height-remaining < $.lines-before * $.line-height {
        self!new-page;
    }
    elsif $!tx > $!margin && $!tx > $!gfx.canvas.width - self!indent {
        self.say;
    }
    $!gfx;
}

method !top { $!page.height - 2 * $!margin; }
method !bottom { $!margin + ($!gutter-2) * $.line-height; }
method !height-remaining {
    $!ty - $!margin - $!gutter * $.line-height;
}

method !lines-remaining {
    (self!height-remaining / $.line-height + 0.01).Int;
}

method !finish-page {
    self!finish-code
        if $!code-start-y;
    if @!footnotes {
        temp $!style .= new: :lines-before(0); # avoid current styling
        $!tx = 0;
        $!ty = self!bottom;
        $!gutter = 0;
        self!draw-line($!margin, $!ty, $!gfx.canvas.width - 2*$!margin, $!ty);
        while @!footnotes {
            $.pad(1);
            my $footnote = @!footnotes.shift;
            self!style: :link, { self.print($footnote.shift) }; # [n]
            $.pod2pdf($footnote);
        }
    }
}

method !new-page {
    self!finish-page();
    $!gutter = Gutter;
    $!page = $!pdf.add-page;
    $!gfx = $!page.gfx;
    $!tx = $!margin;
    $!ty = $!page.height - 2 * $!margin;
    # suppress whitespace before significant content
    $!pad = 0;
}

method !indent { $!margin  +  10 * $!indent; }

method pod2text-inline($pod) {
    $.pod2text($pod).subst(/\s+/, ' ', :g);
}

multi method pod2text(Pod::FormattingCode $pod) {
    given $pod.type {
        when 'N'|'Z' { '' }
        when 'R' { self!replace: $pod, { $.pod2text($_) } }
        default  { $.pod2text: $pod.contents }
    }
}

multi method pod2text(Pod::Block $pod) {
    $pod.contents.map({$.pod2text($_)}).join;
}
multi method pod2text(Str $pod) { $pod }
multi method pod2text($pod) { $pod.map({$.pod2text($_)}).join }


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

method !set-metadata(PodMetaType $key, $value) {

    %!metadata{$key} = $value;

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

# to reduce the common case <Hn><P>Xxxx<P></Hn> -> <Hn>Xxxx</Hn>
multi sub strip-para(List $_ where +$_ == 1) {
    .map(&strip-para).List;
}
multi sub strip-para(Pod::Block::Para $_) {
    .contents;
}
multi sub strip-para($_) { $_ }

multi method metadata(PodMetaType $t) is rw {
    Proxy.new(
        FETCH => { %!metadata{$t} },
        STORE => -> $, Str:D() $v {
            self!set-metadata($t, $v);
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
    =begin code :lang<shell>
    $ raku --doc=PDF::Lite lib/to/class.rakumod | xargs evince
    =end code
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
A PDF::Lite object to add pages to.

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
