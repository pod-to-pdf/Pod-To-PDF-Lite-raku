#| divides a larger Pod document into sections for concurrent processing
unit class Pod::To::PDF::Lite::Scheduler
   does Iterable does Iterator;

=begin pod

=head2 Description

This iterator class breaks a larger Pod document into approximately equal
multi-page chunks for concurrent processing

=end pod

has $.complexity = 8000; # typically gives us chunks of around 10-15 pages
has $!idx = 0;
has Iterator $.pod is required;

multi sub pod-cost(Str:D $pod) { $pod.chars }
multi sub pod-cost(@pod) { @pod.map({pod-cost($_)}).sum }
multi sub pod-cost(Pod::Block $pod) { 20 + pod-cost($pod.contents) }

method pull-one {
    my @chunk;
    my $cost = 0;
    while (my $elem := $!pod.pull-one) !=:= IterationEnd {
        @chunk.push: $elem;
        # break at next page boundary, after reaching thresehold cost
        $cost += pod-cost($elem);
        last if $cost >= $!complexity
            && $elem ~~ Pod::Heading:D
            && $elem.level <= 1;
    }
    @chunk ?? @chunk !! IterationEnd;
}

method iterator(::?CLASS:D:) { self }

method divvy(@pod, |c) {
    # dereference outer '=begin pod ... =end pod' blocks
    my Seq() $seq := @pod.map: {
        $_ ~~ Pod::Block::Named && .name.starts-with('pod')
            ?? .contents.Slip
            !! $_;
    }

    my Iterator:D $pod := $seq.iterator;
    self.new: :$pod, |c;
}
