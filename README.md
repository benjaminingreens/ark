# Ark

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

---

## Install on Unix-like systems

Requires `perl` and `git`.

```sh
mkdir -p ~/.local/src ~/.local/bin && git clone https://github.com/benjaminingreens/ark.git ~/.local/src/ark && sh ~/.local/src/ark/install.sh && (grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.profile || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile) && . ~/.profile
```

---

## Update on Unix-like systems

```sh
git -C ~/.local/src/ark pull && sh ~/.local/src/ark/install.sh
```

---

## Install on iSH

```sh
apk add perl git && mkdir -p ~/.local/src ~/.local/bin && git clone https://github.com/benjaminingreens/ark.git ~/.local/src/ark && sh ~/.local/src/ark/install.sh && (grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.profile || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile) && . ~/.profile
```

---

## Update on iSH

```sh
git -C ~/.local/src/ark pull && sh ~/.local/src/ark/install.sh
```

---

