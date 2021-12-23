class Pod::To::PDF::Lite:ver<0.0.1> {
    use PDF::Lite;
    use PDF::Content;
    use PDF::Content::Color :&color;
    use PDF::Content::Text::Box;
    use Pod::To::PDF::Lite::Style;
    use Pod::To::Text;
    use File::Temp;

    subset Level of Int:D where 1..6;

    has PDF::Lite $.pdf is built .= new;
    has PDF::Lite::Page $!page;
    has PDF::Content $!gfx;
    has UInt $!indent = 0;
    has Pod::To::PDF::Lite::Style $.style handles<font font-size leading line-height bold italic mono underline lines-before link> .= new;
    has ($!tx, $!ty); # current text-flow x, y position
    has $.margin = 20;
    has UInt $!pad = 0;

    method read($pod) {
        self.pod2pdf($pod);
    }

    submethod TWEAK(Str :$title, Str :$lang = 'en', :$pod) {
        $!pdf.Root<Lang> //= $_ with $lang;
        given $!pdf.Info //= {} {
            .CreationDate //= DateTime.now;
            .Producer //= "{self.^name}-{self.^ver}";
            .Creator //= "PDF::Lite-{PDF::Lite.^ver}; PDF::Content-{PDF::Content.^ver}; PDF-{PDF.^ver}";
        }
        self.title //= $_ with $title;
        self.read($_) with $pod;
    }

    method render($class: $pod, |c) {
        my $renderer = $class.new(|c, :$pod);
        my PDF::Lite $pdf = $renderer.pdf;
        my ($file-name, ) = tempfile("pod2pdf-lite-****.pdf", :!unlink);
        $pdf.save-as: $file-name;
        $file-name;
    }

    method title is rw { $!pdf.Info.Title; }
    our sub pod2pdf($pod, :$class = $?CLASS, |c) is export {
        $class.new(|c, :$pod).pdf;
    }

    my constant vpad = 2;
    my constant hpad = 10;

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
            my $tab = $!margin + self!indent;
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
                        self!line: $tab, $y, $tab + $width;
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
                self!table-row(@overflow, @widths, :$header);
            }
            else {
                $!ty -= $row-height + vpad;
                $!ty -= $head-space if $header;
            }
        }
    }

    method !table-cell($pod) {
        my $text = pod2text($pod);
        self!text-box: $text, :width(0), :height(0), :indent(0);
    }

    method !build-table($pod, @table) {
        my $x0 = $!margin + self!indent;
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

        $.pad: {
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
            default     {
                given $pod.name {
                    when 'TITLE' {
                        my Str $title = pod2text($pod.contents);
                        self.title //= $title;
                        $.pad: {
                            self!heading: $title, :level(1);
                        }
                    }
                    when 'SUBTITLE' {
                        $.pad: {
                            self!heading: pod2text($pod.contents), :level(2);
                        }
                    }
                    default {
                        warn "unrecognised POD named block: $_";
                        $.say($_);
                        $.pod2pdf($pod.contents);
                    }
                }
            }
        } }
    }

    multi method pod2pdf(Pod::Block::Code $pod) {
        $.pad: {
            self!code: $pod.contents.join;
        }
    }

    multi method pod2pdf(Pod::Heading $pod) {
        $.pad: {
            my Level $level = min($pod.level, 6);
            self!heading( node2text($pod.contents), :$level);
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
                temp $.bold = True;
                $.pod2pdf($pod.contents);
            }
            when 'C'|'T' {
                temp $.mono = True;
                $.pod2pdf($pod.contents);
            }
            when 'I' {
                temp $.italic = True;
                $.pod2pdf($pod.contents);
            }
            when 'K' {
                temp $.italic = True;
                temp $.mono = True;
                $.pod2pdf($pod.contents);
            }
            when 'U' {
                temp $.underline = True;
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
                my $text = pod2text($pod.contents);
                given $pod.meta.head // $text -> $uri {
                    temp $.link = True;
                    $.print($text);
                }
            }
            default {
                warn "todo: POD formatting code: $_";
                $.pod2pdf($pod.contents);
            }
        }
    }

    multi method pod2pdf(Pod::Item $pod) {
        $.pad: {
            my constant BulletPoints = ("\c[BULLET]",
                                        "\c[WHITE BULLET]",
                                        '-');
            my Level $list-level = min($pod.level // 1, 3);
            my $bp = BulletPoints[$list-level - 1];
            $.print: $bp;

            # slightly iffy $!ty fixup
            $!ty += 2 * $.line-height;

            self!style: :indent, {
                $.pod2pdf($pod.contents);
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

        $.pad: {
            self!style: :lines-before(3), {
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
    }

    multi method pod2pdf(Pod::Block::Comment) {
        # do nothing
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
        $!tx = 0;
        $!ty -= $.line-height;
    }
    multi method say(Str $text, |c) {
        @.print($text, :nl, |c);
    }

    multi method pad(&codez) { $.pad; &codez(); $.pad}
    multi method pad($!pad = 2) { }
    method !text-box(
        Str $text,
        :$width = self!gfx.canvas.width - self!indent - 2*$!margin,
        :$height = $!ty - $!margin,
        |c) {
        PDF::Content::Text::Box.new: :$text, :indent($!tx), :$.leading, :$.font, :$.font-size, :$width, :$height, |c;
    }

    method !pad-here {
        $.say for ^$!pad;
        $!pad = 0;
    }
    method print(Str $text, Bool :$nl, |c) {
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

        if $tb.overflow {
            $.say() unless $nl;
            @.print: $tb.overflow.join;
        }
        else {
            # calculate text bounding box and advance x, y
            my $lines = +$tb.lines;
            my $x0 = $pos.value[0];
            if $nl {
                # advance to next line
                $!tx = 0;
            }
            else {
                $!tx = 0 if $tb.lines > 1;
                $x0 += $!tx;
                # continue this line
                with $tb.lines.pop {
                    $w = .content-width - .indent;
                    $!tx += $w + $tb.space-width;
                }
            }
            $!ty -= $tb.content-height;
            ($x0, $!ty, $w, $h);
        }
    }

    method !text-position {
        :position[$!margin + self!indent, $!ty]
    }

    method !style(&codez, Bool :$indent, |c) {
        temp $!style .= clone: |c;
        temp $!indent;
        $!indent += 1 if $indent;
        &codez();
    }

    method !heading(Str:D $Title, Level :$level = 2, :$underline = $level == 1) {
        self!style: :$underline, {
            my constant HeadingSizes = 20, 16, 13, 11.5, 10, 10;
            $.font-size = HeadingSizes[$level - 1];
            if $level == 1 {
                self!new-page;
            }
            elsif $level == 2 {
                $.lines-before = 3;
            }

            if $level < 5 {
                $.bold = True;
            }
            else {
                $.italic = True;
            }

            @.say($Title);
        }
    }

    method !code(Str $raw is copy) {
        self!style: :mono, :indent, {
            $raw .= chomp;
            $.lines-before = min(+$raw.lines, 3);
            my constant \pad = 5;
            $.font-size *= .8;
            my (\x, \y, \w, \h) = @.say($raw, :verbatim);

            my $x0 =  self!indent + $!margin;
            my $width = $!gfx.canvas.width - $!margin - $x0;
            $!gfx.graphics: {
                constant \pad = 2;
                .FillColor = color 0;
                .StrokeColor = color 0;
                .FillAlpha = 0.1;
                .StrokeAlpha = 0.25;
                .Rectangle: $x0 - pad, y - pad, $width, h + 2*pad + $.line-height;
                .paint: :fill, :stroke;
            }
        }
    }

    method !line($x0, $y0, $x1, $y1 = $y0, :$linewidth = 1) {
        given $!gfx {
            .Save;
            .SetLineWidth: $linewidth;
            .MoveTo: $x0, $y0;
            .LineTo: $x1, $y1;
            .Stroke;
            .Restore;
        }
    }

    method !underline(PDF::Content::Text::Box $tb, :$tab = $!margin + self!indent, ) {
        my $y = $!ty + $tb.underline-position;
        my $linewidth = $tb.underline-thickness;
        for $tb.lines {
            my $x0 = $tab + .indent;
            my $x1 = $tab + .content-width;
            self!line($x0, $y, $x1, :$linewidth);
            $y -= .height * $tb.leading;
        }
    }

    method !gfx {
        my $y = $!ty - $.lines-before * $.line-height;
        if !$!page.defined || $y <= 2 * $!margin {
            self!new-page;
        }
        elsif $!tx > 0 && $!tx > $!gfx.canvas.width - self!indent - $!margin {
            self.say;
        }
        $!gfx;
    }

    method !new-page {
        $!page = $!pdf.add-page;
        $!gfx = $!page.gfx;
        $!tx = 0;
        $!ty = $!page.height - 2 * $!margin;
        # suppress whitespace before significant content
        $!pad = 0;
    }

    method !indent {
        10 * $!indent;
    }

    multi sub node2text(Pod::Block $_) { node2text(.contents) }
    multi sub node2text(@pod) { @pod.map(&node2text).join: ' ' }
    multi sub node2text(Str() $_) { .trim }
}

=begin pod
=NAME
Pod::To::PDF::Lite - Pod to PDF draft renderer

=SYNOPSIS
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

=EXPORTS
    class Pod::To::PDF::Lite;
    sub pod2pdf; # See below

=DESCRIPTION
Renders Pod to PDF draft documents via PDF::Lite.

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

=RESTRICTIONS

L<PDF::Lite> minimalism, including:

=item PDF Core Fonts only
=item no Table of Contents or Index
=item no Links
=item no Synax Highlighting
=item no Marked Content/Accessibility

=end pod
