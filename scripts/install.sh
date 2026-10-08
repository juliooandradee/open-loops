#!/bin/bash
# Builds, copies the app to ~/Applications and (re)starts it.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build.sh

TARGET="$HOME/Applications/Open Loops.app"
mkdir -p "$HOME/Applications"

osascript -e 'tell application id "com.julioandrade.openloops" to quit' >/dev/null 2>&1 || true
sleep 1

rm -rf "$TARGET"
cp -R "build/Open Loops.app" "$TARGET"
open "$TARGET"
echo "Instalado em: $TARGET"
