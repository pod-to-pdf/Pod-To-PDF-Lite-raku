#| multi-threaded rendering mode
unit class Pod::To::PDF::Lite::Async:ver<0.1.9>;

use Pod::To::PDF::Lite;
also is Pod::To::PDF::Lite;

use Pod::To::PDF::Lite::Async::Scheduler;
use PDF::Content::PageTree;

method read(@pod, |c) {
    my List @batches = Pod::To::PDF::Lite::Async::Scheduler.divvy(@pod).map: -> $pod {
        ($pod, PDF::Content::PageTree.pages-fragment);
    }

    if +@batches == 1 {
        # avoid creating sub-trees
        self.read-batch: @pod, $.pdf.Pages, |c;
    }
    else {
        @batches.race(:batch(1)).map: {
            self.read-batch: |$_, |c;
        }

        $.pdf.add-pages(.[1]) for @batches;
    }
}

