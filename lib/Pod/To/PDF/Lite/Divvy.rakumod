#| divides a larger Pod document into sections for concurrent processing
unit class Pod::To::PDF::Lite::Divvy
    does Iterator;

=begin pod

=head2 Description

This iterator class breaks a larger Pod document into approximately equal
multi-page chunks for concurrent processing

=end pod

has $.complexity = 2500; # tyipcally gives us chunks of around 12 -15 pages
has $!idx = 0;
has @.pod;

multi sub pod-cost(Str:D $pod) { $pod.chars }
multi sub pod-cost(@pod) { @pod.map({pos-cost($_)}).sum }
multi sub pod-cost(Pod::Block $pod) { 10 + pod-cost($pod.contents) }

method pull-one {
    if $!idx >= @!pod {
        IterationEnd;
    }
    else {
        my @chunk;
        my $cost = 0;
        while $!idx < @!pod {
            $cost += pod-cost(@!pod[$!idx]);
            @chunk.push: @!pod[$!idx++];
            # break at next page boundary, after reaching thresehold complexity
            last if $cost >= $!complexity
            && @!pod[$!idx] ~~ Pod::Heading:D
            && @!pod[$!idx].level <= 1;
        }
        @chunk;
    }
}
