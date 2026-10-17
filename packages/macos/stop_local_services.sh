#!/bin/bash
# Gracefully stop LocalLightChat's own macOS helpers when its launcher or
# menu-bar item is no longer accessible.  Never use a global pkill.
# Usage: ./stop_local_services.sh [--dry-run]
set -euo pipefail

case "${1:-}" in
  '') DRY_RUN=0 ;;
  --dry-run) DRY_RUN=1 ;;
  -h|--help)
    echo 'Usage: ./stop_local_services.sh [--dry-run]'
    echo 'Only stops processes whose commands/executable mappings belong to LocalLightChat.app.'
    exit 0 ;;
  *) echo 'Usage: ./stop_local_services.sh [--dry-run]' >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2

command -v lsof >/dev/null 2>&1 || { echo 'ERROR: lsof not found.' >&2; exit 1; }
command -v ps >/dev/null 2>&1 || { echo 'ERROR: ps not found.' >&2; exit 1; }
MY_UID="$(id -u)"

# Mac 'ps -ww' prevents command truncation. Only the current user's processes
# are eligible. We also require proof from their argv or Mach-O mapping.
process_command() { ps -ww -p "$1" -o command= 2>/dev/null || true; }
process_owner() { ps -p "$1" -o uid= 2>/dev/null | tr -d '[:space:]' || true; }
process_image() { lsof -nP -a -p "$1" -d txt -Fn 2>/dev/null || true; }

is_our_helper() {
  local cmd="$1" image="$2"
  case "$cmd\n$image" in
    *'/LocalLightChat.app/Contents/Helpers/'*|*'/Library/Application Support/LocalLightChat/'*|*'/Library/Caches/LocalLightChat/'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Identify the exact helper service; never send signals to other applications.
service_kind() {
  local name="$1"
  case "$name" in
    *'/Helpers/nginx'*|*'nginx: master process'*|*'nginx: worker process'*) echo nginx ;;
    *'/Helpers/php-fpm'*|*'php-fpm: master process'*|*'php-fpm: pool'*) echo php-fpm ;;
    *'/Helpers/ragd'*|*'/ragd.conf'*) echo ragd ;;
    *'/Helpers/mcp-server'*|*'/mcp-server.json'*) echo mcp-server ;;
    *) echo unknown ;;
  esac
}

# The launcher can disappear while its children remain alive. Scan the actual
# listening ports AND the runtime pid files, not every nginx on the machine.
pids="$(lsof -nP -t -iTCP:8081 -iTCP:8082 -iTCP:9002 -iTCP:8765 -iTCP:8787 -sTCP:LISTEN 2>/dev/null || true)"
if [ -n "${HOME:-}" ]; then
  for file in "$HOME/Library/Caches/LocalLightChat/run/nginx.pid" "$HOME/Library/Caches/LocalLightChat/run/php/php-fpm.pid"; do
    if [ -f "$file" ]; then
      value="$(cat "$file" 2>/dev/null || true)"
      case "$value" in ''|*[!0-9]*) ;; *) pids="${pids}${pids:+
}$value" ;; esac
    fi
  done
fi

# Collect the app launcher separately. Killing it alone is not enough if it
# has crashed, but it should also be terminated after its helpers.
app_pids="$(pgrep -u "$MY_UID" -f '/LocalLightChat[.]app/Contents/MacOS/LocalLightChat' 2>/dev/null || true)"

selected_pids=()
selected_types=()
if [ -n "$pids" ]; then
  while IFS= read -r pid; do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    [ "$pid" != "$$" ] || continue
    [ "$(process_owner "$pid")" = "$MY_UID" ] || continue
    cmd="$(process_command "$pid")"
    image="$(process_image "$pid")"
    if is_our_helper "$cmd" "$image"; then
      kind="$(service_kind "$cmd $image")"
      if [ "$kind" != unknown ]; then
        selected_pids+=("$pid")
        selected_types+=("$kind")
      fi
    fi
  done < <(printf '%s\n' "$pids" | sort -un)
fi

selected_apps=()
if [ -n "$app_pids" ]; then
  while IFS= read -r pid; do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    [ "$pid" != "$$" ] || continue
    [ "$(process_owner "$pid")" = "$MY_UID" ] || continue
    cmd="$(process_command "$pid")"
    case "$cmd" in *'/LocalLightChat.app/Contents/MacOS/LocalLightChat'*) selected_apps+=("$pid") ;; esac
  done < <(printf '%s\n' "$app_pids" | sort -un)
fi

if [ "${#selected_pids[@]}" -eq 0 ] && [ "${#selected_apps[@]}" -eq 0 ]; then
  echo 'No verified LocalLightChat processes found. Nothing to stop.'
  echo 'If reset still reports occupied ports, inspect those processes manually.'
  exit 0
fi

echo 'Verified LocalLightChat processes:'
for i in "${!selected_pids[@]}"; do
  printf '  %s  pid=%s\n' "${selected_types[$i]}" "${selected_pids[$i]}"
done
for pid in "${selected_apps[@]}"; do printf '  launcher  pid=%s\n' "$pid"; done

if [ "$DRY_RUN" -eq 1 ]; then
  echo 'DRY RUN: No signals sent.'
  exit 0
fi

# QUIT = graceful Nginx/PHP-FPM shutdown; TERM for other helpers and launcher.
for i in "${!selected_pids[@]}"; do
  pid="${selected_pids[$i]}"
  kind="${selected_types[$i]}"
  case "$kind" in nginx|php-fpm) signal=QUIT ;; *) signal=TERM ;; esac
  kill -s "$signal" "$pid" 2>/dev/null || true
done
for pid in "${selected_apps[@]}"; do
  kill -s TERM "$pid" 2>/dev/null || true
done

# Give the services time to exit. NEVER send SIGKILL or remove data here.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  alive=0
  for pid in "${selected_pids[@]}" "${selected_apps[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then alive=1; fi
  done
  [ "$alive" -eq 0 ] && break
  sleep 0.5
done

remaining="$(lsof -nP -iTCP:8081 -iTCP:8082 -iTCP:9002 -iTCP:8765 -iTCP:8787 -sTCP:LISTEN 2>/dev/null || true)"
if [ -n "$remaining" ]; then
  echo 'WARNING: One or more service ports are still occupied:' >&2
  printf '%s\n' "$remaining" >&2
  echo 'No force-kill was performed. Investigate before resetting data.' >&2
  exit 1
fi
echo 'LocalLightChat services stopped. You can now run ./reset_local_data.sh --yes'
