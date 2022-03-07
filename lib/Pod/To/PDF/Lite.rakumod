unit class Pod::To::PDF::Lite:ver<0.0.7>;
use PDF::Lite;
use PDF::Content;
use PDF::Content::Color :&color;
use PDF::Content::Text::Box;
use Pod::To::PDF::Lite::Style;
use Pod::To::Text;
use File::Temp;

subset Level of Int:D where 1..6;
my constant Gutter = 3;

has PDF::Lite $.pdf is built .= new;
has PDF::Lite::Page $!page;
has PDF::Content $!gfx;
has UInt $!indent = 0;
has Pod::To::PDF::Lite::Style $.style handles<font font-size leading line-height bold italic mono underline lines-before link> .= new;
has $.margin = 20;
has $!gutter = Gutter;
has $!tx = $!margin; # text-flow x
has $!ty; # text-flow y
has UInt $!pad = 0;
has @!footnotes;
has Str %!metadata;
has UInt:D $!level = 1;

method pdf {
    $!pdf;
}

method read($pod) {
    self.pod2pdf($pod);
    self!finish-page;
}

submethod TWEAK(Str :$lang = 'en', :$pod, :%metadata) {
    $!pdf.Root<Lang> //= $_ with $lang;
    given $!pdf.Info //= {} {
        .CreationDate //= DateTime.now;
        .Producer //= "{self.^name}-{self.^ver}";
        .Creator //= "Raku-{$*RAKU.version}, PDF::Lite-{PDF::Lite.^ver}; PDF::Content-{PDF::Content.^ver}; PDF-{PDF.^ver}";
    }
    self.metadata(.key.lc) = .value for %metadata.pairs;
    self.read($_) with $pod;
}

method render($class: $pod, |c) {
    state %cache{Any};
    %cache{$pod} //= do {
        # render method may be called more than once: Rakudo #2588
        my $renderer = $class.new(|c, :$pod);
        my PDF::Lite $pdf = $renderer.pdf;
        # save to a temporary file, since PDF is a binary format
        my (Str $file-name, IO::Handle $fh) = tempfile("pod2pdf-lite-****.pdf", :!unlink);
        $pdf.save-as: $fh;
        $file-name;
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
    my $text = pod2text-inline($pod);
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
                $.pad(0);
                temp $!level = $_ eq 'TITLE' ?? 1 !! 2;
                my $title = pod2text-inline($pod.contents);
                self.metadata(.lc) ||= $title;
                self!heading($title);
            }

            default {
                when 'NAME'|'AUTHOR'|'VERSION' {
                    self.metadata(.lc) ||= pod2text-inline($pod.contents);
                }
                my $name = $_;
                temp $!level += 1;
                if $name eq .uc {
                    $!level = 2;
                    $name .= tclc;
                }
                self!heading($name);
                $.pod2pdf($pod.contents);
            }
        }
    }
}

multi method pod2pdf(Pod::Block::Code $pod) {
    $.pad: {
        self!code: pod2text-code($pod);
    }
}

multi method pod2pdf(Pod::Heading $pod) {
    $.pad: {
        my Level $level = min($pod.level, 6);
        self!heading( pod2text-inline($pod.contents), :$level);
    }
}

multi method pod2pdf(Pod::Block::Para $pod) {
    $.pad: {
        $.pod2pdf($pod.contents);
    }
}

