unit class Pod::To::PDF::Lite::Writer is rw;

use PDF::Lite;
use PDF::Content;
use Pod::To::PDF::Lite::Style;

my constant Gutter = 1;

has PDF::Lite::Page $.page;
has PDF::Content $.gfx;
has Pod::To::PDF::Lite::Style $.style .= new;
has UInt:D $.level = 1;
has $.gutter = Gutter;
has UInt $.padding = 0;
has UInt $.indent = 0;
has $.margin = 20;
has $.tx = $!margin; # text-flow x
has $.ty; # text-flow y
has Numeric $.code-start-y;
has @.footnotes;

method new-line {
    $!tx = $!margin;
    $!ty -= $!style.line-height;
}
multi method pad(&codez) { $!padding=2; &codez(); $!padding=2}
method new-page($pdf) {
    $.gutter = Gutter;
    $!page = $pdf.add-page;
    $!gfx = $!page.gfx;
    $!tx = $.margin;
    $!ty = $!page.height - 2 * $!margin;
    # suppress whitespace before significant content
    $!padding = 0;
}
