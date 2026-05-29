#!/bin/sh
set -eu

REPO="https://github.com/benjaminingreens/ark.git"
SRC="${HOME}/.local/src/ark"
PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
LIB="$PREFIX/lib/ark"

command -v git >/dev/null 2>&1 || { echo "git is required"; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "perl is required"; exit 1; }

mkdir -p "$HOME/.local/src" "$BIN" "$PREFIX/lib"

if [ -d "$SRC/.git" ]; then
    git -C "$SRC" pull --ff-only
else
    git clone "$REPO" "$SRC"
fi

# Install executable atomically
tmp="$BIN/ark.$$"
cp "$SRC/bin/ark" "$tmp"
chmod 755 "$tmp"
mv -f "$tmp" "$BIN/ark"

# Replace full library tree atomically-ish
tmp_lib="$PREFIX/lib/ark.$$"
rm -rf "$tmp_lib"
mkdir -p "$tmp_lib"
cp -R "$SRC/lib/ark/." "$tmp_lib/"
find "$tmp_lib" -type d -exec chmod 755 {} \;
find "$tmp_lib" -type f -exec chmod 644 {} \;
find "$tmp_lib/commands" -type f -exec chmod 755 {} \; 2>/dev/null || true
rm -rf "$LIB"
mv "$tmp_lib" "$LIB"

PROFILE="${HOME}/.profile"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

touch "$PROFILE"

if ! grep -qxF "$PATH_LINE" "$PROFILE"; then
    echo "$PATH_LINE" >> "$PROFILE"
fi

echo "Installed Ark."
echo "Restart your shell or run:"
echo ". ~/.profile"