multi method pod2pdf(Pod::FormattingCode $pod) {
    given $pod.type {
         when 'B' {
            self!style: :bold, {
                $.pod2pdf($pod.contents);
            }
        }
        when 'C' {
            self!code: pod2text($pod), :inline;
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
                my $draft-footnote = $ind ~ pod2text-inline($pod.contents);
                $!gutter += self!text-box($draft-footnote).lines;
            }
        }
        when 'U' {
            self!style: :underline, {
                $.pod2pdf($pod.contents);
            }
        }
        when 'Z' {
            # invisable
        }
        when 'X' {
            # indexing
            $.pod2pdf($pod.contents);
        }
        when 'L' {
            my $text = pod2text-inline($pod.contents);
            self!style: :link, {
                $.print($text);
            }
        }
        default {
            warn "todo: POD formatting code: $_";
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

        if $code {
            $.pad(1);
            self!code($decl ~ ' ' ~ $code);
        }

        if $pod.contents {
            $.pad;
            $.pod2pdf($pod.contents);
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

multi method pod2pdf($pod) {
    warn "fallback render of {$pod.WHAT.raku}";
    $.say: pod2text($pod);
}

multi method say {
    $!tx = $!margin;
    $!ty -= $.line-height;
}
multi method say(Str $text, |c) {
    @.print($text, :nl, |c);
}

multi method pad(&codez) { $.pad; &codez(); $.pad}
multi method pad($!pad = 2) { }
method !text-box(
    Str $text,
    :$width = self!gfx.canvas.width - self!indent - $!margin,
    :$height = self!height-remaining,
    |c) {
    PDF::Content::Text::Box.new: :$text, :indent($!tx - $!margin), :$.leading, :$.font, :$.font-size, :$width, :$height, |c;
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

    # calculate text bounding box and advance x, y
    my $lines = +$tb.lines;
    my $x0 = $pos.value[0];
    if $nl {
        # advance to next line
        $!tx = $!margin;
    }
    else {
        $!tx = $!margin if $tb.lines > 1;
        $x0 += $!tx;
        # continue this line
            with $tb.lines.pop {
                $w = .content-width - .indent;
                $!tx += $w + $tb.space-width;
            }
    }
    $!ty -= $tb.content-height;
    my Str $overflow = $tb.overflow.join;
    if $overflow && $reflow {
        $.say() unless $nl;
        @.print: $overflow, :$nl, |c;
        $overflow = Nil;
    }
    ($x0, $!ty, $w, $h, $overflow);
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

method !heading(Str:D $Title, Level :$level = $!level, :$underline = $level == 1) {
    my constant HeadingSizes = 20, 16, 13, 11.5, 10, 10;
    my $font-size = HeadingSizes[$level - 1];
    my Bool $bold   = $level <= 4;
    my Bool $italic;
    my $lines-before = $.lines-before;

    given $level {
        when 1 { self!new-page; }
        when 2 { $lines-before = 3; }
        when 3 { $lines-before = 2; }
        when 5 { $italic = True; }
    }

    self!style: :$font-size, :$bold, :$italic, :$underline, :$lines-before, {


        @.say($Title);
    }
}

method !code(Str $code is copy, :$inline) {
    my $font-size = 8;
    my $lines-before = $.lines-before;
    $lines-before = min(+$code.lines, 3)
        unless $inline;

    self!style: :mono, :indent(!$inline), :$font-size, :$lines-before, {
        $code .= chomp;

        while $code {
            my (\x, \y, \w, \h, \overflow) = @.print: $code, :verbatim, :!reflow;
            $code = overflow;
            unless $inline {
                # draw code-block background
                my constant pad = 5;
                my $x0 = self!indent;
                my $width = $!gfx.canvas.width - $!margin - $x0;
                $!gfx.graphics: {
                    .FillColor = color 0;
                    .StrokeColor = color 0;
                    .FillAlpha = 0.1;
                    .StrokeAlpha = 0.25;
                    .Rectangle: $x0 - pad, y - pad, $width + pad*2, h + pad*2;
                    .paint: :fill, :stroke;
                }
            }
        }
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
    if self!height-remaining <  $.lines-before * $.line-height {
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

method !finish-page {
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

# we're currently throwing code formatting away
multi sub pod2text-code(Pod::Block $pod) {
    $pod.contents.map(&pod2text-code).join;
}
multi sub pod2text-code(Str $pod) { $pod }

sub pod2text-inline($pod) {
    pod2text($pod).subst(/\s+/, ' ', :g);
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

    $ raku --doc=PDF::Lite lib/to/class.rakumod | xargs xpdf

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
    $ raku --doc=PDF::Lite lib/to/class.rakumod | xargs xpdf
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
    $pdf.save-as: "class.pdf"
    =end code

=head2 Restrictions

L<PDF::Lite> minimalism, including:

=item PDF Core Fonts only
=item no Table of Contents or Index
=item no Links
=item no Syntax Highlighting
=item no Marked Content/Accessibility

=end pod
