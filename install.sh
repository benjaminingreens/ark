#!/bin/sh
set -eu

REPO="https://github.com/benjaminingreens/ark.git"
SRC="${HOME}/.local/src/ark"
PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
LIB="$PREFIX/lib/ark"

command -v git >/dev/null 2>&1 || {
    echo "git is required"
    exit 1
}

command -v perl >/dev/null 2>&1 || {
    echo "perl is required"
    exit 1
}

mkdir -p "$HOME/.local/src" "$BIN" "$LIB/commands"

if [ -d "$SRC/.git" ]; then
    git -C "$SRC" pull
else
    git clone "$REPO" "$SRC"
fi

install -m755 "$SRC/bin/ark" "$BIN/ark"
install -m644 "$SRC/lib/ark/arkfuncs.pl" "$LIB/arkfuncs.pl"

for cmd in "$SRC"/lib/ark/commands/*; do
    [ -f "$cmd" ] || continue
    install -m755 "$cmd" "$LIB/commands/$(basename "$cmd")"
done

PROFILE="${HOME}/.profile"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

touch "$PROFILE"

if ! grep -qxF "$PATH_LINE" "$PROFILE"; then
    echo "$PATH_LINE" >> "$PROFILE"
fi

echo "Installed Ark."
echo "Restart your shell or run:"
echo ". ~/.profile"
