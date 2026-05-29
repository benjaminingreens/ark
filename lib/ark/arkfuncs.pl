use strict;
use warnings;
use utf8;

sub arkfunc_newest {
    my ($query, $n, $records_ref, $run_query) = @_;
    my @matches = $run_query->($query);

    @matches = sort {
        meta_sort_value($b, "~") cmp meta_sort_value($a, "~")
    } @matches;

    $n = int($n);
    return () if $n <= 0 || !@matches;

    return @matches[0 .. ($n - 1 > $#matches ? $#matches : $n - 1)];
}

sub arkfunc_oldest {
    my ($query, $n, $records_ref, $run_query) = @_;
    my @matches = $run_query->($query);

    @matches = sort {
        meta_sort_value($a, "~") cmp meta_sort_value($b, "~")
    } @matches;

    $n = int($n);
    return () if $n <= 0 || !@matches;

    return @matches[0 .. ($n - 1 > $#matches ? $#matches : $n - 1)];
}

sub arkfunc_random {
    my ($query, $n, $records_ref, $run_query) = @_;
    my @matches = $run_query->($query);

    @matches = sort { rand() <=> rand() } @matches;

    $n = int($n);
    return () if $n <= 0 || !@matches;

    return @matches[0 .. ($n - 1 > $#matches ? $#matches : $n - 1)];
}

1;
