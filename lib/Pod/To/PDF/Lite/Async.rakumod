#| multi-threaded rendering mode
unit class Pod::To::PDF::Lite::Async:ver<0.1.14>;

use Pod::To::PDF::Lite;
also is Pod::To::PDF::Lite;

method read(@pod, |c) is DEPRECATED('Pod::To::PDF.read: @pod, :async, |c') {
    nextwith(@pod, |c, :async);
}
