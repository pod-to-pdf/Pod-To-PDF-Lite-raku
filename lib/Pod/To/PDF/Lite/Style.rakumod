#| Basic core-font styler
unit class Pod::To::PDF::Lite::Style is rw;

use PDF::Content::Font::CoreFont;

has Bool $.bold;
has Bool $.italic;
has Bool $.underline;
has Bool $.mono;
has Numeric $.font-size = 10;
has UInt $.lines-before = 1;
has Bool $.link;

method leading { 1.1 }
method line-height {
    $.leading * $!font-size;
}
constant %CoreFont = %(
    # Normal Fonts                 # Mono Fonts
    :n-n-n<times>,             :n-n-M<courier>,  
    :B-n-n<times-bold>,        :B-n-M<courier-bold>,
    :n-I-n<times-italic>,      :n-I-M<courier-oblique>
    :B-I-n<times-boldoitalic>, :B-I-M<courier-boldoblique>
);
my subset FontKey of Str where %CoreFont{$_}:exists;
has %.fonts;
has $!font-key;
method !font-key {
    $!font-key //= join(
        '-', 
        ($!bold ?? 'B' !! 'n'),
        ($!italic ?? 'I' !! 'n'),
        ($!mono ?? 'M' !! 'n'),
    );
}

method font {
    given self!font-key -> FontKey $key {
        %!fonts{$key} //= do {
            my Str:D $font-name = %CoreFont{$key};
            PDF::Content::Font::CoreFont.load-font($font-name);
        }
    }
}
