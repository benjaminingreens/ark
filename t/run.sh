#!/usr/bin/env bash
#
# Ark regression suite. Not a golden-file diff (dates/ids are dynamic by
# design -- see bin/ark) but targeted assertions against a fresh scratch
# repo. Run from anywhere:
#
#   t/run.sh
#
# Exits 0 if everything passed, 1 otherwise (so it composes with CI).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARK_BIN="$SCRIPT_DIR/../bin/ark"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export ARK_YES=1
export ARK_NO_PROGRESS=1
export TZ=UTC
export COLUMNS=80
unset ARK_COLOR NO_COLOR ARK_COMMAND_DIR ARK_PUBLISH_TEMPLATE

pass=0
fail=0

ok() {
    pass=$((pass + 1))
}

bad() {
    fail=$((fail + 1))
    echo "FAIL: $1"
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if grep -qF -- "$needle" <<<"$haystack"; then ok; else
        bad "$desc (expected to contain: $needle)"
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if grep -qF -- "$needle" <<<"$haystack"; then
        bad "$desc (expected NOT to contain: $needle)"
    else ok; fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then ok; else
        bad "$desc (expected '$expected', got '$actual')"
    fi
}

assert_exit0() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok; else
        bad "$desc (expected exit 0)"
    fi
}

assert_exit_nonzero() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        bad "$desc (expected non-zero exit)"
    else ok; fi
}

cd "$WORK"

# ------------------------------------------------------------
# init
# ------------------------------------------------------------
out="$("$ARK_BIN" init)"
assert_contains "init reports success" "$out" "Initialised ark repository"
for d in note todo evnt; do
    [ -d "$d" ] && ok || bad "init creates $d/"
done
[ -f .ark/repo ] && ok || bad "init creates .ark/repo marker"
[ -f .arkrc ] && ok || bad "init creates .arkrc"
assert_exit_nonzero "init refuses to run twice" "$ARK_BIN" init

# default aliases shipped in .arkrc should exist and not collide
arkrc="$(cat .arkrc)"
for alias in overdue duesoon undated high done backlog upcoming normalise report; do
    assert_contains "default .arkrc defines '$alias'" "$arkrc" "$alias ="
done

assert_contains "default .arkrc sets the #= tag default" "$arkrc" "#=general"
assert_contains "default .arkrc sets unclaimed=" "$arkrc" "unclaimed=#"

# ------------------------------------------------------------
# add
# ------------------------------------------------------------
out="$("$ARK_BIN" add todo 'Buy milk {#home; !2}')"
assert_contains "add todo with meta" "$out" "todo: Buy milk {#home; !2};;"

out="$("$ARK_BIN" add todo Call Mum)"
assert_contains "add todo unquoted words" "$out" "todo: Call Mum;;"

out="$("$ARK_BIN" add note 'Thought about liturgy {#theology}')"
assert_contains "add note" "$out" "note: Thought about liturgy {#theology};;"

out="$("$ARK_BIN" add evnt 'Team meeting {>20260601T1400; <20260601T1500; #work}')"
assert_contains "add evnt" "$out" "evnt: Team meeting"

assert_exit_nonzero "add rejects bad type" "$ARK_BIN" add bogus x
assert_exit_nonzero "add rejects empty content" "$ARK_BIN" add todo
out="$("$ARK_BIN" add todo 'oops;; evnt: injected' 2>&1; true)"
assert_contains "add rejects embedded ;;" "$out" "must not contain"

inbox="$(cat inbox.txt)"
assert_contains "inbox has all 4 added records" "$inbox" "todo: Buy milk"
assert_contains "inbox has all 4 added records" "$inbox" "todo: Call Mum"

# duplicate warning: add the same content twice before tidying
"$ARK_BIN" add todo 'Duplicate me {#dup}' >/dev/null
"$ARK_BIN" add todo 'Duplicate me {#dup}' >/dev/null
out="$("$ARK_BIN" tidy --apply)"
assert_contains "tidy warns about likely duplicate content" "$out" "possible duplicate"
assert_contains "tidy still files both duplicate records" "$out" "found 6 record(s)"

[ ! -f inbox.txt ] && ok || bad "tidy --apply consumes inbox.txt"

# ------------------------------------------------------------
# query engine
# ------------------------------------------------------------
out="$("$ARK_BIN" todo)"
assert_contains "query: todo type filter" "$out" "Buy milk"
assert_not_contains "query: todo type filter excludes notes" "$out" "liturgy"

