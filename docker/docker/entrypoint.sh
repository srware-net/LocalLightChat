#!/usr/bin/env bash
set -Eeuo pipefail

DATA_ROOT=/var/lib/locallightchat
RAG_BIN=/opt/locallightchat/rag/ragd
MCP_BIN=/opt/locallightchat/mcp/mcp_server
RAG_CONFIG=/config/ragd.conf
MCP_CONFIG=/config/mcp-server.json

mkdir -p \
  /run/nginx \
  "$DATA_ROOT/data/rag" \
  "$DATA_ROOT/data/mcp" \
  "$DATA_ROOT/data/artifacts" \
  "$DATA_ROOT/uploads" \
  "$DATA_ROOT/workspaces" \
  "$DATA_ROOT/tmp"

# Compatibility for code paths/URLs that still resolve /var/www/html/uploads.
rm -rf /var/www/html/uploads
ln -sfn "$DATA_ROOT/uploads" /var/www/html/uploads

chown -R www-data:www-data "$DATA_ROOT"

for file in "$RAG_BIN" "$MCP_BIN" "$RAG_CONFIG" "$MCP_CONFIG"; do
  if [[ ! -e "$file" ]]; then
    echo "ERROR: required file is missing: $file" >&2
    exit 1
  fi
done

pids=()
names=()
shutting_down=0

start_process() {
  local name="$1"
  shift
  echo "[entrypoint] starting $name"
  "$@" &
  pids+=("$!")
  names+=("$name")
}

shutdown_all() {
  local status="${1:-0}"
  if (( shutting_down )); then
    return
  fi
  shutting_down=1

  trap - TERM INT
  echo "[entrypoint] stopping services"

  local pid
  for pid in "${pids[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done

  for pid in "${pids[@]:-}"; do
    wait "$pid" 2>/dev/null || true
  done

  exit "$status"
}

trap 'shutdown_all 143' TERM
trap 'shutdown_all 130' INT

# Explicit config paths: no dependency on process working directories.
# RAG/MCP run unprivileged; nginx keeps its normal root master/www-data workers.
# ragd requires a non-empty llama_url. The Docker default intentionally ships
# without an inference endpoint, so keep RAG disabled until the user configures it.
rag_llama_url="$(awk -F= '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*llama_url[[:space:]]*=/ {
    sub(/^[^=]*=/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit
  }
' "$RAG_CONFIG")"

if [[ -n "$rag_llama_url" ]]; then
  start_process ragd gosu www-data:www-data "$RAG_BIN" --config "$RAG_CONFIG"
else
  echo "[entrypoint] ragd disabled: llama_url is empty in $RAG_CONFIG"
fi

start_process mcp_server gosu www-data:www-data "$MCP_BIN" "$MCP_CONFIG"
start_process php-fpm php-fpm --nodaemonize
start_process nginx nginx -g 'daemon off;'

set +e
wait -n "${pids[@]}"
status=$?
set -e

# Identify a process that stopped, if possible.
for i in "${!pids[@]}"; do
  if ! kill -0 "${pids[$i]}" 2>/dev/null; then
    echo "[entrypoint] ${names[$i]} exited (status $status)" >&2
    break
  fi
done

shutdown_all "$status"
