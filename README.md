TITLE
=====

Pod::To::PDF::Lite

SUBTITLE
========

Pod to PDF draft renderer

Description
-----------

Renders Pod to PDF draft documents via PDF::Lite.

Usage
-----

From command line:

    $ raku --doc=PDF::Lite lib/to/class.rakumod | xargs evince

From Raku:

```raku
use Pod::To::PDF::Lite;

=NAME
foobar.pl

=SYNOPSIS
    foobar.pl <options> files ...

pod2pdf($=pod).save-as: "foobar.pdf";
```

Exports
-------

    class Pod::To::PDF::Lite;
    sub pod2pdf; # See below

From command line:

```shell
$ raku --doc=PDF::Lite lib/to/class.rakumod | xargs evince
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
$pdf.save-as: "foobar.pdf"
```

Subroutines
-----------

### sub pod2pdf()

```raku sub pod2pdf( Pod::Block $pod ) returns PDF::Lite; ```

Renders the specified Pod to a PDF::Lite object, which can then be further manipulated or saved.

**`PDF::Lite :$pdf`**

An existing PDF::Lite object to add pages to.

**`UInt:D :$width, UInt:D :$height`**

The page size in points (there are 72 points per inch).

**`UInt:D :$margin`**

The page margin in points (default 20).

**`Hash :@fonts**

By default, Pod::To::PDF::Lite uses core fonts. This option can be used to preload selected fonts.

Note: [PDF::Font::Loader](PDF::Font::Loader) must be installed, to use this option.

**`Bool :$threads`** (experimental)

Process the PDF in concurrent multi-threaded mode. This typically runs several times faster
for larger documents on a hyper-threaded quad-core. Note that the document is batched
for writing on page breaks and should thus have regular level-1 headers. 

```raku
use PDF::Lite;
use Pod::To::PDF::Lite;
need PDF::Font::Loader; # needed to enable this option

my @fonts = (
    %(:file<fonts/Raku.ttf>),
    %(:file<fonts/Raku-Bold.ttf>, :bold),
    %(:file<fonts/Raku-Italic.ttf>, :italic),
    %(:file<fonts/Raku-BoldItalic.ttf>, :bold, :italic),
    %(:file<fonts/Raku-Mono.ttf>, :mono),
);

PDF::Lite $pdf = pod2pdf($=pod, :@fonts);
$pdf.save-as: "pod.pdf";
```

Asynchronous Rendering (Experimental)
---------------------------

    $ raku --doc=PDF::Lite::Async lib/to/class.rakumod | xargs evince

This module currently includes L<Pod::To::PDF::Lite::Async>. This extends L<Pod::To::PDF::Lite> Pod renderer, adding the
ability to render larger documents concurrently.

For this mode to be useful, the document is likely to be of the order of dozens of pages
and include multiple level-1 headers (for batching purposes).

Restrictions
------------

[PDF::Lite](PDF::Lite) minimalism, including:

  * no Table of Contents or Index

  * no Links

  * no Marked Content/Accessibility

See Also
--------

  * [Pod::To::PDF](Pod::To::PDF) - PDF rendering via [Cairo](Cairo)