out="$("$ARK_BIN" 'todo, -#home')"
assert_contains "query: tag presence" "$out" "Buy milk"
assert_not_contains "query: tag presence excludes non-matching" "$out" "Call Mum"

out="$("$ARK_BIN" 'todo, --#home')"
assert_not_contains "query: tag absence" "$out" "Buy milk"

out="$("$ARK_BIN" 'todo, !<=2')"
assert_contains "query: priority comparison" "$out" "Buy milk"

out="$("$ARK_BIN" 'todo|note')"
assert_contains "query: OR across types" "$out" "Buy milk"
assert_contains "query: OR across types" "$out" "liturgy"

out="$("$ARK_BIN" 'newest(todo; 1)')"
n=$(wc -l <<<"$out")
assert_eq "query function: newest(...; 1) returns exactly 1" "1" "$n"

# missing-field comparison warning
"$ARK_BIN" add todo 'No deadline task' >/dev/null
"$ARK_BIN" tidy --apply >/dev/null
out="$("$ARK_BIN" 'todo, %<=today')"
assert_contains "comparison warns about records missing the field" "$out" "missing '%'"

# ------------------------------------------------------------
# metadata grammar: canonical / named key:value / unclaimed
# ------------------------------------------------------------
"$ARK_BIN" add todo 'Prep sermon {time:00:10; sermon; #real}' >/dev/null
"$ARK_BIN" add todo 'Colon in a canonical value {$team:backend; #canon}' >/dev/null
"$ARK_BIN" add todo 'New symbol keeps its colon value {+5:6; #plus}' >/dev/null

# records only become queryable once tidy files them out of inbox.txt,
# and tidy (with no explicit --clean/--tidy/--compact) also crystallises
# unclaimed tokens, so one plain `tidy --apply` covers all of this.
"$ARK_BIN" tidy --apply >/dev/null

out="$("$ARK_BIN" 'todo, -#real')"
assert_contains "named key:value token round-trips" "$out" "time:00:10"
assert_contains "tidy crystallises an unclaimed token into #tag" "$out" "#sermon"

out="$("$ARK_BIN" 'todo, -#canon')"
assert_contains "canonical token keeps a colon in its own value intact" "$out" "\$team:backend"

out="$("$ARK_BIN" 'todo, -#plus')"
assert_contains "non-canonical leading char + colon is a named field, not a symbol" "$out" "+5:6"

# ------------------------------------------------------------
# query language: named keys (comparison / presence / sort / remove)
# ------------------------------------------------------------
"$ARK_BIN" add todo 'Short chore {time:00:05; #chores}' >/dev/null
"$ARK_BIN" add todo 'Long chore {time:01:30; #chores}' >/dev/null
"$ARK_BIN" add todo 'Undated chore {#chores}' >/dev/null
"$ARK_BIN" tidy --apply >/dev/null

out="$("$ARK_BIN" 'todo, -#chores, time>00:10')"
assert_contains "named-key comparison matches" "$out" "Long chore"
assert_not_contains "named-key comparison excludes lower values" "$out" "Short chore"

out="$("$ARK_BIN" 'todo, -#chores, time>00:10')"
assert_contains "named-key comparison warns about records missing the field" "$out" "missing 'time'"

out="$("$ARK_BIN" 'todo, -#chores, -time:')"
assert_contains "named-key presence check" "$out" "Short chore"
assert_contains "named-key presence check" "$out" "Long chore"
assert_not_contains "named-key presence check excludes fieldless records" "$out" "Undated chore"

out="$("$ARK_BIN" 'todo, -#chores, --time:')"
assert_contains "named-key absence check" "$out" "Undated chore"
assert_not_contains "named-key absence check excludes fielded records" "$out" "Short chore"

out="$("$ARK_BIN" 'todo, -#chores, -time:, >time')"
first_line="$(head -n1 <<<"$out")"
assert_contains "named-key ascending sort puts smaller value first" "$first_line" "Short chore"

out="$("$ARK_BIN" 'todo, -#chores, -time:, <time')"
first_line="$(head -n1 <<<"$out")"
assert_contains "named-key descending sort puts larger value first" "$first_line" "Long chore"

