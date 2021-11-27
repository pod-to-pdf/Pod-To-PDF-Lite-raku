class Pod::To::PDF::Lite:ver<0.0.1> {

    use PDF;
    use PDF::Lite;
    use PDF::Content;
    use PDF::Content::Text::Box;
    use Pod::To::PDF::Lite::Style;
    use Pod::To::Text;

    subset Level of Int:D where 1..6;

    has PDF::Lite $.pdf .= new;
    has PDF::Lite::Page $!page;
    has PDF::Content $!gfx;
    has UInt $!indent = 0;
    has Pod::To::PDF::Lite::Style $.style handles<line-height font font-size leading bold invisible italic mono> .= new;
    has $!x;
    has $!y;
    has $.margin = 10;
    has $!collapse;

    submethod TWEAK {
        given $!pdf.Info //= {} {
            .CreationDate //= DateTime.now;
            .Producer //= "{self.^name}-{self.^ver}";
            .Creator //= "PDF::Lite-{PDF::Lite.^ver}; PDF::Content-{PDF::Content.^ver}; PDF-{PDF.^ver}";
        }
        self!new-page()
    }

    method render($class: $pod, |c) {
	pod2pdf($pod, :$class, |c).Str;
    }

    sub pod2pdf($pod, :$class = $?CLASS, :$toc = True) is export {
        my $obj = $class.new;
        $obj.pod2pdf($pod);
        $obj.pdf;
    }

    multi method pod2pdf(Pod::Block::Named $pod) {
        given $pod.name {
            when 'pod'  { $.pod2pdf($pod.contents)     }
            when 'para' {
                self!nest: {
                    $.pod2pdf: $pod.contents;
                }
            }
            when 'config' { }
            when 'nested' {
                self!nest: {
                    $!indent++;
                    $.pod2pdf: $pod.contents;
                }
            }
            default     {
                warn $pod.WHAT.raku;
                $.say($pod.name);
                $.pod2pdf($pod.contents)
            }
        }
    }

    multi method pod2pdf(Pod::Block::Code $pod) {
        $.say;
        self!code: $pod.contents.join;
    }

    multi method pod2pdf(Pod::Heading $pod) {
        $.say;
        my Level $level = min($pod.level, 6);
        self!heading( node2text($pod.contents), :$level);
    }

    multi method pod2pdf(Pod::Block::Para $pod) {
        $.say;
        $.pod2pdf($pod.contents);
    }

    multi method pod2pdf(Pod::FormattingCode $pod) {
        given $pod.type {
            when 'I' {
                temp $.italic = True;
                $.pod2pdf($pod.contents);
            }
            when 'B' {
                temp $.bold = True;
                $.pod2pdf($pod.contents);
            }
            when 'Z' {
                temp $.invisible = True;
                $.pod2pdf($pod.contents);
            }
            when 'L' {
                my $x = $!x;
                my $y = $!y;
                my $text = $pod.contents.join;
                $.print($text);
            }
            default {
                warn "todo: POD formatting code: $_";
                $.pod2pdf($pod.contents);
            }
        }
    }

    multi method pod2pdf(Pod::Item $pod) {
        $.say;
        self!nest: {
            my constant BulletPoints = ("\c[BULLET]", "\c[WHITE BULLET]", '-');
            my Level $list-level = min($pod.level // 1, 3);
            my $bp = BulletPoints[$list-level - 1];
            .print: $bp, |self!text-position;

            $!collapse = True;
            $!indent++;
            $.pod2pdf($pod.contents);
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

        self!heading($type.tclc ~ ' ' ~ $name, :$level);

        if $code {
            self!code($decl ~ ' ' ~ $code);
        }

        if $pod.contents {
            $.say;
            $.pod2pdf($pod.contents);
        }

        $.say;
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

    multi method pod2pdf(List $pod) {
        for $pod.list {
            $.pod2pdf($_);
        };
    }

    multi method pod2pdf(Str $pod) {
        $.print($pod);
    }

    multi method pod2pdf($pod) is default {
        warn "fallback render of {$pod.WHAT.raku}";
        $.say: pod2text($pod);
    }

    multi method say {
        $!x = 0;
        $!y -= $.line-height
            unless $!collapse;
    }
    multi method say(Str $text, |c) {
        $.print($text, :nl, |c);
    }

    method print(Str $text, Bool :$nl, |c) {
        my $gfx = self!gfx;
        my $width = $!gfx.canvas.width - self!indent - $!margin - $!x;
        my $height = $!y - $!margin;
        
        $!collapse = False;
        my PDF::Content::Text::Box $tb .= new: :$text, :$width, :$height, :indent($!x), :$.leading, :$.font, :$.font-size, |c;
        $gfx.print: $tb, |self!text-position(), :$nl
            unless $.invisible;

        if $tb.overflow {
            $.say() unless $nl;
            $.print: $tb.overflow.join;
        }
        else {
            # calculate text bounding box and advance x, y
            my $lines = +$tb.lines;
            $lines-- if $lines && !$nl;
            $!y -= $lines * $.line-height;
            if $lines {
                $!x = 0;
            }
            $!x += $tb.lines.tail.content-width + $tb.space-width
                unless $nl;
        }
    }

    method !text-position {
        :position[$!margin + self!indent, $!y]
    }

    method !nest(&codez) {
        temp $!style .= clone;
        temp $!indent;
        &codez();
    }

    method !heading(Str:D $Title, Level :$level = 2) {
        constant HeadingSizes = 20, 16, 13, 11.5, 10, 10;
        $.say if $level <= 2;
        self!nest: {
            $.font-size = HeadingSizes[$level - 1];
            if $level < 5 {
                $.bold = True;
            }
            else {
                $.italic = True;
            }

            $.say: $Title;
        }
    }
    method !code(Str $raw) {
        $.say;
        self!nest: {
            $.mono = True;
            $.font-size *= .8;
            $!indent++;
            $.say($raw, :verbatim);
        }
    }

    method !gfx {
        if $!y <= 2 * $!margin {
            self!new-page;
        }
        elsif $!x > 0 && $!x > $!gfx.canvas.width - self!indent - $!margin {
            $!collapse = False;
            self.say;
        }
        $!gfx;
    }
    method !new-page {
        $!page = $!pdf.add-page;
        $!gfx = $!page.gfx;
        $!x = 0;
        $!y = $!page.height - 2 * $!margin;
        # suppress whitespace before significant content
        $!collapse = True;
    }

    method !indent {
        10 * $!indent;
    }

    multi sub node2text(Pod::Block $_) { node2text(.contents) }
    multi sub node2text(@pod) { @pod.map(&node2text).join: ' ' }
    multi sub node2text(Str() $_) { .trim }
}

=NAME
Pod::To::PDF::Lite - Basic Pod to PDF Renderer

=begin SYNOPSIS
From command line:

    $ raku --doc=PDF::Lite lib/to/class.rakumod >to-class.pdf

From Raku:
    =begin code :lang<raku>
    use Pod::To::PDF::Lite;

    =NAME
    foobar.pl

    =SYNOPSIS
        foobar.pl <options> files ...

    pod2pdf($=pod).save-as: "foobar.pdf";
    =end code
=end SYNOPSIS

=begin EXPORTS
    class Pod::To::PDF;
    sub pod2pdf; # See below
=end EXPORTS

=begin DESCRIPTION
This is a mimimalistic module for rendering POD to PDF.

The pdf2pdf() function returns a PDF::Lite object which can be further
manipulated, or saved to a PDF file.

    pod2pdf($=pod).save-as: "class.pdf"
                
The render() method returns a byte string which can be written to a
`latin-1` encoded file.

    "class.pdf".IO.spurt: Pod::To::PDF.render($=pod), :enc<latin-1>;


=end DESCRIPTION
