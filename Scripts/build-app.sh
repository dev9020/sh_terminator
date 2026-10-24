#!/bin/sh
# Builds a release binary and packages it into SHTerminator.app, signed with
# the Hardened Runtime and this project's entitlements (library validation
# and unsigned-executable-memory stay off — see SHTerminator.entitlements).
#
# Signing is ad-hoc ("-") by default, for local, personal use. An ad-hoc
# signature names nobody: anyone who can write to the .app can re-sign a
# modified copy and it looks just as valid. Set SIGN_IDENTITY to a real
# identity (e.g. "Developer ID Application: …", see
# `security find-identity -v -p codesigning`) to sign with it instead;
# distributing to other machines also needs notarization — see SECURITY.md §6.
set -eu

cd "$(dirname "$0")/.."

APP_NAME="SHTerminator"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "==> swift build -c release"
swift build -c release

echo "==> assembling ${APP_BUNDLE}"
rm -rf "dist"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
# zsh startup files and the ssh helper for the panes' proxy (SECURITY.md §18).
cp -R "Resources/shell" "${APP_BUNDLE}/Contents/Resources/shell"

if [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "==> codesign (ad-hoc, hardened runtime)"
    echo "    note: ad-hoc signature, for this Mac only; set SIGN_IDENTITY to sign with a real identity"
    codesign --force --sign - \
      --options runtime \
      --entitlements "SHTerminator.entitlements" \
      "${APP_BUNDLE}"
else
    echo "==> codesign (${SIGN_IDENTITY}, hardened runtime)"
    codesign --force --sign "${SIGN_IDENTITY}" --timestamp \
      --options runtime \
      --entitlements "SHTerminator.entitlements" \
      "${APP_BUNDLE}"
fi

echo "==> verifying signature"
codesign --verify --verbose "${APP_BUNDLE}"

echo "==> security audit"
./Scripts/audit.sh

echo "Done: ${APP_BUNDLE}"
