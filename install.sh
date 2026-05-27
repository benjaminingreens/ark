#!/bin/sh
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
LIB="$PREFIX/lib/ark"

mkdir -p "$BIN"
mkdir -p "$LIB/commands"

install -m755 ark "$BIN/ark"

for cmd in commands/*; do
    [ -f "$cmd" ] || continue
    install -m755 "$cmd" "$LIB/commands/$(basename "$cmd")"
done

echo "Installed Ark to $BIN/ark"
echo "Installed commands to $LIB/commands"
echo ""
echo "Ensure this is in your PATH:"
echo "  export PATH=\"$BIN:\$PATH\""
