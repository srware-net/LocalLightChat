#!/bin/bash
# Package LocalLightChat.app on macOS 11+ using Xcode CLT, without Homebrew/CMake.
# Accept thin arm64/x86_64 or universal2 macOS Mach-O helper binaries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

# ============================================================================
# EDIT HERE ONCE - afterwards just run: ./build_app.sh
# Put your macOS Mach-O executables into ./binaries/ or use absolute paths.
# Nothing is downloaded automatically, and no Homebrew or CMake is required.
# ============================================================================
# Launcher architecture: universal2, arm64, x86_64, or auto (machine architecture).
# universal2 keeps the fat Swift launcher, but DOES NOT require fat helpers.
APP_ARCH="universal2"

BINARIES_DIR="$ROOT/binaries"
NGINX_PATH="$BINARIES_DIR/nginx-universal2"
PHP_FPM_PATH="$BINARIES_DIR/php-fpm-universal2"
RAGD_PATH="$BINARIES_DIR/ragd-universal2"                 # optional
MCP_SERVER_PATH="$BINARIES_DIR/mcp_server-universal2"    # optional
MCP_GATEWAY_PATH="$BINARIES_DIR/llc-mcp-gateway-universal2" # optional

DEFAULT_APP_VERSION="1.0.0"
DEFAULT_APP_BUILD_NUMBER="1"
DEFAULT_APP_BUNDLE_ID="com.locallightchat.desktop"
DEFAULT_SIGN_IDENTITY="-" # - = ad hoc; for notarization: Developer ID Application: ...
# TEST BUILDS ONLY: 1 = fresh database gets admin/admin; 0 = secure random password.
DEV_ADMIN_LOGIN="1"    # SET TO 0 BEFORE DISTRIBUTING A PRODUCTION RELEASE
# ============================================================================
# Advanced: environment variables can override these settings, but are NOT
# required for normal builds.
OUT="${OUT_DIR:-$ROOT/dist}"
APP="$OUT/LocalLightChat.app"
VERSION="${APP_VERSION:-$DEFAULT_APP_VERSION}"
BUILD_NUMBER="${APP_BUILD_NUMBER:-$DEFAULT_APP_BUILD_NUMBER}"
BUNDLE_ID="${APP_BUNDLE_ID:-$DEFAULT_APP_BUNDLE_ID}"
IDENTITY="${SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
case "$DEV_ADMIN_LOGIN" in
  1) DEV_ADMIN_PLIST='<true/>' ;;
  0) DEV_ADMIN_PLIST='<false/>' ;;
  *) echo 'ERROR: DEV_ADMIN_LOGIN must be 0 or 1' >&2; exit 1 ;;
esac
ARCH="${TARGET_ARCH:-$APP_ARCH}"
if [ "$ARCH" = auto ]; then
  ARCH="$(uname -m)"
fi
case "$ARCH" in
  arm64) BUILD_ARCHS=(arm64) ;;
  x86_64) BUILD_ARCHS=(x86_64) ;;
  universal2) BUILD_ARCHS=(arm64 x86_64) ;;
  *) echo "ERROR: APP_ARCH must be auto, arm64, x86_64 or universal2 (got: $ARCH)" >&2; exit 1 ;;
esac
NGINX_BIN="${NGINX_BIN:-$NGINX_PATH}"
PHP_FPM_BIN="${PHP_FPM_BIN:-$PHP_FPM_PATH}"
RAGD_BIN="${RAGD_BIN:-$RAGD_PATH}"
MCP_SERVER_BIN="${MCP_SERVER_BIN:-$MCP_SERVER_PATH}"
MCP_GATEWAY_BIN="${MCP_GATEWAY_BIN:-$MCP_GATEWAY_PATH}"

fail() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Missing $1 (Xcode Command Line Tools required)"; }
need_cmd xcrun
need_cmd lipo
need_cmd codesign
need_cmd ditto
need_cmd file

