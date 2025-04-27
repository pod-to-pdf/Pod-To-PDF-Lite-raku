#| Basic core-font styler
unit class Pod::To::PDF::Lite::Style;

use PDF::Content::Font::CoreFont;
use PDF::Content::FontObj;

has Bool $.bold;
has Bool $.italic;
has Bool $.underline;
has Bool $.mono;
has Bool $.verbatim;
has Numeric $.font-size = 12;
has UInt $.lines-before = 1;
has Bool $.link;
has PDF::Content::FontObj $.font;

my Lock:D $lock .= new;

method leading { 1.1 }
method line-height {
    $.leading * $!font-size;
}
constant %CoreFont = %(
    # Normal Fonts           # Mono Fonts
    :___<times>,             :__M<courier>,  
    :B__<times-bold>,        :B_M<courier-bold>,
    :_I_<times-italic>,      :_IM<courier-oblique>,
    :BI_<times-bolditalic>,  :BIM<courier-boldoblique>
);
my subset FontKey of Str where %CoreFont{$_}:exists;
method font-key {
    (
        ($!bold ?? 'B' !! '_'),
        ($!italic ?? 'I' !! '_'),
        ($!mono ?? 'M' !! '_'),
    ).join;
}

method clone { nextwith :font(PDF::Content::FontObj), |%_; }

method font(:%font-map) {
    $!font //= do {
        my FontKey:D $key = self.font-key;
        $lock.protect: {
            %font-map{$key} //= do {
                my Str:D $font-name = %CoreFont{$key};
                PDF::Content::Font::CoreFont.load-font($font-name);
            }
        }
    }
}
