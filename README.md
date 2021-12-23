NAME
====

Pod::To::PDF::Lite - Pod to PDF draft renderer

SYNOPSIS
========

From command line:

    $ raku --doc=PDF::Lite lib/to/class.rakumod | xargs xpdf

From Raku:

```raku
use Pod::To::PDF::Lite;

=NAME
foobar.pl

=SYNOPSIS
    foobar.pl <options> files ...

pod2pdf($=pod).save-as: "foobar.pdf";
```

EXPORTS
=======

    class Pod::To::PDF::Lite;
    sub pod2pdf; # See below

DESCRIPTION
===========

Renders Pod to PDF draft documents via PDF::Lite.

From command line:

```shell
$ raku --doc=PDF::Lite lib/to/class.rakumod | xargs xpdf
```

From Raku code, the `pod2pdf` function returns a [PDF::Lite](PDF::Lite) object which can be further manipulated, or saved to a PDF file.

```raku
use Pod::To::PDF::Lite;
use PDF::Lite;

=NAME
foobar.raku

=SYNOPSIS
    foobarraku <options> files ...

my PDF::Lite $pdf = pod2pdf($=pod);
$pdf.save-as: "class.pdf"
```

RESTRICTIONS
============



[PDF::Lite](PDF::Lite) minimalism, including:

  * PDF Core Fonts only

  * no Table of Contents or Index

  * no Links

  * no Synax Highlighting

  * no Marked Content/Accessibility