[ -f "$ROOT/launcher/LocalLightChat.swift" ] || fail 'Missing launcher source'
[ -f "$ROOT/web/api.php" ] || fail 'Missing web application'
[ -f "$ROOT/resources/nginx/mime.types" ] || fail 'Missing nginx mime.types'
[ -f "$ROOT/resources/config/ragd.conf.template" ] || fail 'Missing complete RAG config template' 
[ -f "$ROOT/assets/LocalLightChat.icns" ] || fail 'Missing app icon: assets/LocalLightChat.icns'
[ -n "$NGINX_BIN" ] || fail 'NGINX_PATH must point to a macOS nginx executable'
[ -n "$PHP_FPM_BIN" ] || fail 'PHP_FPM_PATH must point to a macOS php-fpm executable'
[ -f "$NGINX_BIN" ] || fail "Nginx not found: $NGINX_BIN (copy it to binaries/ or edit NGINX_PATH at the top of this script)"
[ -f "$PHP_FPM_BIN" ] || fail "PHP-FPM not found: $PHP_FPM_BIN (copy it to binaries/ or edit PHP_FPM_PATH at the top of this script)"

# Check Mach-O format, but do not demand matching/fat slices.
# This allows e.g. an arm64-only MCP helper alongside a universal2 launcher.
check_macho() {
  local path="$1" label="$2" present="" target
  [ -f "$path" ] || fail "$label not found: $path"
  file "$path" | grep -q 'Mach-O' || fail "$label is not a macOS Mach-O executable: $path"
  for target in arm64 x86_64; do
    if lipo -verify_arch "$target" "$path" >/dev/null 2>&1; then
      present="${present}${present:+,}$target"
    fi
  done
  [ -n "$present" ] || fail "$label: no supported macOS architecture found: $path"
  echo "==> $label architectures: $present"
  for target in "${BUILD_ARCHS[@]}"; do
    if ! lipo -verify_arch "$target" "$path" >/dev/null 2>&1; then
      if [ "$target" = arm64 ] && lipo -verify_arch x86_64 "$path" >/dev/null 2>&1; then
        echo "WARNING: $label is x86_64-only on arm64; requires Rosetta 2 on Apple Silicon." >&2
      else
        echo "WARNING: $label lacks $target. The $target app slice cannot use this helper." >&2
      fi
    fi
  done
}

check_macho "$NGINX_BIN" nginx
check_macho "$PHP_FPM_BIN" php-fpm

# Optional helpers: skip missing defaults, but reject typos in explicitly
# overridden paths (including edited paths outside the binaries directory).
optional_helper() {
  local path="$1" default_path="$2" label="$3"
  if [ -z "$path" ]; then
    return 0
  fi
  if [ ! -f "$path" ]; then
    if [ "$path" = "$default_path" ]; then
      echo "NOTE: $label not found ($path); service will be omitted" >&2
      return 0
    fi
    fail "$label not found: $path"
  fi
  check_macho "$path" "$label" >&2
  printf '%s' "$path"
}
RAGD_BIN="$(optional_helper "$RAGD_BIN" "$RAGD_PATH" ragd)"
MCP_SERVER_BIN="$(optional_helper "$MCP_SERVER_BIN" "$MCP_SERVER_PATH" mcp-server)"
MCP_GATEWAY_BIN="$(optional_helper "$MCP_GATEWAY_BIN" "$MCP_GATEWAY_PATH" mcp-gateway)"

# Always build clean: never modify a previously signed .app.
mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources/nginx"

# Deliberately avoid distributing the legacy shared private TLS key.
cp "$ROOT/resources/nginx/mime.types" "$APP/Contents/Resources/nginx/mime.types"
cp "$ROOT/resources/nginx/fastcgi_params" "$APP/Contents/Resources/nginx/fastcgi_params"
mkdir -p "$APP/Contents/Resources/config"
cp "$ROOT/resources/config/ragd.conf.template" "$APP/Contents/Resources/config/ragd.conf.template"
cp "$ROOT/assets/LocalLightChat.icns" "$APP/Contents/Resources/LocalLightChat.icns"
cp -R "$ROOT/resources/LICENSES" "$APP/Contents/Resources/LICENSES"
cp -R "$ROOT/web" "$APP/Contents/Resources/www"
# The signed webroot contains code/static assets only; create no persistent folders.
rm -rf "$APP/Contents/Resources/www/data" "$APP/Contents/Resources/www/uploads" \
       "$APP/Contents/Resources/www/tmp" "$APP/Contents/Resources/www/workspaces" \
       "$APP/Contents/Resources/www/artifacts"
