# Ark

install/update v0.1.0-alpha.15
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/benjaminingreens/ark/v0.1.0-alpha.15/install.sh)"
```

install/update v0.1.0-alpha.15 on ish:
```bash
apk add perl git curl
sh -c "$(curl -fsSL https://raw.githubusercontent.com/benjaminingreens/ark/v0.1.0-alpha.15/install.sh)"
```

Ark is a plain-text terminal organiser for notes, todos, and events.

Records are stored in simple `.txt` files and queried from the command line.
Nothing is stored anywhere except the `.txt` files in your repository, so
everything is greppable, diffable, and versionable with git.

**This is an early pre-release and is under active development.**

---

## Table of contents

- [Getting started](#getting-started)
- [Record syntax](#record-syntax)
- [Metadata symbols](#metadata-symbols)
- [Adding records (`ark add`)](#adding-records-ark-add)
- [Querying](#querying)
- [Output modes](#output-modes)
- [Editing records](#editing-records)
- [Glance](#glance)
- [Archive](#archive)
- [Recurring events](#recurring-events)
- [Tidy](#tidy)
- [Publish](#publish)
- [Configuration (`.arkrc`)](#configuration-arkrc)
- [Environment variables](#environment-variables)
- [Command reference](#command-reference)
- [Development](#development)
- [Status](#status)

---

## Getting started

```bash
mkdir myjournal && cd myjournal
ark init
```

`ark init` creates:

- `note/`, `todo/`, `evnt/` — where filed records eventually live
- `.ark/repo` — a marker file identifying this directory (and its
  subdirectories) as an ark repository; `ark` walks up from your current
  directory looking for `.ark/` before running any command
- `.arkrc` — repository config, seeded with sensible defaults (see
  [Configuration](#configuration-arkrc))

From here you can either add records straight into place (any `.txt` file
under `note/`, `todo/`, or `evnt/` is scanned), or jot them into `inbox.txt`
with `ark add` and let `ark tidy` file them away later.

---

## Record syntax

```text
todo: Buy milk {!2; #home};;
note: Thought about liturgy {#theology};;
evnt: Team meeting {>20260601T1400; <20260601T1500; #work};;
```

- Every record starts with `type:` (`todo`, `note`, or `evnt`), and ends
  with `;;`.
- The `{...}` metadata block is optional and, when present, holds
  `;`-separated tokens (see [Metadata symbols](#metadata-symbols) below).
- Content may span multiple lines; `ark tidy` writes multiline notes as
  their own file:
  ```text
  note: {#theology; /on-liturgy}

  A longer note that
  spans several lines.

  ;;
  ```
- Metadata is entirely optional:
  ```text
  note: Just a thought;;
  todo: Call Mum;;
  ```
- Multiple records can live in the same file, and non-record text around
  them is left alone by queries (though `ark tidy` may flag or rewrite it
  — see [Tidy](#tidy)).

---

## Metadata symbols

Each token in a `{...}` block is one leading symbol plus a value,
separated by `;`:

| Symbol | Meaning | Typical type | Example |
|---|---|---|---|
| `#` | tag | any | `#work` |
| `!` | priority (numeric) | todo | `!1` |
| `%` | deadline (date/datetime) | todo | `%20260601` |
| `=` | status | todo | `=done` |
| `$` | authour | any | `$ben` |
| `@` | assignee | todo | `@jesse` |
| `/` | title | note (also used as filename slug by tidy) | `/on-liturgy` |
| `~` | created (timestamp) | any | `~20260601T140000` |
| `&` | id | any | `&ark20260601140000abcd1234ef56` |
| `>` | start time | evnt | `>20260601T1400` |
| `<` | end time | evnt | `<20260601T1500` |
| `^` | recurrence pattern | evnt | `^1w@wd1-5@h9+3h` (see [Recurring events](#recurring-events)) |

Dates/datetimes are `yyyymmdd` or `yyyymmddThhmmss` (seconds optional).
`ark tidy --clean`/`--tidy` automatically fills in `~created`, `&id`,
`$authour` (from `.arkrc` if set), and `#tag` (defaulting to `general`)
for every record, plus `=status`, `!priority`, and `@assignee` for todos —
you rarely need to type these yourself.

---

## Adding records (`ark add`)

```bash
ark add TYPE 'CONTENT {meta; meta}'
```

Appends `TYPE: CONTENT;;` as a new line in `inbox.txt`, verbatim — no
metadata is auto-filled at this point (that happens when you run
`ark tidy`). `TYPE` must be `todo`, `note`, or `evnt`. Quote `CONTENT` as
one shell argument whenever it includes a `{...}` block, so the shell
doesn't split or brace-expand it.

```bash
ark add todo 'Buy milk {#home; !2}'
ark add todo Call Mum                     # unquoted words also work
ark add note 'Thought about liturgy {#theology}'
ark add evnt 'Team meeting {>20260601T1400; <20260601T1500; #work}'
```

Records added this way aren't picked up by queries until they're filed
out of `inbox.txt` — run `ark tidy --apply` (or just `ark tidy --apply`,
since inbox.txt is level 1, the default) afterwards. You can just as
well skip `ark add` and write directly into `inbox.txt`, or any `.txt`
file under `note/`, `todo/`, `evnt/` — `ark add` is only a convenience
for the common case.

---

## Querying

```bash
ark 'QUERY'
```

A query is one or more comma-separated **conditions**, ANDed together;
`|` ORs whole groups (parenthesise to nest). Conditions:

| Condition | Meaning |
|---|---|
| `todo` / `note` / `evnt` | match record type |
| `text` | substring match against content + raw metadata |
| `-text` | same as above, explicit form |
| `--text` | negated substring match |
| `-SYM` | has metadata symbol `SYM` present, e.g. `-#` has a tag, `-^` recurs |
| `--SYM` | metadata symbol `SYM` absent |
| `SYM=VAL`, `SYM<VAL`, `SYM>VAL`, `SYM<=VAL`, `SYM>=VAL` | compare a metadata value: `!` numeric, `%` dates (see below), everything else lexical |
| `today`, `week`, `Nd`/`Nw`/`Nm`/`Ny` | evnt only: start time falls within that window from now |

`%` (deadline/created) comparisons accept relative dates: `today`,
`+2w`, `-3d`, `+1m`, `+1y`, etc., alongside literal `yyyymmdd[Thhmmss]`.

Whenever a query uses a comparison (`SYM<VAL` etc.), ark prints a
warning above the results if any other record matched the rest of the
query but lacks that metadata symbol entirely, e.g.:
```text
warning: 5 otherwise matching record(s) missing '%' for '%<=today'
```
so you don't silently miss records that just haven't been given a
deadline yet.

Examples:

```bash
ark 'todo'                          # all todos
ark 'todo, -#work'                  # todos tagged #work
ark 'todo, --#work'                 # todos NOT tagged #work
ark 'todo, !<=2'                    # priority 1 or 2
ark 'todo, -=done'                  # status is done
ark 'evnt, today'                   # events today (recurrence expanded)
ark 'evnt, week'                    # events this week
ark 'todo|note'                     # todos or notes
ark 'todo, (-#work|-#home)'         # todo AND (tagged work OR home)
ark 'todo, %<=today, --=done'       # overdue-or-due todos not yet done
```

Run several queries (or aliases) in one invocation — results print in
order, separated by a blank line:

```bash
ark 'todo, -!1' 'evnt, today'
```

### Sorting

Add a sort token anywhere in the query:

| Token | Meaning |
|---|---|
| `>SYM` / `<SYM` | ascending / descending by metadata `SYM`'s value |
| `>>` | ascending by evnt start (`>`) |
| `<<` | descending by evnt end (`<`) |
| `><` | ascending by evnt end (`<`) |
| `<>` | descending by evnt start (`>`) |

(`>`/`<` are themselves metadata symbols for evnt start/end, which is
why sorting by them needs the two-character form above, rather than
colliding with the `>SYM`/`<SYM` sort syntax.)

```bash
ark 'todo, >!'          # ascending priority
ark 'todo, <!'          # descending priority
ark 'evnt, week, >>'    # this week's events, earliest start first
```

### Query functions

`fn(QUERY; ARG)` runs `QUERY` and hands the matches to a named function
for filtering/reordering. Built in:

```bash
ark 'newest(todo, -=done; 3)'   # 3 most recently created matches
ark 'oldest(todo, -=done; 3)'   # 3 oldest
ark 'random(todo, -=done; 2)'   # 2 at random
```

You can define your own in `.arkrc` — see [Configuration](#configuration-arkrc).

### Query aliases

`.arkrc`'s `[queries]` section names reusable queries, usable as a query
word in place of an actual query string:

```ini
[queries]
overdue = todo, -=done, %<today
```

```bash
ark overdue
```

An alias's value can itself be one or more `;;`-separated **steps**,
each of which is either a plain query, or an `edit`/`glance` invocation
— letting an alias chain interactive or batch-editing steps. This is
exactly what the default `.arkrc` created by `ark init` sets up (see
[Configuration](#configuration-arkrc)). This `glance`/`edit` routing
only ever applies to steps that came from an alias substitution — a
literal query you type directly, even one that happens to start with
the word `glance` or `edit`, is always treated as a plain query and
never misrouted to that command.

An alias name that collides with a word that already means something on
its own (a record type, `today`/`week`, a command, an output mode) would
silently shadow it, so ark prints a warning at startup if you define
one:
```text
warning: query alias 'today' shadows a built-in word/command of the same name
```

---

## Output modes

Put one of these before the query (or as a query word):

| Mode | Effect |
|---|---|
| `pipe` (default) | plain, **never colored**, one result per line — the guaranteed-stable format for scripting |
| `basic` | blank line between results; colored when the terminal allows |
| `compact` | one result per line, autowrap disabled (long lines scroll instead of wrapping — handy in a real terminal); colored when allowed |
| `pretty` | multi-line colored "cards" (see below); colored when allowed |
| `wrap` | modifier, combinable with any mode: wrap long lines at terminal width (`$COLUMNS`, or the terminal's actual width) |

```bash
ark basic 'todo'
ark compact 'todo'
ark pretty 'todo'
ark wrap 'todo'
```

`pretty` mode renders each record as a short card instead of one dense
line — a content line, then an indented line of the fields that matter
for reading at a glance (tag, priority, status, deadline, evnt time),
with the noisier `~created`/`&id` left out:

```text
[ ] Buy milk
  #home  priority 1  todo  due 2026-08-11  ./todo/2026/07/todo_202607_002.txt

[x] Completed task
  #work  priority 3  done  ./todo/2026/07/todo_202607_002.txt
```

### Color

Color is opt-out, not opt-in: it's on automatically in `basic`/
`compact`/`pretty` whenever stdout is a real terminal, and off
otherwise (piped, redirected, or a non-interactive shell) — no flags
needed either way. Overdue deadlines and top priority show in red, due-
today in yellow, done items dim and struck through, tags cyan, evnt
times blue, and so on.

- `NO_COLOR=1` (see [no-color.org](https://no-color.org)) or
  `ARK_COLOR=never` disable it.
- `ARK_COLOR=always` forces it on (e.g. for `less -R`), taking
  precedence over `NO_COLOR`.
- `pipe` mode **never** colors, regardless of any of the above — that's
  what makes it the safe default for scripts and pipelines.
- Combining `wrap` with a colored mode suppresses color for that call,
  since ANSI codes would otherwise throw off the wrap-width
  calculation.

Pin your own preferred default (so you don't have to type `pretty`/
`compact` every time) with `.arkrc`'s `[defaults] output=`; see
[Configuration](#configuration-arkrc). An explicit mode word on the
command line always overrides it.

---

## Editing records

### Interactive: `ark edit 'QUERY'`

Shows a numbered list of matches, prompts you to select some
(`all` / `none` / `1,3,5-8` / `q` to quit), then prompts for an
operation to apply to the selection:

```text
Operation [a/add TOKEN | r/remove TOKEN | s/set TOKEN | p/replace OLD NEW | q]:
```

Chain multiple operations on one line with `;;`, e.g.
`add #urgent ;; set !1`. After confirming, the edit is applied, records
reload, and you're prompted again (until you quit).

### Batch: `ark edit 'QUERY' OP ARGS`

Applies one operation to every match, non-interactively (still asks for
confirmation unless `ARK_YES=1`):

```bash
ark edit 'todo, -#jesse' add '#family'
ark edit 'todo, -#jesse' remove '#jesse'
ark edit 'todo, -#jesse' set '=done'
ark edit 'todo, -#jesse' replace '#jesse' '#family'
```

### Operations

| Op | Alias | Meaning |
|---|---|---|
| `add` | `a` | append `TOKEN` unless already present |
| `remove` | `r` | drop token(s) matching `TOKEN` — an exact token, a bare symbol (drops any token with that symbol, e.g. `#` drops all tags), or a `prefix*` wildcard |
| `set` | `s` | replace whatever token(s) share `TOKEN`'s symbol with `TOKEN` |
| `replace` | `p` | swap one exact raw token for another: `replace OLD NEW` |

Edits are written back by replacing each record's exact original text in
its source file — everything else in the file is left untouched. Review
with `git diff` afterwards (ark reminds you to).

---

## Glance

```bash
ark glance 'QUERY' ['QUERY2' ...]
```

Like a query, but prints a numbered list to stderr (so stdout stays
pipeable) and then asks which of them to actually print to stdout:

```text
[1] todo: Buy milk {!2; #home} [...]
[2] todo: Call Mum {!1; #family} [...]

Select records for output [all/none/1,3,5-8/q]:
```

Useful for picking a subset to pipe elsewhere, or as a step inside a
query alias (see [Query aliases](#query-aliases)).

---

## Archive

```bash
ark archive 'QUERY'
```

Ark has no delete command, by design — instead, `archive` shows a
numbered list of matches and asks which to move
(`all` / `none` / `1,3,5-8` / `q`), the same selection UI as glance:

```text
[1] todo: Buy milk {!2; #home} [...]
[2] todo: Call Mum {!1; #family} [...]

Select records to archive [all/none/1,3,5-8/q]:
```

Selected records are moved, verbatim, out of whatever file they're
currently in and appended into `archive/TYPE/yyyy/mm/` (grouped by the
record's own `~created` date, falling back to today if a record
predates that metadata). Nothing is deleted — archived records simply
stop appearing in ordinary queries, since `archive/` isn't one of the
`note`/`todo`/`evnt` roots ark scans. If a source file ends up empty
once its archived record(s) are removed, that empty file is deleted;
files with other records left in them are just rewritten without the
archived ones.

Bring something back by hand — it's still a plain `.txt` record, just
under `archive/` instead of `note/`/`todo/`/`evnt/`.

---

## Recurring events

An evnt's `^` metadata is a recurrence pattern applied to its `>` start
time, e.g. `^1w@wd1-5@h9+3h`:

| Piece | Meaning |
|---|---|
| `1w` (or `1d`/`1m`/`1y`, combinable: `1m2w`) | repeat every 1 week |
| `@wd1-5` | restrict to ISO weekdays 1-5 (Mon-Fri) |
| `@m...` / `@h...` / `@n...` | restrict to day-of-month / hour / minute; all accept comma/range lists, e.g. `@h9,13-15` |
| `~SELECTOR` | exclude instances matching `SELECTOR` (same syntax as `@...`) |
| `+3h` | each instance lasts 3 hours (default: 3h if the start has a time-of-day, otherwise a full day) |
| leading `.` | anchor the repeat interval to the 1st of the start's month/year, instead of the start date itself |

```text
evnt: Weekly standup {>20260601T0900; <20260601T0930; ^1w@wd1-5};;
```

**Important:** recurrence is only expanded within the time window a
query implies. If your query includes `today`, `week`, or `Nd`/`Nw`/
`Nm`/`Ny`, that's the window. If it doesn't, ark still uses a default
window of **today only**. So `ark 'evnt, -#work'` (no time token) will
only show a recurring #work event if it happens to recur today — add
`week` or `30d` etc. to see further out. Non-recurring events are
unaffected by this default window and match regardless of date unless
you add a time condition yourself.

A comparison against evnt start/end (`>`/`<`) with a date also widens
this window to cover it, so you don't need `week`/`Nd` just to reach
further out:
```bash
ark 'evnt, ><=+30d'        # recurring events widen to cover the next 30 days
ark 'evnt, >>=20260901'    # widens to include (at least) that date
```

---

## Tidy

`ark tidy` combines one **operation** with one **level**. Nothing is
written to disk unless `--apply` is given (a dry run always shows what
it would do).

### Operations

| Flag | Effect |
|---|---|
| `--clean` | reformat records in place: fill in missing `~created`/`&id`/`$authour`/`#tag` (todo also gets `=status`/`!priority`/`@assignee`), and order metadata tokens consistently. Never moves a record to a different file. |
| `--tidy` | clean, **and** group loose single-line records out of whatever file they were found in into `TYPE/yyyy/mm/` batch files; multiline notes get their own file (named from `/title`, or a timestamp if untitled). Files named with a leading `_` are reformatted in place but never emptied out. Warns (without dropping anything) if the same content shows up more than once in a single run — most likely an accidental double-paste, e.g. running `ark add` twice by habit. |
| `--compact` | within each `TYPE/yyyy/mm/` directory, merge all files back into as few files as possible (max 1000 records each), dropping duplicates (matched by `&id`, else by exact text). Skips any month containing a multiline note. |
| *(none)* | same as `--tidy --1` |

### Levels

| Flag | Files touched |
|---|---|
| `--1` (default) | `inbox.txt` only |
| `--2` | all "loose" files (anything not already inside a `TYPE/yyyy/mm/` directory) |
| `--3` | files already inside a `TYPE/yyyy/mm/` directory |
| `--4` | everything |

```bash
ark tidy                       # dry run: tidy inbox.txt
ark tidy --apply               # actually file inbox.txt away
ark tidy --clean --2 --apply   # reformat all loose files in place
ark tidy --compact --apply     # merge/dedupe files under TYPE/yyyy/mm/
```

The duplicate-content warning only looks within a single `tidy` run,
deliberately — cross-run detection isn't attempted, because adding the
same content again next week (or next year) is a legitimate new record
for a todo/note app, not a duplicate. It's really only catching "you
pasted this twice a second ago," which is the case worth flagging.

---

## Publish

```bash
ark publish
```

Builds a static HTML site under `docs/` from `note:` records:

1. Reads `.arkrc`'s `[publish]` tag list (required — dies if empty) and
   `defaults.no_publish` (an opt-out tag, default `no_publish`).
2. Scans every note record; a note is published once per `[publish]` tag
   it carries, unless it also carries the opt-out tag.
3. Renders one page per published note (its body run through a small
   built-in markdown dialect: `#`/`##`/`###` headings, `-`/`*` and `1.`
   lists, `>` blockquotes, `**bold**`/`*italic*`/`[text](url)`,
   backslash-escaping, and `---csv` blocks rendered as tables), one
   index page per tag, and a site index linking tags that have notes.
4. Wraps every page in a template — `.ark/publish.html` if present (or
   `$ARK_PUBLISH_TEMPLATE`), else a built-in default — and writes shared
   CSS once.

`docs/` is wiped and rebuilt from scratch on every run.

```ini
[publish]
theology
journal

[defaults]
no_publish = draft
```

---

## Configuration (`.arkrc`)

Created by `ark init` with these defaults:

```ini
[bases]
.

[defaults]
authour=
assignee=
tag=general
# output=compact   # uncomment to make compact/basic/pretty the default view instead of pipe

[queries]
# Everyday shortcuts -- e.g. `ark overdue`, `ark high`. None of these
# names collide with a built-in word/command; ark warns you at startup
# if you ever add one that does.
overdue = todo, --=done, %<today
duesoon = todo, --=done, %<=+3d, %>=today
undated = todo, --=done, --%
high = todo, --=done, !<=1
done = todo, -=done
backlog = todo, --=done, >!
upcoming = evnt, week, >>

# Priority/deadline decay: nudges stale todos' priority and deadline
# metadata forward as they age. Run it yourself, e.g. `ark normalise` --
# nothing here runs automatically.
normalise =
  edit 'todo, -=todo, !=1, --%' set '%+2w'
  ;; edit 'todo, -=todo, !=2, --%' set '%+4w'
  ;; edit 'todo, -=todo, !>1, %>=today, %<+2w' set '!1'
  ;; edit 'todo, -=todo, !>2, %>=+2w, %<=+4w' set '!2'
  ;; edit 'todo, -=todo, !<2, %>=-4w, %<=-2w' set '!2'
  ;; edit 'todo, -=todo, !<3, %<-4w' set '!3'

# A multi-step daily/weekly review: this week's events, today's events,
# then three interactive glance picks over the open todo backlog.
report =
  evnt, week, --^, >>
  ;; evnt, today, -^, >>
  ;; glance 'todo, -=todo, (-!1|-!2), >!'
  ;; glance 'newest(todo, -=todo, -!3; 2)'
  ;; glance 'oldest(todo, -=todo, -!3; 2)'
  ;; glance 'random(todo, -=todo, -!3; 2)'
```

The one-line aliases (`overdue`, `duesoon`, `undated`, `high`, `done`,
`backlog`, `upcoming`) are ordinary single-step queries — see
[Querying](#querying) for what each condition means. `normalise` and
`report` are multi-step aliases (see [Query aliases](#query-aliases))
— nothing runs automatically; you invoke them with `ark normalise` /
`ark report` like any other query. Note that each line after the first
in a `[queries]` entry is a **continuation**, joined onto the same
alias and split into `;;`-separated steps — the leading `;;` on each
continuation line above is exactly that separator, not a comment
(lines starting with `#` *are* comments, and are skipped).

### Sections

| Section | Contents |
|---|---|
| `[bases]` | one extra directory per line to also scan for `note/`, `todo/`, `evnt/` (in addition to the repository root); `~` expands to your home directory |
| `[defaults]` | `authour=`, `assignee=`, `tag=` (used by `ark tidy`), `no_publish=` (used by `ark publish`), `output=` (used by the query engine — see [Output modes](#output-modes)) |
| `[queries]` | `name = query`, a reusable alias usable as a query word; indented continuation lines extend the same alias. A name that collides with a built-in word prints a warning (see [Query aliases](#query-aliases)) |
| `[functions]` | `name = path/to/file.pl` — a Perl file `require`'d at startup, which must define a sub `arkfunc_name(query, arg, \@records, $run_query)` |
| `[function name]` | an inline Perl body for `arkfunc_name`, read verbatim until the next `[section]` — an alternative to `[functions]` for small one-off functions |
| `[publish]` | tag names to publish, one per line (see [Publish](#publish)) |

---

## Environment variables

| Variable | Effect |
|---|---|
| `ARK_YES` | skip all confirmation prompts (batch edit, archive, tidy would still require `--apply` to write) |
| `ARK_NO_PROGRESS` | disable the scanning progress bar |
| `COLUMNS` | terminal width used by `wrap` output mode (falls back to actual terminal width, then 80) |
| `NO_COLOR` | disable color in `basic`/`compact`/`pretty` (see [Color](#color)); any value counts |
| `ARK_COLOR` | `never` disables color, `always` forces it on (overriding `NO_COLOR` and the terminal check) |
| `ARK_COMMAND_DIR` | extra directory to search first for command scripts (like `tidy`, `publish`, `add`) |
| `ARK_PUBLISH_TEMPLATE` | path to a custom HTML template for `ark publish`, overriding `.ark/publish.html` |

---

## Command reference

```text
ark 'QUERY'                  run a query, print matching records
ark 'QUERY1' 'QUERY2' ...    run several queries/aliases in sequence

ark init                     initialise an ark repository here
ark add TYPE 'CONTENT'       append a record to inbox.txt
ark edit 'QUERY'             interactive edit mode over the matches
ark edit 'QUERY' OP ARGS     batch edit all matches, no prompts
ark glance 'QUERY' [...]     numbered list; choose which matches to print
ark archive 'QUERY'          numbered list; move chosen matches to archive/
ark tidy [OPTS]              reformat / organise / compact record files
ark publish                  build a static site from tagged notes
ark help                     show a summary of all of the above
```

Run `ark help` at any time for a terminal-friendly version of this
reference.

---

## Development

```bash
t/run.sh
```

Runs the project's regression suite: builds a scratch repo, drives
`ark` through the query engine, edit/glance/archive, tidy (all three
operations), output modes/color, and publish, and asserts on specific
behaviors rather than diffing golden output (dates and ids are dynamic
by design). Exits non-zero if anything fails. Run it before and after
any change to `bin/ark` or `lib/ark/`.

---

## Status

Ark is under active development.

Interfaces, syntax, and behaviour may change.
