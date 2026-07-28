#!/usr/bin/env perl
# Shared by bin/ark and every lib/ark/commands/* script, so metadata
# parsing and .arkrc loading exist in exactly one place instead of being
# reimplemented per entry point. require'd, not use'd -- it executes in
# the caller's (main) package, same pattern as arkfuncs.pl.
use strict;
use warnings;
use utf8;

# ============================================================
# METADATA GRAMMAR
#
# A metadata token (one ';'-separated piece of a {...} block) is one of:
#
#   1. Canonical: the first character is one of the fixed 12 below --
#      sym is that character, val is everything after it, verbatim
#      (including any colons). This set is closed; it will not grow.
#        #  tag       !  priority   %  deadline
#        =  status     $  authour    @  assignee
#        /  title      ~  created    &  id
#        >  start       <  end        ^  recurrence
#
#   2. Named: the first character isn't canonical, and the token
#      contains a colon -- sym is everything before the FIRST colon,
#      val is everything after it. e.g. `time:00:10` -> sym=time,
#      val=00:10. Any key name works; nothing needs to be registered.
#
#   3. Unclaimed: the first character isn't canonical and there's no
#      colon at all -- the whole token becomes the value of whatever
#      key .arkrc's [defaults] unclaimed= names ('#', a tag, if unset).
#      e.g. with the default unclaimed=#, a bare `sermon` token is
#      exactly equivalent to `#sermon`.
#
# Order matters: canonical is checked before colon-splitting, so a
# canonical token's own value (a title, an ISO datetime, an assignee
# name) can safely contain a colon without being misread as a named
# field -- `/Meeting: budget review` stays a title, not a "Meeting" key.
#
# Nothing here is ever rejected -- every token maps to something.
# ============================================================

our @CANONICAL_META_SYMS = split //, '#!%=$@/~&><^';
our %IS_CANONICAL_META_SYM = map { $_ => 1 } @CANONICAL_META_SYMS;

# Set once per process by each entry point, right after loading .arkrc
# (see resolve_unclaimed_key below). parse_meta_token() falls back to
# '#' on its own if nothing has set this yet.
our $UNCLAIMED_KEY = '#';

sub ark_trim {
    my ($s) = @_;
    $s //= "";
    $s =~ s/^\s+|\s+$//g;
    return $s;
}

sub ark_expand_base_path {
    my ($path) = @_;
    $path = ark_trim($path);

    if ($path =~ /^~(?=\/|$)/) {
        my $home = $ENV{HOME} || (getpwuid($<))[7] || ".";
        $path =~ s/^~/$home/;
    }

    return $path;
}

sub parse_meta_token {
    my ($tok) = @_;

    if ($tok =~ m{^id/(.+)}) {
        return { raw => $tok, sym => "id/", val => $1 };
    }

    my $first = substr($tok, 0, 1);

    if ($IS_CANONICAL_META_SYM{$first}) {
        return { raw => $tok, sym => $first, val => substr($tok, 1) };
    }

    my $colon = index($tok, ':');

    if ($colon >= 0) {
        my $key = substr($tok, 0, $colon);
        my $val = substr($tok, $colon + 1);
        return { raw => "$key:$val", sym => $key, val => $val };
    }

    my $key = (defined $UNCLAIMED_KEY && length $UNCLAIMED_KEY) ? $UNCLAIMED_KEY : '#';
    my $raw = $IS_CANONICAL_META_SYM{$key} ? "$key$tok" : "$key:$tok";

    return { raw => $raw, sym => $key, val => $tok };
}

sub parse_meta {
    my ($raw) = @_;
    my @items;
    return @items unless defined $raw;

    for my $tok (split /\s*;\s*/, ark_trim($raw)) {
        next unless length $tok;
        push @items, parse_meta_token($tok);
    }

    return @items;
}

# For callers (tidy) that work with flat raw token strings rather than
# {sym,val,raw} hashrefs.
sub parse_meta_raw {
    my ($raw) = @_;
    return map { $_->{raw} } parse_meta($raw);
}