# Clean common platform-created junk without modifying original sources.
find "$APP/Contents/Resources/www" -name '.DS_Store' -type f -delete

cp "$NGINX_BIN" "$APP/Contents/Helpers/nginx"
cp "$PHP_FPM_BIN" "$APP/Contents/Helpers/php-fpm"
if [ -n "$RAGD_BIN" ]; then cp "$RAGD_BIN" "$APP/Contents/Helpers/ragd"; else echo 'NOTE: RAGD_BIN missing: RAG service will be skipped'; fi
if [ -n "$MCP_SERVER_BIN" ]; then cp "$MCP_SERVER_BIN" "$APP/Contents/Helpers/mcp-server"; else echo 'NOTE: MCP_SERVER_BIN missing: MCP agent will be skipped'; fi
if [ -n "$MCP_GATEWAY_BIN" ]; then cp "$MCP_GATEWAY_BIN" "$APP/Contents/Helpers/mcp-gateway"; fi
chmod 755 "$APP/Contents/Helpers/"*

# The launcher can be thin or universal2, independent from the helper slices.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for arch in "${BUILD_ARCHS[@]}"; do
  echo "==> Compiling native launcher for $arch"
  "$SWIFTC" -O -sdk "$SDK" -target "${arch}-apple-macos11.0" \
    -framework AppKit -framework Security \
    -o "$TMP/LocalLightChat-$arch" "$ROOT/launcher/LocalLightChat.swift"
done
if [ "${#BUILD_ARCHS[@]}" -eq 2 ]; then
  lipo -create "$TMP/LocalLightChat-arm64" "$TMP/LocalLightChat-x86_64" \
    -output "$APP/Contents/MacOS/LocalLightChat"
else
  cp "$TMP/LocalLightChat-${BUILD_ARCHS[0]}" "$APP/Contents/MacOS/LocalLightChat"
fi
chmod 755 "$APP/Contents/MacOS/LocalLightChat"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>LocalLightChat</string>
  <key>CFBundleName</key><string>LocalLightChat</string>
  <key>CFBundleDisplayName</key><string>LocalLightChat</string>
  <key>CFBundleIconFile</key><string>LocalLightChat.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <!-- Normal Dock app with no extra controls window; the Dock icon opens the browser. -->
  <key>LSUIElement</key><false/>
  <key>LLCDevAdminLogin</key>$DEV_ADMIN_PLIST
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>LocalLightChat runs local services on your Mac.</string>
</dict></plist>
EOF

# Sign nested Mach-O files before outer bundle, NEVER use codesign --deep to sign.
sign_one() {
  local target="$1"
  if [ "$IDENTITY" = '-' ]; then
    codesign --force --sign - "$target"
  else
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$target"
  fi
}
for tool in "$APP/Contents/Helpers/"*; do
  echo "==> Signing helper: $(basename "$tool")"
  sign_one "$tool"
done
sign_one "$APP/Contents/MacOS/LocalLightChat"
# No writes anywhere inside .app after this point.
sign_one "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/LocalLightChat"
ZIP="$OUT/LocalLightChat-macos.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
cat <<EOF

Done:
  $APP
  $ZIP
Signature: $IDENTITY
Launcher: $ARCH (helpers may have different architectures)

Next:
  open "$APP"
  "$ROOT/verify_app.sh" "$APP"
EOF
if [ "$IDENTITY" = '-' ]; then
  echo 'NOTE: ad hoc signature is for LOCAL TESTING only; NOT notarizable.'
else
  echo 'NOTE: Submit the signed ZIP using notarize.sh, then staple the app.'
fi
