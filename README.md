# Ark

install/update v0.1.0-alpha.1
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/benjaminingreens/ark/v0.1.0-alpha.1/install.sh)"
```

install/update v0.1.0-alpha.1 on ish:
```bash
apk add perl git curl
sh -c "$(curl -fsSL https://raw.githubusercontent.com/benjaminingreens/ark/v0.1.0-alpha.1/install.sh)"
```

Ark is a plain-text terminal organiser for notes, todos, and events.

Records are stored in simple `.txt` files and queried from the command line.

**This is an early pre-release and is under active development.**

---

## Record Syntax

### Todo

```text
todo Buy milk {=todo; !2; #home};;
```

### Note

```text
note Thought about liturgy {#theology};;
```

### Event

```text
evnt Team meeting {>20260601T1400; <20260601T1500; #work};;
```

Metadata is optional:

```text
note Just a thought;;
todo Call Mum;;
```

---

## Basic Commands

Show todos:

```bash
ark 'todo'
```

Show notes:

```bash
ark 'note'
```

Show events:

```bash
ark 'evnt'
```

Events today:

```bash
ark 'evnt, today'
```

Query by tag:

```bash
ark 'todo, -#work'
```

Priority query:

```bash
ark 'todo, !<=2'
```

Sort by priority:

```bash
ark 'todo, >!'
```

Interactive editing:

```bash
ark edit 'todo, -#work'
```

Subcommands:

```bash
ark tidy
```

Initialise a repository:

```bash
ark init
```

---

## Status

Ark is under active development.

Interfaces, syntax, and behaviour may change.
