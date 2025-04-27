use v6;

use Test;
use Pod::To::PDF::Lite;
use PDF::Lite;

plan 1;

my PDF::Lite $pdf = pod2pdf($=pod);
$pdf.id = $*PROGRAM.basename.fmt('%-16.16s');

$pdf<Info>:delete; # because this is variable
lives-ok {$pdf.save-as: "t/code.pdf", :!info;}

=begin pod
asdf

    indented

asdf

    indented
    multi
    line

asdf

    indented
    multi
    line
    
        nested
    and
    broken
    up

asdf

=code Abbreviated

asdf

=for code
Paragraph
code

asdf

=begin code
Delimited
code
=end code

asdf

=begin code :allow<B>
B<Formatted>
code
=end code

=end pod
