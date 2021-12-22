# Pod::To::PDF::Lite (Raku)

Render Pod as a minimal draft PDF file.

## Installation

Using zef:
```
$ zef install Pod::To::PDF::Lite
```

## Usage:

From command line:

    $ raku --doc=PDF::Lite lib/class.rakumod | xargs xpdf

From Raku:

```
use Pod::To::PDF::Lite;
use PDF::Lite;

=NAME
foobar.raku

=SYNOPSIS
    foobarraku <options> files ...

my PDF::Lite $pdf = pod2pdf($=pod);
$pdf.save-as: "class.pdf";
```
## Restrictions
Produces mimimalistic PDF files via [PDF::Lite](https://pdf-raku.github.io/PDF-Lite-raku):
- PDF Core Fonts only
- no Table of Contents or Index
- no Links
- no PDF Tagging

## See Also
- [PDF::Lite](https://pdf-raku.github.io/PDF-Lite-raku) - minimal PDF manipulation

