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
# recurring events + date-window widening
# ------------------------------------------------------------
mkdir -p evnt/2026/06
cat > evnt/2026/06/evnt_202606_001.txt <<'EOF'
evnt: Weekly standup {>20260602T0900; <20260602T0930; #work; ^1w@wd1-5};;
EOF

out="$("$ARK_BIN" 'evnt, -#work')"
n=$(grep -c "Weekly standup" <<<"$out")
assert_eq "recurrence: default window is today-only" "1" "$n"

out="$("$ARK_BIN" 'evnt, -#work, ><=20260801')"
n=$(grep -c "Weekly standup" <<<"$out")
if [ "$n" -gt 5 ]; then ok; else
    bad "recurrence: absolute date comparison widens expansion window (got $n instances)"
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
echo
echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
