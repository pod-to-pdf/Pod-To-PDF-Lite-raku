#| Basic core-font styler
unit class Pod::To::PDF::Lite::Style is rw;

use PDF::Content::Font::CoreFont;

has Bool $.bold;
has Bool $.italic;
has Bool $.underline;
has Bool $.mono;
has Bool $.invisible;
has Numeric $.font-size = 10;

method leading { 1.1 }
method line-height {
    $.leading * $!font-size;
}
method !font-key {
    join(
        '-', 
        ($!bold ?? 'B' !! 'n'),
        ($!italic ?? 'I' !! 'n'),
        ($!mono ?? 'M' !! 'n'),
    );
}
constant %CoreFont = %(
    # Normal Fonts              # Mono Fonts
    :n-n-n<times>,             :n-n-M<courier>,  
    :B-n-n<times-bold>,        :B-n-M<courier-bold>,
    :n-I-n<times-italic>,      :n-I-M<courier-oblique>
    :B-I-n<times-boldoitalic>, :B-I-M<courier-boldoblique>
);
has %.fonts;

method font {
    my $key = self!font-key;
    %!fonts{$key} //= do {
        my Str:D $font-name = %CoreFont{$key};
        PDF::Content::Font::CoreFont.load-font($font-name);
    }
}
