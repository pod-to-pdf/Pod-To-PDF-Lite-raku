# Pod::To::PDF::Lite (Raku)

Render Pod as PDF.

## Installation

Using zef:
```
$ zef install Pod::To::PDF::Lite
```

## Usage:

From command line:

    $ raku --doc=PDF::Lite lib/class.rakumod > class.pdf

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
