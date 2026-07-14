use strict;
use warnings;
use utf8;

# Built-in query functions, invoked from a query as `name(query; arg)`,
# e.g. `newest(todo, -=done; 3)`. Each arkfunc_NAME sub is called with
# (inner_query, arg, \@records, $run_query) where $run_query->($q) runs
# a query the same way the main engine would; it returns the subset of
# matching records to keep, in whatever order they should be printed.
# Custom functions can be added the same way via .arkrc's [functions] or
# inline [function NAME] sections -- see bin/ark's eval_query_function.

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
