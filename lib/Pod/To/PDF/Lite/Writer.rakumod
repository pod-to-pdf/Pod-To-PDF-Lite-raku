#| An independant Pod::To::PDF writer
unit class Pod::To::PDF::Lite::Writer is rw;
#= able to work on a discrete multi-page Pod segment and write to a
#= distinct page sub-tree in an output PDF

use PDF::Content;
use PDF::Content::Color :&color;
use PDF::Content::FontObj;
use PDF::Content::Page;
use PDF::Content::PageTree;
use PDF::Content::Text::Box;
use Pod::To::PDF::Lite::Style;

my constant Gutter = 3;
my constant FooterStyle = Pod::To::PDF::Lite::Style.new: :lines-before(0), :font-size(10);
subset Level of Int:D where 0..6;

has PDF::Content::FontObj %.font-map is required;
has %.replace; # input replace patterns
has Str %.metadata; # output metadata
has PDF::Content::PageTree:D $.pages is required;
has PDF::Content::Page $!page;
has PDF::Content $.gfx;
has Pod::To::PDF::Lite::Style $.style handles<font-size leading line-height bold italic mono underline lines-before link verbatim> .= new;
has UInt:D $.level = 1;
has $!gutter = Gutter;
has Numeric $!padding = 0;
has UInt $!indent = 0;
has Numeric $.margin-left;
has Numeric $.margin-right;
has Numeric $.margin-top;
has Numeric $.margin-bottom;
has $!tx = $!margin-left; # text-flow x
has $!ty; # text-flow y
has Numeric $!code-start-y;
has @!footnotes;
has $.finish = True;
has Bool $!float;
has Numeric $!width;
has UInt:D $!pp = 0;

submethod TWEAK(Numeric:D :$margin = 20) {
    $!margin-top    //= $margin;
    $!margin-left   //= $margin;
    $!margin-bottom //= $margin;
    $!margin-right  //= $margin;
}

method write($pod) {
    self.pod2pdf($pod);
    self!finish-page;
}

multi method pad { $!padding=2*$.line-height }
multi method pad(&codez) { $.pad; &codez(); $.pad; }

method !new-page {
    self!finish-page();
    self!add-page();
}

