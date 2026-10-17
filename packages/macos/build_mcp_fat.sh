#!/bin/bash
# Build universal2 macOS MCP binaries from existing arm64 and x86_64 executables.
# No Homebrew, CMake, or compilation required. Requires Apple Command Line Tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# -------------------------- CONFIGURE ONCE --------------------------
# Put the builder in the same folder as build_app.sh to have its output go
# directly into that application's binaries/ directory.
INPUT_DIR="$ROOT/mcp-fat-input"
OUTPUT_DIR="$ROOT/binaries"

# Input filenames may use either of the aliases listed in find_input().
# The final filenames intentionally match build_app.sh.
SIGN_IDENTITY="-"  # - = ad hoc signature (for local builds)
# --------------------------------------------------------------------

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

case "${1:-}" in
  --help|-h)
    cat <<EOF
Usage: ./build_mcp_fat.sh

Place these macOS executables in:
  mcp-fat-input/arm64/mcp_server
  mcp-fat-input/x86_64/mcp_server
  mcp-fat-input/arm64/llc-mcp-gateway
  mcp-fat-input/x86_64/llc-mcp-gateway

Creates:
  binaries/mcp_server-universal2
  binaries/llc-mcp-gateway-universal2

No compiler or dependency manager required.
EOF
    exit 0 ;;
  '') ;;
  *) fail "Unknown argument: $1 (try --help)" ;;
esac

[ "$(uname -s)" = Darwin ] || fail 'Run this script on macOS (Apple lipo/codesign required).'
for cmd in lipo codesign file mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Missing '$cmd'. Install Xcode Command Line Tools: xcode-select --install"
done

# We allow a few common executable names, but the architecture always comes
# from the Mach-O header, never the filename.
find_input() {
  local arch="$1" role="$2" base="" candidate="" found=""
  local folder="$INPUT_DIR/$arch"
  [ -d "$folder" ] || fail "Missing input folder: $folder"

  if [ "$role" = server ]; then
    for base in mcp_server mcp-server llc-mcp-server; do
      for candidate in "$folder/$base" "$folder/$base-$arch"; do
        if [ -f "$candidate" ]; then
          [ -z "$found" ] || fail "Several MCP server candidates in $folder. Keep only one."
          found="$candidate"
        fi
      done
    done
  else
    for base in llc-mcp-gateway llc_mcp_gateway mcp-gateway mcp_gateway; do
      for candidate in "$folder/$base" "$folder/$base-$arch"; do
        if [ -f "$candidate" ]; then
          [ -z "$found" ] || fail "Several MCP gateway candidates in $folder. Keep only one."
          found="$candidate"
        fi
      done
    done
  fi
  [ -n "$found" ] || fail "Missing $role binary in $folder. See ./build_mcp_fat.sh --help"
  printf '%s\n' "$found"
}

check_input() {
  local path="$1" expect_arch="$2" archs=""
  file "$path" | grep -q 'Mach-O' || fail "Not a macOS Mach-O binary: $path"
  archs="$(lipo -archs "$path" 2>/dev/null)" || fail "Cannot inspect architecture: $path"
  [ "$archs" = "$expect_arch" ] || fail "Expected a THIN $expect_arch binary, got '$archs': $path"
  [ -s "$path" ] || fail "Empty executable: $path"
}

server_arm="$(find_input arm64 server)"
server_x86="$(find_input x86_64 server)"
gateway_arm="$(find_input arm64 gateway)"
gateway_x86="$(find_input x86_64 gateway)"

check_input "$server_arm" arm64
check_input "$server_x86" x86_64
check_input "$gateway_arm" arm64
check_input "$gateway_x86" x86_64

mkdir -p "$OUTPUT_DIR"
TEMP_DIR="$(mktemp -d "$OUTPUT_DIR/.mcp-fat.XXXXXXXX")" || fail 'Cannot create staging directory'
cleanup() { [ -z "${TEMP_DIR:-}" ] || rm -rf -- "$TEMP_DIR"; }
trap cleanup EXIT

make_fat() {
  local name="$1" arm="$2" x86="$3" target=""
  target="$TEMP_DIR/$name"
  info "Combining $name"
  lipo -create "$arm" "$x86" -output "$target"
  # Each architecture must be checked SEPARATELY; a multi-architecture
  # -verify_arch invocation fails on some versions of lipo.
  lipo -verify_arch arm64 "$target" >/dev/null || fail "$name: arm64 verification failed"
  lipo -verify_arch x86_64 "$target" >/dev/null || fail "$name: x86_64 verification failed"
  chmod 755 "$target"

  # lipo modifies the Mach-O data; sign the FINAL fat binary, not the slices.
  if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --sign "$SIGN_IDENTITY" "$target"
    codesign --verify --strict "$target" || fail "$name: signature verification failed"
  fi
  file "$target"
  lipo -info "$target"
}

make_fat mcp_server-universal2 "$server_arm" "$server_x86"
make_fat llc-mcp-gateway-universal2 "$gateway_arm" "$gateway_x86"

# Only replace existing build inputs once BOTH files have been built/validated.
mv -f "$TEMP_DIR/mcp_server-universal2" "$OUTPUT_DIR/mcp_server-universal2"
mv -f "$TEMP_DIR/llc-mcp-gateway-universal2" "$OUTPUT_DIR/llc-mcp-gateway-universal2"

printf '\nSUCCESS — ready for build_app.sh:\n'
printf '  %s\n' "$OUTPUT_DIR/mcp_server-universal2" "$OUTPUT_DIR/llc-mcp-gateway-universal2"
printf '\nNote: The .app packaging step must re-sign these helpers with Developer ID for notarization.\n'
