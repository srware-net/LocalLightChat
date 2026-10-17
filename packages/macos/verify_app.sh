#!/bin/bash
set -euo pipefail
APP="${1:?Usage: verify_app.sh /path/to/LocalLightChat.app}"
[ -d "$APP/Contents/Resources/www" ] || { echo 'Missing webroot' >&2; exit 1; }
[ -f "$APP/Contents/Resources/nginx/fastcgi_params" ] || { echo 'Missing nginx FastCGI params' >&2; exit 1; }
[ -x "$APP/Contents/MacOS/LocalLightChat" ] || { echo 'Missing native launcher' >&2; exit 1; }
[ -f "$APP/Contents/Resources/LocalLightChat.icns" ] || { echo 'Missing app icon' >&2; exit 1; }
for bin in "$APP/Contents/MacOS/LocalLightChat" "$APP/Contents/Helpers/"*; do
  [ -f "$bin" ] || continue
  echo "==> $(basename "$bin")"
  lipo -info "$bin"
  for arch in arm64 x86_64; do
    if lipo -verify_arch "$arch" "$bin" >/dev/null 2>&1; then
      otool -arch "$arch" -L "$bin"
    fi
  done
done
codesign --verify --deep --strict --verbose=2 "$APP"
echo 'Signature and architectures: OK'
