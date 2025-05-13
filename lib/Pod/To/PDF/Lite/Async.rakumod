#| multi-threaded rendering mode
unit class Pod::To::PDF::Lite::Async:ver<0.1.11>;

use Pod::To::PDF::Lite;
also is Pod::To::PDF::Lite;

use Pod::To::PDF::Lite::Async::Scheduler;
use PDF::Content::PageTree;

method read(@pod, |c) {
    my List @batches = Pod::To::PDF::Lite::Async::Scheduler.divvy(@pod).map: -> $pod {
        ($pod, PDF::Content::PageTree.pages-fragment);
    }
    my @results;

    if +@batches == 1 {
        # avoid creating sub-trees
        @results[0] = self.read-batch: @pod, $.pdf.Pages, |c;
    }
    else {
        my @results = @batches.hyper(:batch(1)).map: {
            self.read-batch: |$_, |c;
        }

        $.pdf.add-pages(.[1]) for @batches;
    }
    $.merge-batch($_) for @results;
}

