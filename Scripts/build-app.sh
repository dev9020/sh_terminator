#!/bin/sh
# Builds a release binary and packages it into SHTerminator.app, signed with
# the Hardened Runtime and this project's entitlements (library validation
# and unsigned-executable-memory stay off — see SHTerminator.entitlements).
#
# Signing is ad-hoc ("-") for local, personal use. Distributing this app to
# other machines would need a real Developer ID signature and notarization,
# which is out of scope here — see README.md.
set -eu

cd "$(dirname "$0")/.."

APP_NAME="SHTerminator"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release

echo "==> assembling ${APP_BUNDLE}"
rm -rf "dist"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> codesign (ad-hoc, hardened runtime)"
codesign --force --deep --sign - \
  --options runtime \
  --entitlements "SHTerminator.entitlements" \
  "${APP_BUNDLE}"

echo "==> verifying signature"
codesign --verify --verbose "${APP_BUNDLE}"

echo "==> security audit"
./Scripts/audit.sh

echo "Done: ${APP_BUNDLE}"