ARK_YES=1 "$ARK_BIN" edit 'todo, -#chores, -time:' remove 'time' >/dev/null
out="$("$ARK_BIN" 'todo, -#chores')"
assert_not_contains "bare named-key remove drops the field by exact key" "$out" "time:"

# ------------------------------------------------------------
# recurring events + date-window widening
# ------------------------------------------------------------
mkdir -p evnt/2026/06
cat > evnt/2026/06/evnt_202606_001.txt <<'EOF'
evnt: Weekly standup {>20260602T0900; <20260602T0930; #work; ^1w@wd1-5};;
EOF

out="$("$ARK_BIN" 'evnt, -#work')"
n=$(grep -c "Weekly standup" <<<"$out")
assert_eq "recurrence: default window is today-only" "1" "$n"

# Relative, not absolute: a hardcoded future bound decays into a
# shrinking (and eventually negative) window as real time passes it,
# which is exactly what made this test flaky. +60d is always ~60 days
# out from whenever the suite actually runs.
out="$("$ARK_BIN" 'evnt, -#work, ><=+60d')"
n=$(grep -c "Weekly standup" <<<"$out")
if [ "$n" -gt 5 ]; then ok; else
    bad "recurrence: relative date comparison widens expansion window (got $n instances)"
fi

# ------------------------------------------------------------
# alias/reserved-word collision guard + glance misrouting fix
# ------------------------------------------------------------
"$ARK_BIN" add note 'glance meeting notes from today {#work}' >/dev/null
"$ARK_BIN" tidy --apply >/dev/null

out="$("$ARK_BIN" 'glance meeting' 2>&1)"
assert_contains "literal query starting with 'glance' is not misrouted" "$out" "glance meeting notes"
assert_not_contains "literal query starting with 'glance' is not misrouted" "$out" "Select records for output"

cat >> .arkrc <<'EOF'

[queries]
today = todo, -!1
EOF
out="$("$ARK_BIN" todo 2>&1 >/dev/null)"
assert_contains "colliding alias name triggers a warning" "$out" "shadows a built-in word"
# revert the test-only alias
head -n -3 .arkrc > .arkrc.tmp && mv .arkrc.tmp .arkrc

# ------------------------------------------------------------
# edit
# ------------------------------------------------------------
"$ARK_BIN" edit 'todo, -#home' add '#urgent' >/dev/null
out="$("$ARK_BIN" 'todo, -#urgent')"
assert_contains "edit add" "$out" "Buy milk"

"$ARK_BIN" edit 'todo, -#urgent' remove '#urgent' >/dev/null
out="$("$ARK_BIN" 'todo, --#urgent')"
assert_contains "edit remove" "$out" "Buy milk"

"$ARK_BIN" edit 'todo, -#home' remove '#' >/dev/null
out="$("$ARK_BIN" 'todo, -#home')"
assert_not_contains "edit remove by bare symbol" "$out" "Buy milk"

"$ARK_BIN" edit 'todo, -Call Mum' set '!1' >/dev/null 2>&1
out="$("$ARK_BIN" 'todo, !=1')"
assert_contains "edit set" "$out" "Call Mum"

# ------------------------------------------------------------
# glance (interactive selection over stdin)
# ------------------------------------------------------------
out="$(printf 'all\n' | "$ARK_BIN" glance 'todo, -#dup')"
assert_contains "glance selection prints chosen records" "$out" "Duplicate me"

# ------------------------------------------------------------
# archive
# ------------------------------------------------------------
before="$("$ARK_BIN" 'todo, -Call Mum')"
assert_contains "sanity: Call Mum present before archiving" "$before" "Call Mum"

out="$(printf '1\n' | "$ARK_BIN" archive 'todo, -Call Mum')"
assert_contains "archive reports what it moved" "$out" "archived 1 record(s)"

after="$("$ARK_BIN" 'todo, -Call Mum')"
assert_not_contains "archived record no longer in normal queries" "$after" "Call Mum"

archived_content="$(cat archive/todo/*/*/*.txt 2>/dev/null)"
assert_contains "archived record preserved verbatim" "$archived_content" "Call Mum"

# ------------------------------------------------------------
# output modes
# ------------------------------------------------------------
out="$(ARK_COLOR=always "$ARK_BIN" pipe todo)"
assert_not_contains "pipe mode never colorizes, even when forced" "$out" $'\e['

out="$(ARK_COLOR=always "$ARK_BIN" compact todo)"
assert_contains "compact mode colorizes when forced" "$out" $'\e['

out="$(ARK_COLOR=always "$ARK_BIN" pretty todo)"
assert_contains "pretty mode colorizes when forced" "$out" $'\e['

out="$(NO_COLOR=1 ARK_COLOR=always "$ARK_BIN" compact todo)"
assert_contains "explicit ARK_COLOR=always overrides NO_COLOR" "$out" $'\e['
out="$(NO_COLOR=1 "$ARK_BIN" compact todo)"
assert_not_contains "NO_COLOR disables color" "$out" $'\e['

out="$(ARK_COLOR=always "$ARK_BIN" wrap compact todo)"
assert_not_contains "wrap mode suppresses color to protect width math" "$out" $'\e['

cat >> .arkrc <<'EOF'

[defaults]
output = compact
EOF
out="$(ARK_COLOR=always "$ARK_BIN" todo)"
assert_contains ".arkrc [defaults] output= applies when no explicit mode given" "$out" $'\e['
out="$(ARK_COLOR=always "$ARK_BIN" pipe todo)"
assert_not_contains "explicit mode word overrides .arkrc default" "$out" $'\e['
head -n -3 .arkrc > .arkrc.tmp && mv .arkrc.tmp .arkrc

# ------------------------------------------------------------
# tidy: clean / tidy / compact, dry-run vs --apply
# ------------------------------------------------------------
"$ARK_BIN" add todo 'Needs tidying' >/dev/null
out="$("$ARK_BIN" tidy --clean)"
assert_contains "tidy dry run says so" "$out" "Dry run only"
[ -f inbox.txt ] && ok || bad "dry run makes no changes"

out="$("$ARK_BIN" tidy --clean --apply)"
assert_contains "tidy --clean --apply applies" "$out" "Applied tidy"
inbox="$(cat inbox.txt)"
assert_contains "tidy --clean fills in auto metadata" "$inbox" "=todo"
assert_contains "tidy --clean fills in auto metadata" "$inbox" "&"

"$ARK_BIN" tidy --apply >/dev/null
out="$("$ARK_BIN" tidy --compact --apply)"
assert_contains "tidy --compact applies" "$out" "Applied tidy"
assert_eq "tidy --compact operation label" "compact" "$(grep '^operation:' <<<"$out" | awk '{print $2}')"

# ------------------------------------------------------------
# publish
# ------------------------------------------------------------
cat >> .arkrc <<'EOF'

[publish]
theology
EOF
out="$("$ARK_BIN" publish)"
assert_contains "publish reports counts" "$out" "Published"
[ -f docs/index.html ] && ok || bad "publish writes site index"
[ -f docs/assets/publish.css ] && ok || bad "publish writes shared CSS"
found_note_page=$(find docs/notes -name '*.html' 2>/dev/null | wc -l)
if [ "$found_note_page" -ge 1 ]; then ok; else bad "publish writes at least one note page"; fi

# ------------------------------------------------------------
# .arkrc backward compatibility + self-healing append
# ------------------------------------------------------------
OLD="$(mktemp -d)"
cd "$OLD"
mkdir -p .ark note todo evnt
echo "ark repository" > .ark/repo
cat > .arkrc <<'EOF'
[bases]
.

[defaults]
authour=
assignee=
tag=general

[queries]
overdue = todo, --=done, %<today
EOF

"$ARK_BIN" add todo 'legacy config test' >/dev/null
"$ARK_BIN" tidy --clean --apply >/dev/null
inbox="$(cat inbox.txt)"
assert_contains "old-style tag= still drives the default tag" "$inbox" "#general"

"$ARK_BIN" todo >/dev/null 2>&1
arkrc="$(cat .arkrc)"
assert_contains "unclaimed= gets appended to an old .arkrc" "$arkrc" "unclaimed=#"
assert_contains "old-style tag= is left untouched, not renamed" "$arkrc" "tag=general"
assert_not_contains "no duplicate #= is added when tag= already covers it" "$arkrc" "#=general"

before_count=$(grep -c '^unclaimed=' .arkrc)
"$ARK_BIN" todo >/dev/null 2>&1
after_count=$(grep -c '^unclaimed=' .arkrc)
assert_eq "appending unclaimed= is idempotent" "$before_count" "$after_count"

cd "$WORK"
rm -rf "$OLD"

# ------------------------------------------------------------
echo
echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
