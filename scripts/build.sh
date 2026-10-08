#!/bin/bash
# Compiles the app and assembles "build/Open Loops.app" (ad-hoc signed).
# Universal binary: one build per architecture, joined with lipo (works with the Command Line Tools alone).
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR="build/Open Loops.app"
BINARY="build/OpenLoops-universal"

for ARCH in arm64 x86_64; do
  swift build -c release --triple "$ARCH-apple-macosx14.0"
done
mkdir -p build
lipo -create -output "$BINARY" \
  .build/arm64-apple-macosx/release/OpenLoops \
  .build/x86_64-apple-macosx/release/OpenLoops

if [ ! -f Resources/AppIcon.icns ]; then
  swift scripts/make-icon.swift
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/OpenLoops"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/emblem.png "$APP_DIR/Contents/Resources/"

codesign --force --sign - "$APP_DIR"
echo "OK: $APP_DIR ($(lipo -archs "$APP_DIR/Contents/MacOS/OpenLoops"))"
