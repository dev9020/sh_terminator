#!/bin/sh
# Regenerates Resources/AppIcon.icns from Scripts/make-icon.swift.
# Only needed after changing the icon drawing code; the .icns is committed.
set -eu

cd "$(dirname "$0")/.."

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift Scripts/make-icon.swift "${ICONSET}"
iconutil --convert icns --output Resources/AppIcon.icns "${ICONSET}"
rm -rf "$(dirname "${ICONSET}")"

echo "Done: Resources/AppIcon.icns"