sub norm_tag {
    my ($s) = @_;

    $s = ark_trim($s // "");
    $s =~ s/^#//;
    $s = lc $s;
    $s =~ s/[^a-z0-9_-]+/-/g;
    $s =~ s/^-+|-+$//g;

    return $s;
}

# ============================================================
# .arkrc
#
# ini-style config, sections:
#   [bases]           one extra search directory per line
#   [defaults]        #=/unclaimed=/authour=/assignee=/output=/repo=/
#                      no_publish=, see README
#   [queries]         name = query, indented continuation lines appended
#                      to the same alias
#   [functions]       name = path/to/file.pl (require'd, must define
#                      arkfunc_NAME)
#   [function NAME]   inline Perl body for arkfunc_NAME, read verbatim
#                      until the next [section]
#   [publish]         one tag name per line, used by `ark publish`
#
# A line starting with '#' is a comment UNLESS it's immediately followed
# by '=' (no space): '#=general' is the tag default, '# a comment' is a
# comment. This is the one place the canonical '#' symbol collides with
# ini comment syntax, since '#' is both a metadata symbol and the
# traditional start-of-comment character.
# ============================================================

# Pre-key:value .arkrc files used tag=/authour=/assignee= instead of
# #=/$=/@=. Currently only tag=/#= is actually renamed in practice (the
# others were never asked to change), but the alias mechanism is
# generic: an old-style key keeps working as a fallback for its
# canonical-symbol key, so nobody's existing .arkrc breaks.
our %DEFAULTS_KEY_ALIAS = (
    tag => '#',
);

# Keys ensure_arkrc_defaults() guarantees exist in an existing .arkrc's
# [defaults] section, appended once the first time a new-enough ark runs
# against an older repo. unclaimed= is the only one that's actually
# load-bearing (parse_meta_token already falls back to '#' in memory if
# it's absent) -- writing it out anyway keeps .arkrc an honest,
# inspectable record of what's configured, rather than a value that
# only ever exists as an invisible in-code fallback.
our @ENSURE_DEFAULTS = (
    ['unclaimed', '#'],
);

sub is_comment_line {
    my ($line) = @_;
    return $line =~ /^#/ && $line !~ /^#=/;
}

sub load_arkrc {
    my ($path) = @_;
    $path = ".arkrc" unless defined $path;

    my %config = (
        bases            => ["."],
        functions        => {},
        inline_functions => [],
        queries          => {},
        defaults         => {},
        publish_tags     => [],
    );

    return %config unless -f $path;

    ensure_arkrc_defaults($path);

    open my $fh, "<:encoding(UTF-8)", $path or return %config;

    my $section = "";
    my $inline_name = "";
    my $inline_code = "";
    my $query_name = "";

    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\r$//;

        if ($section eq "queries" && $query_name && $line =~ /^\s+(.+)$/) {
            $config{queries}{$query_name} .= " " . ark_trim($1);
            next;
        }

        if ($line =~ /^\s*\[(.+)\]\s*$/) {
            $query_name = "";

            if ($section eq "function" && length $inline_code) {
                push @{$config{inline_functions}}, {
                    name => $inline_name,
                    code => $inline_code,
                };
                $inline_code = "";
                $inline_name = "";
            }

            my $header = ark_trim($1);

            if ($header =~ /^function\s+(\w+)$/) {
                $section = "function";
                $inline_name = $1;
            } else {
                $section = lc $header;
            }

            next;
        }

        if ($section eq "function") {
            $inline_code .= $line . "\n";
            next;
        }

        $line = ark_trim($line);
        next unless length $line;
        next if is_comment_line($line);

        if ($section eq "bases") {
            push @{$config{bases}}, ark_expand_base_path($line);
        }
        elsif ($section eq "functions") {
            my ($name, $fpath) = split /\s*=\s*/, $line, 2;
            next unless $name && $fpath;
            $config{functions}{$name} = ark_expand_base_path($fpath);
        }
        elsif ($section eq "queries") {
            my ($name, $query) = split /\s*=\s*/, $line, 2;
            next unless $name;
            $query //= "";

            $config{queries}{$name} = $query;
            $query_name = $name;
        }
        elsif ($section eq "defaults") {
            my ($name, $val) = split /\s*=\s*/, $line, 2;
            next unless $name;
            $config{defaults}{$name} = ark_trim($val // "");
        }
        elsif ($section eq "publish") {
            my $tag = $line;

            if ($tag =~ /^\s*([A-Za-z0-9_-]+)\s*=\s*(.*?)\s*$/) {
                $tag = length($2) ? $2 : $1;
            }

            $tag = norm_tag($tag);
            push @{$config{publish_tags}}, $tag if length $tag;
        }
    }

    if ($section eq "function" && length $inline_code) {
        push @{$config{inline_functions}}, {
            name => $inline_name,
            code => $inline_code,
        };
    }

    close $fh;

    if (@{$config{bases}} > 1) {
        shift @{$config{bases}} if $config{bases}[0] eq ".";
    }

    my %seen_tag;
    @{$config{publish_tags}} = grep { !$seen_tag{$_}++ } @{$config{publish_tags}};

    # Old-style keys keep working: they fill their aliased canonical-
    # symbol key only if that key wasn't already set directly.
    for my $old (keys %DEFAULTS_KEY_ALIAS) {
        my $new = $DEFAULTS_KEY_ALIAS{$old};
        next unless exists $config{defaults}{$old};
        next if exists $config{defaults}{$new} && length $config{defaults}{$new};
        $config{defaults}{$new} = $config{defaults}{$old};
    }

    return %config;
}

# Appends any of @ENSURE_DEFAULTS missing from an existing .arkrc's
# [defaults] section. Never touches or reorders anything already there
# -- an old-style key counts as already satisfying its aliased new key
# (see DEFAULTS_KEY_ALIAS), so nothing is ever duplicated. No-ops
# (no write at all) once every default is already present.
sub ensure_arkrc_defaults {
    my ($path) = @_;

    open my $fh, "<:encoding(UTF-8)", $path or return;
    my @lines = <$fh>;
    close $fh;

    my $section = "";
    my %present;
    my $defaults_at = -1; # index of the [defaults] header line
    my $insert_at   = -1; # index to splice new lines in before

    for my $i (0 .. $#lines) {
        my $l = $lines[$i];
        $l =~ s/[\r\n]+$//;

        if ($l =~ /^\s*\[(.+)\]\s*$/) {
            if ($defaults_at >= 0 && $insert_at < 0) {
                $insert_at = $i;
            }

            $section = lc ark_trim($1);
            $defaults_at = $i if $section eq "defaults" && $defaults_at < 0;
            next;
        }

        next unless $section eq "defaults";

        my $t = ark_trim($l);
        next unless length $t;
        next if is_comment_line($t);
        $present{ark_trim($1)} = 1 if $t =~ /^([^=]+)=/;
    }

    $insert_at = scalar(@lines) if $defaults_at >= 0 && $insert_at < 0;

    # Land right after the last non-blank defaults line, not after any
    # blank line(s) separating the block from what follows.
    while ($insert_at > $defaults_at + 1
        && $lines[$insert_at - 1] =~ /^\s*$/) {
        $insert_at--;
    }

    my %alias_target = reverse %DEFAULTS_KEY_ALIAS;
    my @missing;

    for my $pair (@ENSURE_DEFAULTS) {
        my ($key, $default_val) = @$pair;
        next if $present{$key};
        next if defined $alias_target{$key} && $present{ $alias_target{$key} };
        push @missing, "$key=$default_val";
    }

    return unless @missing;

    if ($defaults_at < 0) {
        push @lines, "\n" if @lines;
        push @lines, "[defaults]\n";
        push @lines, "$_\n" for @missing;
    } else {
        splice @lines, $insert_at, 0, map { "$_\n" } @missing;
    }

    open my $out, ">:encoding(UTF-8)", $path or return;
    print $out @lines;
    close $out;
}

# Resolves the effective unclaimed-token key from a loaded config,
# falling back to '#'. Call once right after load_arkrc() and assign
# the result to $UNCLAIMED_KEY before any parse_meta() calls.
sub resolve_unclaimed_key {
    my (%config) = @_;
    my $v = $config{defaults}{unclaimed};
    return (defined $v && length $v) ? $v : '#';
}

1;