method !width { $!width //= do $.gfx.canvas.width }

method !add-page {
    $!gutter = Gutter;
    $!page = $!pages.add-page;
    $!tx = $!margin-left;
    $!ty = $!page.height - $!margin-top - 16;
    $!padding = 0;
    $!pp++;
    $!gfx = $!page.gfx;
}

method !finish-page {
    self!finish-code
        if $!code-start-y;
    if @!footnotes {
        temp $.style = FooterStyle;
        temp $!indent = 0;
        temp $!code-start-y = Nil;
        $!tx = $!margin-left;
        $!ty = min $!ty - $.line-height / 2, self!bottom;
        $!gutter = 0;
        my $start-page = $!pp;
        self!draw-line($!margin-left, $!ty, self!width - $!margin-right, $!ty);
        while @!footnotes {
            $!padding = $.line-height;
            my $footnote = @!footnotes.shift;
            my $ind = $footnote.shift;
            self!style: :link, { self.print($ind) }; # [n]
            $!tx += 2;
            $.pod2pdf($footnote);
        }
        unless $!pp == $start-page {
            # page break in footnotes. draw closing HR
            $.say;
            my $y = $!ty + $.line-height / 2;
            self!draw-line($!margin-left, $y, self!width - $!margin-right, $y);
        }
    }

    if $!finish {
        # Finalize the page graphics. This will speed up
        # PDF construction in the main thread
        .finish with $!page;
    }
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
    @widths;
}

method !table-row(@row, @widths, Bool :$header) {
    if +@row -> \cols {
        my @overflow;
        # simple fixed column widths, for now
        my $tab = self!indent;
        my $row-height = 0;
        my $height = $!ty - $!margin-bottom;
        my $head-space = $.line-height - $.font-size;

        for ^cols {
            my $width = @widths[$_];

            if @row[$_] -> $tb is rw {
                if $tb.width > $width || $tb.height > $height {
                    $tb .= clone: :$width, :$height;
                }

                $.gfx.print: $tb, :position[$tab, $!ty], :shape;
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
    my \total-width = self!width - $x0 - $!margin-right;
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
}

multi method pod2pdf(Pod::Block::Table $pod) {
    my @widths = self!build-table: $pod, my @table;

    self!style: :lines-before(3), :pad, {
        if $pod.caption -> $caption {
            self!style: :italic, {
                $.say: $caption;
            }
        }
        self!pad-here;
        my PDF::Content::Text::Box @headers = @table.shift.List;
        if @headers {
            self!table-row: @headers, @widths, :header;
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
                %!metadata{.lc} ||= $.pod2text-inline($pod.contents);
                self!heading($pod.contents, :padding($.line-height));
            }

            default {
                my $name = $_;
                temp $!level += 1;
                if $name eq $name.uc {
                    if $name ~~ 'VERSION'|'NAME'|'AUTHOR' {
                        %!metadata{.lc} ||= $.pod2text-inline($pod.contents);
                    }
                    $.level = 2;
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
        $.level = min($pod.level, 6);
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

    %!replacing{$place-holder}:delete;
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
            my UInt:D $footnote-lines = do {
                # pre-compute footnote size
                temp $!style = FooterStyle;
                temp $!tx = $!margin-left;
                temp $!ty = $!page.height;
                temp $!indent = 0;
                my $draft-footnote = $ind ~ $.pod2text-inline($pod.contents);
                +self!text-box($draft-footnote).lines;
            }
            # force a page break, unless there's room for both the reference and the footnote
            # on the current page
            self!new-page
                unless self!height-remaining > ($footnote-lines+1) * FooterStyle.line-height;
            $!gutter += $footnote-lines;
            my @contents = $ind, $pod.contents.Slip;
            @!footnotes.push: @contents;
            self!style: :link, {  $.pod2pdf($ind); }
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
    $.pod2pdf($pod.contents.&strip-para);
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

            $!float = True;

            self!style: :indent, {
                $.pod2pdf($pod.contents.&strip-para);
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
        self!heading($type.tclc ~ ' ' ~ $name, :$level)
            if $type || $name;

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

multi method pod2pdf(Str $pod) {
    $.print($pod);
}

multi method pod2pdf(List:D $pod) {
    $.pod2pdf($_) for $pod.list;
}

multi method pod2pdf($pod) {
    warn "fallback render of {$pod.WHAT.raku}";
    $.say: $.pod2text($pod);
}

multi method say {
    $!tx = $!margin-left;
    $!ty -= $!style.line-height;
    $!padding = 0;
}
multi method say(Str $text, |c) {
    @.print($text, :nl, |c);
}

method font { $.style.font: :%!font-map }

method !text-box(
    Str $text,
    :$width = self!width - self!indent - $!margin-right,
    :$height = self!height-remaining,
    |c) {
    my $indent = $!tx - $!margin-left;
    my Bool $kern = !$.mono;
    PDF::Content::Text::Box.new: :$text, :$indent, :$.leading, :$.font, :$.font-size, :$width, :$height, :$.verbatim, :$kern, |c;
}

method !pad-here {
    if $!padding && !$!float {
        $!tx  = $!margin-left;
        $!ty -= $!padding;
    }
    $!float = False;
    $!padding = 0;
}

method print(Str $text, Bool :$nl, |c) {
    self!pad-here;
    my $gfx = $.gfx;
    my PDF::Content::Text::Box $tb = self!text-box: $text, |c;
    my Pair $pos = self!text-position();
    if $.link {
        use PDF::Content::Color :ColorName;
        $gfx.Save;
        given color Blue {
            $gfx.FillColor = $_;
            $gfx.StrokeColor = $_;
        }
    }

    $gfx.text: {
        .print: $tb, |$pos, :$nl, :shape;
        $!tx = $!margin-left;
        $!tx += .text-position[0] - self!indent
            unless $nl;
    }
    self!underline: $tb
        if $.underline;

    $gfx.Restore if $.link;

    $tb.lines.pop unless $nl;
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

method !heading($pod is copy, Level :$level = $.level, :$underline = $level <= 1, :$!padding = 2 * $.line-height) {
    my constant HeadingSizes = 28, 24, 20, 16, 14, 12, 12;
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

    self!style: :$font-size, :$bold, :$italic, :$underline, :$lines-before, :pad, {
        $.pod2pdf: strip-para($pod);
   }
}

method !finish-code {
    my constant pad = 5;
    with $!code-start-y -> $y0 {
        my $x0 = self!indent;
        my $width = self!width - $!margin-right - $x0 - 2*pad;
        $.gfx.graphics: {
            my constant Black = 0;
            .FillColor = color Black;
            .StrokeColor = color Black;
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

    $.gfx; # vivify

    self!style: :mono, :indent, :$font-size, :lines-before(0), :pad, :verbatim, {
        self!pad-here;
        my @plain-text;

        for ^@contents -> $i {
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

method gfx {
    if !$!gfx.defined || self!height-remaining < $.lines-before * $.line-height {
        self!new-page;
    }
    elsif $!tx > $!margin-right && $!tx > self!width - self!indent {
        self.say;
    }
    $!gfx;
}
method !height-remaining {
    $!ty - $!margin-bottom - $!gutter * FooterStyle.line-height;
}
method !top { $!page.height - $!margin-top - $!margin-bottom }
method !bottom { $!margin-bottom + ($!gutter-2) * FooterStyle.line-height; }

method !indent { $!margin-left  +  10 * $!indent; }

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

# to reduce the common case <Hn><P>Xxxx<P></Hn> -> <Hn>Xxxx</Hn>
multi sub strip-para(List $_ where +$_ == 1) {
    .map(&strip-para).List;
}
multi sub strip-para(Pod::Block::Para $_) {
    .contents;
}
multi sub strip-para($_) { $_ }

