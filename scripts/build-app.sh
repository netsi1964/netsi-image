#!/bin/bash
# Builds NetsiImage.app and (by default) installs it in /Applications.
#
#   scripts/build-app.sh              # build + install
#   scripts/build-app.sh --no-install # build only
#
# The bundle is signed with the local "Netsi Image Local" identity when it
# exists (scripts/signing-identity.sh), otherwise ad-hoc signed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NetsiImage"
APP_BUNDLE_NAME="Netsi Image.app"
APP_DISPLAY_NAME="Netsi Image"
BUNDLE_ID="dk.netsi.image"
VERSION="${NETSI_VERSION:-1.3.0}"
BUILD_NUMBER="${NETSI_BUILD:-4}"
MIN_MACOS="27.0"
INSTALL=1
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Ukendt argument: $arg" >&2
      exit 2
      ;;
  esac
done

echo "==> Bygger release"
swift build -c release --package-path "$ROOT"

BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"
if [[ ! -x "$BIN_DIR/$APP_NAME" ]]; then
  echo "Fejl: $BIN_DIR/$APP_NAME blev ikke fundet." >&2
  exit 1
fi

APP_DIR="$ROOT/build/$APP_BUNDLE_NAME"
echo "==> Samler $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# SwiftPM resource bundle (Bundle.module) must sit in Contents/Resources.
for bundle in "$BIN_DIR"/*.bundle; do
  [[ -e "$bundle" ]] || continue
  cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>da</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME ($VERSION)</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY_NAME ($VERSION)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.graphics-design</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Netsi</string>
</dict>
</plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

echo "==> Signerer"
# En stabil, lokal signeringsidentitet gør at macOS husker appens adgang til
# OpenRouter-nøglen i Keychain, så nye builds ikke udløser nye dialoger.
SIGN_KEYCHAIN="$HOME/Library/Keychains/netsi-image-signing.keychain-db"
SIGN_IDENTITY="$(security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p' | head -1)"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" --keychain "$SIGN_KEYCHAIN" "$APP_DIR" >/dev/null
else
  echo "    (ingen lokal identitet fundet – kør scripts/signing-identity.sh for stabile nøgle-adgange)"
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi
codesign --verify --deep --strict "$APP_DIR"

if [[ "$INSTALL" -eq 1 ]]; then
  TARGET="/Applications/$APP_BUNDLE_NAME"
  echo "==> Installerer i /Applications"
  rm -rf "/Applications/NetsiImage.app"   # tidligere navn
  if [[ -w /Applications ]]; then
    rm -rf "$TARGET"
    ditto "$APP_DIR" "$TARGET"
  else
    sudo rm -rf "$TARGET"
    sudo ditto "$APP_DIR" "$TARGET"
  fi
  # Locally built apps carry no quarantine flag; clear one if it exists anyway.
  xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
  echo "==> Installeret: $TARGET"

  # Kun én registreret kopi: den i /Applications. Staging-kopien afregistreres
  # og fjernes, så Spotlight/Launchpad ikke viser appen to steder.
  "$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$TARGET" >/dev/null 2>&1 || true
  rm -rf "$APP_DIR"
fi

if [[ "$INSTALL" -eq 1 ]]; then
  echo "==> Færdig: /Applications/$APP_BUNDLE_NAME"
else
  echo "==> Færdig: $APP_DIR"
fi
