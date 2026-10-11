#!/usr/bin/env python3
"""
Convert an OpenWebUI SQLite database to a current LocalLightChat SQLite database.

Default behavior:
  - needs only the OpenWebUI DB path
  - creates a clean LocalLightChat SQLite DB from the embedded schema
  - writes locallightchat_converted.sqlite next to the input DB unless --out is given
  - creates/sets one LocalLightChat superadmin login: admin/admin
  - converts OpenWebUI folders, files and chats
  - converts each OpenWebUI chat's active/current message branch to LocalLightChat's linear messages_json
  - optionally converts OpenWebUI branches to LocalLightChat attached clone chats

Usage:
  python convert_openwebui_to_locallightchat.py openwebui.db

Useful options:
  --out converted.sqlite
  --template locallightchat.sqlite     # copy this DB first instead of creating a clean DB
  --branch-mode active                 # default: only OpenWebUI current branch
  --branch-mode branched               # create LocalLightChat attached clone chats for OpenWebUI branches
  --with-branched                      # shorthand for --branch-mode branched
  --branch-mode all                    # all messages chronologically; may flatten alternate branches oddly
  --media-storage inline|uploads|auto  # controls image/audio storage; auto follows LLC limits
  --image-storage inline|uploads|auto   # override only images
  --audio-storage inline|uploads|auto   # override only audio
  --uploads-dir PATH                  # where OpenWebUI upload files live
  --keep-existing                      # only meaningful with --template; do not wipe target data first
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import ntpath
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any, Optional


LOCAL_LIGHT_CHAT_SCHEMA = """
PRAGMA foreign_keys=OFF;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  email TEXT NULL UNIQUE,
  pass_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS folders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  parent_id TEXT NULL,
  name TEXT NOT NULL,
  is_archive INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(parent_id) REFERENCES folders(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS chats (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT 'New chat',
  preview TEXT NOT NULL DEFAULT '',
  folder_id TEXT NULL,
  connection_id TEXT NULL,
  model TEXT NULL,
  messages_json TEXT NOT NULL DEFAULT '[]',
  meta_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS files (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  original_name TEXT NOT NULL,
  stored_name TEXT NOT NULL,
  mime TEXT NOT NULL,
  size INTEGER NOT NULL,
  library_visible INTEGER NOT NULL DEFAULT 0,
  rag_document_id TEXT NOT NULL DEFAULT '',
  rag_job_id TEXT NOT NULL DEFAULT '',
  rag_state TEXT NOT NULL DEFAULT '',
  rag_chunks INTEGER NOT NULL DEFAULT 0,
  rag_embedding_model TEXT NOT NULL DEFAULT '',
  rag_error TEXT NOT NULL DEFAULT '',
  rag_indexed_at INTEGER NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS mcp_sessions (
  user_id TEXT NOT NULL,
  chat_id TEXT NOT NULL,
  server_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  protocol_version TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(user_id, chat_id, server_id),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_mcp_sessions_updated ON mcp_sessions(updated_at);

CREATE TABLE IF NOT EXISTS artifacts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  chat_id TEXT NOT NULL,
  run_id TEXT NOT NULL DEFAULT '',
  tool_call_id TEXT NOT NULL,
  source_server TEXT NOT NULL DEFAULT '',
  source_tool TEXT NOT NULL DEFAULT '',
  mime_type TEXT NOT NULL DEFAULT 'application/json',
  storage_path TEXT NOT NULL,
  size_bytes INTEGER NOT NULL DEFAULT 0,
  line_count INTEGER NOT NULL DEFAULT 0,
  token_count_original INTEGER NOT NULL DEFAULT 0,
  token_count_preview INTEGER NOT NULL DEFAULT 0,
  tokenizer_source TEXT NOT NULL DEFAULT 'estimated_chars_div_4',
  created_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_artifacts_user_chat ON artifacts(user_id, chat_id, created_at);
CREATE INDEX IF NOT EXISTS idx_artifacts_user_chat_run ON artifacts(user_id, chat_id, run_id);

CREATE TABLE IF NOT EXISTS workspaces (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_workspaces_user_updated ON workspaces(user_id, updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_one_archive_per_user ON folders(user_id) WHERE is_archive=1;
CREATE INDEX IF NOT EXISTS idx_files_user_library_created ON files(user_id, library_visible, created_at DESC);

CREATE TABLE IF NOT EXISTS templates (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS settings (
  user_id TEXT NOT NULL,
  k TEXT NOT NULL,
  v TEXT NOT NULL,
  PRIMARY KEY(user_id, k),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS connections (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  label TEXT NOT NULL,
  prefix TEXT NOT NULL DEFAULT '',
  base_url TEXT NOT NULL,
  api_key TEXT NOT NULL DEFAULT '',
  headers TEXT NULL,
  notes TEXT NOT NULL DEFAULT '',
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS global_connections (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  prefix TEXT NOT NULL DEFAULT '',
  base_url TEXT NOT NULL,
  api_key TEXT NOT NULL DEFAULT '',
  headers TEXT NULL,
  notes TEXT NOT NULL DEFAULT '',
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS global_settings (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);
"""

GLOBAL_SETTINGS_DEFAULTS = {
    "search_provider": "serper",
    "serper_api_key": "",
    "brave_api_key": "",
    "exa_api_key": "",
    "search_custom_url": "",
    "search_custom_news_url": "",
    "search_custom_api_key": "",
    "search_custom_allow_private": "0",
    "searchngx_url": "",
    "searchngx_api_key": "",
    "searchngx_allow_private": "0",
    "search_num": "10",
    "search_hl": "de",
    "search_gl": "de",
    "web_allow_private": "0",
    "web_fetch_max_chars": "50000",
    "web_tool_max_chars": "60000",
    "tool_max_iters": "20",
    "tool_simple_max_iters": "20",
    "tool_agentic_max_iters": "200",
    "agent_activity_mode": "tail",
    "agent_activity_max_tokens": "1000",
    "rag_url": "",
    "rag_top_k": "8",
    "rag_timeout_sec": "180",
    "upload_hard_limit_mb": "100",
    "media_image_inline_limit_mb": "8",
    "media_audio_inline_limit_mb": "15",
    "voice_tts_provider": "browser",
    "voice_api_key": "",
    "voice_tts_model": "gpt-4o-mini-tts",
    "voice_tts_voice": "marin",
    "image_provider": "openai",
    "image_api_key": "",
    "image_base_url": "https://api.openai.com/v1",
    "image_model": "gpt-image-2",
    "image_size": "auto",
    "image_quality": "auto",
    "image_background": "auto",
    "image_output_format": "png",
    "image_openrouter_api_key": "",
    "image_openrouter_base_url": "https://openrouter.ai/api/v1",
    "image_openrouter_model": "google/gemini-3-pro-image-preview",
    "image_comfyui_url": "",
    "image_comfyui_workflow_json": "",
    "image_comfyui_bindings_json": "",
    "image_comfyui_width": "512",
    "image_comfyui_height": "512",
    "image_comfyui_steps": "20",
    "image_comfyui_guidance": "3.5",
    "image_comfyui_seed": "-1",
    "image_comfyui_batch": "1",
    "image_comfyui_timeout_sec": "900",
    "image_comfyui_apply_defaults": "0",
    "image_comfyui_profiles_json": "[]",
    "image_comfyui_profile_id": "",
}

USER_SETTINGS_DEFAULTS = {
    "inherit_global_connections": "1",
    "allow_own_connections": "1",
    "inherit_global_web": "0",
    "inherit_global_search": "0",
    "inherit_global_image": "0",
    "inherit_global_voice": "0",
    "selected_connection_id": "",
    "selected_model": "",
    "system_prompt": "",
    "rag_default_mode": "hybrid",
    "rag_auto_enable": "0",
    "mcp_servers_json": "[]",
    "mcp_servers_auto_enable": "0",
    "mcp_context_mode": "externalize",
    "mcp_externalize_above_tokens": "6000",
    "mcp_preview_max_tokens": "2500",
    "mcp_full_first_pass_max_tokens": "32000",
    "pricing_json": "[]",
    "models_cache_json": "[]",
    "models_cache_at": "0",
    "web_auto_enable": "0",
    "web_search_auto_enable": "0",
    "web_prefer_attachments": "0",
    "voice_auto_enable": "0",
    "voice_auto_send": "1",
    "image_auto_enable": "0",
    "vision_auto_attach_last_image": "1",
    **GLOBAL_SETTINGS_DEFAULTS,
}

DEFAULT_GLOBAL_CONNECTIONS = [
    {
        "id": "gc_openai",
        "label": "OpenAI",
        "prefix": "OpenAI",
        "base_url": "https://api.openai.com/v1",
        "api_key": "",
        "headers": None,
        "notes": "",
        "enabled": 0,
    },
    {
        "id": "gc_openrouter",
        "label": "OpenRouter",
        "prefix": "OR",
        "base_url": "https://openrouter.ai/api/v1",
        "api_key": "",
        "headers": None,
        "notes": "",
        "enabled": 0,
    },
]

ADMIN_HASH_FALLBACK_FOR_ADMIN = "$2y$12$U0GvU/UKmMnA7esPt5DZmOzVAA2RkkhMT3d5iqVsXnDtirFfdIXy6"


def now_s() -> int:
    return int(time.time())


def stable_id(prefix: str, raw: str, n: int = 16) -> str:
    # UUID5 gives stable deterministic IDs but without leaking the long source UUID everywhere.
    h = uuid.uuid5(uuid.NAMESPACE_URL, raw).hex[:n]
    return f"{prefix}_{h}"


def as_int_seconds(value: Any, default: Optional[int] = None) -> int:
    if default is None:
        default = now_s()
    if value is None:
        return default
    try:
        v = int(float(value))
        # If milliseconds accidentally appear, normalize to seconds.
        if v > 10_000_000_000:
            v //= 1000
        return v
    except Exception:
        return default


def json_loads_or(value: Any, fallback: Any) -> Any:
    if value is None:
        return fallback
    if isinstance(value, (dict, list)):
        return value
    try:
        return json.loads(value)
    except Exception:
        return fallback


def json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def text_from_jsonish(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        # OpenWebUI chat_message.content is often a JSON string literal.
        try:
            decoded = json.loads(value)
            if isinstance(decoded, str):
                return decoded
            return json_dumps(decoded)
        except Exception:
            return value
    return str(value)


def extract_reasoning(content: str) -> tuple[str, str]:
    """Move OpenWebUI <details type="reasoning">...</details> blocks to LocalLightChat reasoning."""
    reasoning_parts: list[str] = []

    def repl(match: re.Match[str]) -> str:
        inner = match.group(1)
        # Remove summary line but keep the actual text, lightly de-HTML common entities.
        inner = re.sub(r"<summary>.*?</summary>", "", inner, flags=re.I | re.S).strip()
        inner = (inner.replace("&gt;", ">")
                      .replace("&lt;", "<")
                      .replace("&amp;", "&")
                      .replace("&#x27;", "'")
                      .replace("&quot;", '"'))
        reasoning_parts.append(inner.strip())
        return ""

    stripped = re.sub(r"<details[^>]*type=[\"']reasoning[\"'][^>]*>(.*?)</details>\s*", repl, content, flags=re.I | re.S)
    return stripped.strip(), "\n\n".join(p for p in reasoning_parts if p)



def human_size(n: int) -> str:
    try:
        n = int(n)
    except Exception:
        n = 0
    if n < 1024:
        return f"{n} B"
    if n < 1024 * 1024:
        return f"{n/1024:.1f} KB"
    return f"{n/(1024*1024):.1f} MB"


def ext_of(name: str) -> str:
    return Path(str(name or "")).suffix.lower().lstrip(".")


def is_image_mime_or_ext(mime: str, name: str) -> bool:
    return str(mime or "").lower().startswith("image/") or ext_of(name) in {"png", "jpg", "jpeg", "webp", "gif", "bmp"}


def is_audio_mime_or_ext(mime: str, name: str) -> bool:
    return str(mime or "").lower().startswith("audio/") or ext_of(name) in {"mp3", "wav", "m4a", "aac", "ogg", "oga", "opus", "flac", "webm"}


def audio_format_from_name_mime(name: str, mime: str) -> str:
    ext = ext_of(name)
    if ext in {"mp3", "wav", "m4a", "aac", "ogg", "oga", "opus", "flac", "webm"}:
        return "ogg" if ext == "oga" else ext
    m = str(mime or "").lower()
    if "mpeg" in m or "mp3" in m:
        return "mp3"
    if "wav" in m:
        return "wav"
    if "mp4" in m or "m4a" in m:
        return "m4a"
    if "aac" in m:
        return "aac"
    if "ogg" in m:
        return "ogg"
    if "opus" in m:
        return "opus"
    if "flac" in m:
        return "flac"
    if "webm" in m:
        return "webm"
    return ext or "mp3"


def data_url_for_bytes(mime: str, data: bytes) -> str:
    return f"data:{mime or 'application/octet-stream'};base64," + base64.b64encode(data).decode("ascii")


def safe_stored_name(file_id: str, original_name: str) -> str:
    ext = ext_of(original_name)
    base = re.sub(r"[^a-zA-Z0-9_\-]", "", str(file_id)) or stable_id("f", str(original_name), 20)
    return base + (f".{ext}" if ext else "")


def win_basename(path: str) -> str:
    # Works for both C:\foo\bar.png and /foo/bar.png even when running on Linux/macOS.
    return ntpath.basename(str(path or "").replace("/", "\\"))


class MediaContext:
    def __init__(
        self,
        *,
        openwebui_db: Path,
        uploads_dir: Optional[Path],
        llc_uploads_dir: Optional[Path],
        llc_upload_url_prefix: str,
        media_storage: str,
        image_storage: str,
        audio_storage: str,
        image_inline_limit_mb: int,
        audio_inline_limit_mb: int,
    ) -> None:
        self.openwebui_db = openwebui_db
        self.uploads_dir = uploads_dir
        self.llc_uploads_dir = llc_uploads_dir
        self.llc_upload_url_prefix = (llc_upload_url_prefix or "./uploads").rstrip("/")
        self.media_storage = media_storage
        self.image_storage = image_storage
        self.audio_storage = audio_storage
        self.image_inline_limit = max(0, int(image_inline_limit_mb)) * 1024 * 1024
        self.audio_inline_limit = max(0, int(audio_inline_limit_mb)) * 1024 * 1024
        self.files_by_id: dict[str, dict[str, Any]] = {}
        self.warnings: list[str] = []
        self.copied: set[str] = set()

    def policy_for(self, kind: str, size: int) -> str:
        specific = self.image_storage if kind == "image" else self.audio_storage
        policy = specific if specific != "auto" else self.media_storage
        if policy == "auto":
            limit = self.image_inline_limit if kind == "image" else self.audio_inline_limit
            return "inline" if (limit <= 0 or int(size or 0) <= limit) else "uploads"
        return policy

    def add_warning_once(self, msg: str) -> None:
        if msg not in self.warnings:
            self.warnings.append(msg)

    def file_info_from_attachment(self, file_obj: dict[str, Any]) -> dict[str, Any]:
        nested = file_obj.get("file") if isinstance(file_obj.get("file"), dict) else {}
        meta = nested.get("meta") if isinstance(nested.get("meta"), dict) else {}
        fid = str(file_obj.get("id") or nested.get("id") or file_obj.get("file_id") or stable_id("f", json_dumps(file_obj), 20))
        row = self.files_by_id.get(fid, {})
        row_meta = row.get("meta") if isinstance(row.get("meta"), dict) else {}
        name = str(file_obj.get("name") or nested.get("filename") or row.get("filename") or meta.get("name") or row_meta.get("name") or "attachment")
        mime = str(file_obj.get("content_type") or meta.get("content_type") or row_meta.get("content_type") or mimetypes.guess_type(name)[0] or "application/octet-stream")
        size = int(file_obj.get("size") or meta.get("size") or row_meta.get("size") or row.get("size") or 0)
        src_path = str(nested.get("path") or row.get("path") or "")
        return {"id": fid, "name": name, "mime": mime, "size": size, "source_path": src_path, "row": row}

    def candidate_paths(self, info: dict[str, Any]) -> list[Path]:
        src = str(info.get("source_path") or "")
        name = str(info.get("name") or "")
        fid = str(info.get("id") or "")
        basename = win_basename(src) if src else ""
        if not basename and fid and name:
            basename = f"{fid}_{name}"
        out: list[Path] = []
        if src:
            out.append(Path(src))
        dirs = []
        if self.uploads_dir:
            dirs.append(self.uploads_dir)
        dirs.append(self.openwebui_db.parent / "uploads")
        for d in dirs:
            if basename:
                out.append(Path(d) / basename)
            if fid and name:
                out.append(Path(d) / f"{fid}_{name}")
            if name:
                out.append(Path(d) / name)
        # Deduplicate while preserving order.
        seen = set()
        uniq = []
        for p in out:
            key = str(p)
            if key not in seen:
                seen.add(key); uniq.append(p)
        return uniq

    def read_source_bytes(self, info: dict[str, Any]) -> Optional[bytes]:
        for p in self.candidate_paths(info):
            try:
                if p.is_file():
                    return p.read_bytes()
            except Exception:
                pass
        return None

    def stored_name_for(self, info: dict[str, Any]) -> str:
        return safe_stored_name(str(info.get("id") or stable_id("f", str(info), 20)), str(info.get("name") or "attachment"))

    def ensure_stored(self, info: dict[str, Any], data: Optional[bytes] = None) -> tuple[str, str, bool]:
        """Return (stored_name, url, copied_ok)."""
        stored = self.stored_name_for(info)
        url = f"{self.llc_upload_url_prefix}/{stored}"
        if not self.llc_uploads_dir:
            return stored, url, False
        self.llc_uploads_dir.mkdir(parents=True, exist_ok=True)
        dest = self.llc_uploads_dir / stored
        if str(dest) in self.copied or dest.exists():
            return stored, url, True
        if data is None:
            data = self.read_source_bytes(info)
        if data is None:
            self.add_warning_once(f"Could not find upload file for {info.get('name')} ({info.get('id')}). Use --uploads-dir if the OpenWebUI uploads folder is elsewhere.")
            return stored, url, False
        try:
            dest.write_bytes(data)
            self.copied.add(str(dest))
            return stored, url, True
        except Exception as e:
            self.add_warning_once(f"Could not copy upload file {info.get('name')}: {e}")
            return stored, url, False


def attachment_from_openwebui(file_obj: dict[str, Any], media: Optional[MediaContext]) -> dict[str, Any]:
    """Best-effort attachment shape for LocalLightChat messages_json.

    LLC accepts two media modes:
      - inline: attachment has data_url
      - uploads: attachment has url + file_id + stored_only and a row in files
    """
    if media is None:
        nested = file_obj.get("file") if isinstance(file_obj.get("file"), dict) else {}
        meta = nested.get("meta") if isinstance(nested.get("meta"), dict) else {}
        return {
            "id": file_obj.get("id") or nested.get("id"),
            "name": file_obj.get("name") or nested.get("filename") or meta.get("name") or "attachment",
            "mime": file_obj.get("content_type") or meta.get("content_type") or "application/octet-stream",
            "size": int(file_obj.get("size") or meta.get("size") or 0),
        }

    info = media.file_info_from_attachment(file_obj)
    fid = str(info["id"])
    name = str(info["name"])
    mime = str(info["mime"])
    size = int(info["size"] or 0)
    att_id = "att_" + uuid.uuid5(uuid.NAMESPACE_URL, f"{fid}:{name}").hex[:9]

    common: dict[str, Any] = {"id": att_id, "name": name, "mime": mime, "size": size}

    if is_image_mime_or_ext(mime, name):
        policy = media.policy_for("image", size)
        data = media.read_source_bytes(info) if policy == "inline" else None
        if policy == "inline" and data is not None:
            return {**common, "type": "image", "meta": f"{human_size(len(data) or size)} · inline", "data_url": data_url_for_bytes(mime or "image/*", data), "size": len(data) or size}
        if policy == "inline" and data is None:
            media.add_warning_once(f"Could not inline image {name}; falling back to stored upload reference.")
        stored, url, copied = media.ensure_stored(info, data)
        return {**common, "type": "image", "meta": f"{human_size(size)} · stored in uploads", "url": url, "file_id": fid, "stored_only": True, "note": "Image stored in uploads; encoded again when sent to the model."}

    if is_audio_mime_or_ext(mime, name):
        policy = media.policy_for("audio", size)
        # LLC itself keeps audio as uploaded file even when inline, so do the same when possible.
        data = media.read_source_bytes(info)
        stored, url, copied = media.ensure_stored(info, data)
        if policy == "inline" and data is not None:
            return {**common, "type": "audio", "meta": f"{human_size(len(data) or size)} · inline audio", "data_url": data_url_for_bytes(mime or "audio/*", data), "url": url, "file_id": fid, "format": audio_format_from_name_mime(name, mime), "size": len(data) or size}
        if policy == "inline" and data is None:
            media.add_warning_once(f"Could not inline audio {name}; falling back to stored upload reference.")
        return {**common, "type": "audio", "meta": f"{human_size(size)} · stored in uploads", "url": url, "file_id": fid, "stored_only": True, "note": "Audio stored in uploads; encoded again when sent to the model.", "format": audio_format_from_name_mime(name, mime)}

    # Text files: prefer inline extracted content from OpenWebUI, then raw file bytes if available.
    if str(mime).startswith("text/") or ext_of(name) in {"txt", "md", "csv", "json", "jsonl", "xml", "yaml", "yml", "py", "js", "ts", "html", "css", "log"}:
        row = info.get("row") if isinstance(info.get("row"), dict) else {}
        dataj = row.get("data") if isinstance(row.get("data"), dict) else {}
        txt = dataj.get("content") if isinstance(dataj.get("content"), str) else None
        if txt is None:
            raw = media.read_source_bytes(info)
            if raw is not None:
                try:
                    txt = raw.decode("utf-8")
                except UnicodeDecodeError:
                    txt = raw.decode("utf-8", "replace")
        if txt is not None:
            return {**common, "type": "text", "meta": f"{human_size(size)} · inline", "text": txt, "truncated": False}

    stored, url, copied = media.ensure_stored(info)
    return {**common, "type": "file", "meta": f"{human_size(size)} · stored", "url": url, "file_id": fid, "not_sent": True}

def make_password_hash(password: str) -> str:
    """Return a bcrypt hash accepted by PHP/password_verify-style apps ($2y$)."""
    # 1) Try Python bcrypt if installed.
    try:
        import bcrypt  # type: ignore
        h = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode("ascii")
        return h.replace("$2b$", "$2y$", 1)
    except Exception:
        pass

    # 2) Try local PHP, which is common on systems running this kind of app.
    try:
        code = "echo password_hash($argv[1], PASSWORD_BCRYPT, ['cost'=>12]);"
        res = subprocess.run(["php", "-r", code, password], check=True, capture_output=True, text=True, timeout=10)
        h = res.stdout.strip()
        if h.startswith("$2y$") or h.startswith("$2b$"):
            return h.replace("$2b$", "$2y$", 1)
    except Exception:
        pass

    # 3) Last-resort deterministic fallback for exactly the requested admin/admin login.
    if password == "admin":
        return ADMIN_HASH_FALLBACK_FOR_ADMIN

    raise RuntimeError("Cannot create bcrypt password hash. Install Python package 'bcrypt' or PHP, or use --admin-password admin.")


def get_openwebui_user_id(src: sqlite3.Connection) -> str:
    row = src.execute("SELECT id FROM user ORDER BY created_at LIMIT 1").fetchone()
    if row:
        return str(row[0])
    row = src.execute("SELECT user_id FROM chat ORDER BY created_at LIMIT 1").fetchone()
    if row:
        return str(row[0])
    return "openwebui_user"


def convert_folders(src: sqlite3.Connection, dst: sqlite3.Connection, local_user_id: str) -> dict[str, str]:
    src.row_factory = sqlite3.Row
    mapping: dict[str, str] = {}
    rows = src.execute("SELECT * FROM folder ORDER BY created_at, name").fetchall()
    for r in rows:
        mapping[str(r["id"])] = stable_id("fld", str(r["id"]))

    for r in rows:
        old_id = str(r["id"])
        dst.execute(
            """INSERT OR REPLACE INTO folders
               (id,user_id,parent_id,name,is_archive,created_at,updated_at)
               VALUES (?,?,?,?,?,?,?)""",
            (
                mapping[old_id],
                local_user_id,
                mapping.get(str(r["parent_id"])) if r["parent_id"] else None,
                r["name"] or "Folder",
                0,
                as_int_seconds(r["created_at"]),
                as_int_seconds(r["updated_at"], as_int_seconds(r["created_at"])),
            ),
        )
    return mapping


def active_branch_messages(history: dict[str, Any]) -> list[dict[str, Any]]:
    messages = history.get("messages") if isinstance(history.get("messages"), dict) else {}
    if not messages:
        return []
    current_id = history.get("currentId")
    if not current_id or current_id not in messages:
        # pick newest leaf if no currentId
        leaves = [m for m in messages.values() if not m.get("childrenIds")]
        current = max(leaves or messages.values(), key=lambda m: as_int_seconds(m.get("timestamp"), 0))
        current_id = current.get("id")

    chain: list[dict[str, Any]] = []
    seen: set[str] = set()
    mid = current_id
    while mid and mid in messages and mid not in seen:
        seen.add(mid)
        m = messages[mid]
        chain.append(m)
        mid = m.get("parentId")
    chain.reverse()
    return chain


def all_messages(history: dict[str, Any]) -> list[dict[str, Any]]:
    messages = history.get("messages") if isinstance(history.get("messages"), dict) else {}
    return sorted(messages.values(), key=lambda m: (as_int_seconds(m.get("timestamp"), 0), str(m.get("id", ""))))


def branch_leaf_messages(history: dict[str, Any]) -> list[list[dict[str, Any]]]:
    """Return one root-to-leaf message path per OpenWebUI branch.

    OpenWebUI stores a chat as a message tree. LocalLightChat models a branch as
    a separate cloned chat that contains a full linear copy of the conversation
    up to that branch. This function returns exactly those linear paths.
    """
    messages = history.get("messages") if isinstance(history.get("messages"), dict) else {}
    if not messages:
        return []

    leaves = [m for m in messages.values() if not m.get("childrenIds")]
    if not leaves:
        leaves = list(messages.values())

    def chain_to_root(leaf: dict[str, Any]) -> list[dict[str, Any]]:
        chain: list[dict[str, Any]] = []
        seen: set[str] = set()
        mid = leaf.get("id")
        while mid and mid in messages and mid not in seen:
            seen.add(str(mid))
            m = messages[mid]
            chain.append(m)
            mid = m.get("parentId")
        chain.reverse()
        return chain

    paths = [chain_to_root(leaf) for leaf in leaves]
    # Stable order: active/current path first, then the rest by their last message timestamp.
    current_id = history.get("currentId")
    paths.sort(
        key=lambda path: (
            0 if path and path[-1].get("id") == current_id else 1,
            as_int_seconds(path[-1].get("timestamp"), 0) if path else 0,
            str(path[-1].get("id", "")) if path else "",
        )
    )
    return paths


def preview_from_messages(local_messages: list[dict[str, Any]]) -> str:
    # LLC's own preview tends to use the latest user message, not always the first one.
    last_user = next((m for m in reversed(local_messages) if m.get("role") == "user"), None)
    first_user = next((m for m in local_messages if m.get("role") == "user"), None)
    return str((last_user or first_user or {}).get("content", ""))[:240]


def title_for_variant(base_title: str, variant_index: int, leaf_message: Optional[dict[str, Any]] = None) -> str:
    title = base_title or "Imported chat"
    suffix = " (Variant)" if variant_index == 1 else f" (Variant {variant_index})"
    return f"{title}{suffix}"


def convert_one_message(m: dict[str, Any], default_model: Optional[str], default_connection: Optional[str], media: Optional[MediaContext]) -> dict[str, Any]:
    role = m.get("role") or "user"
    content, reasoning = extract_reasoning(str(m.get("content") or ""))
    ts_ms = as_int_seconds(m.get("timestamp")) * 1000
    out: dict[str, Any] = {
        "role": role,
        "content": content,
        "created_at": ts_ms,
    }
    files = m.get("files") if isinstance(m.get("files"), list) else []
    if role == "user":
        out["attachments"] = [attachment_from_openwebui(f, media) for f in files if isinstance(f, dict)]
    else:
        out["reasoning"] = reasoning
        out["created_at"] = ts_ms
        out["model"] = m.get("model") or default_model
        out["connection_id"] = default_connection
        out["incomplete"] = not bool(m.get("done", True))
        out["stopped"] = False
        out["metrics"] = {"runs": []}
    return out



def load_openwebui_files(src: sqlite3.Connection) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    try:
        rows = src.execute("SELECT * FROM file ORDER BY created_at").fetchall()
    except sqlite3.Error:
        return out
    for r in rows:
        keys = r.keys() if hasattr(r, "keys") else []
        d = {k: r[k] for k in keys}
        d["meta"] = json_loads_or(d.get("meta"), {})
        d["data"] = json_loads_or(d.get("data"), {})
        fid = str(d.get("id") or "")
        if fid:
            out[fid] = d
    return out


def insert_openwebui_files(src: sqlite3.Connection, dst: sqlite3.Connection, local_user_id: str, media: Optional[MediaContext]) -> int:
    files = load_openwebui_files(src)
    if media is not None:
        media.files_by_id = files
    count = 0
    for fid, d in files.items():
        meta = d.get("meta") if isinstance(d.get("meta"), dict) else {}
        original = str(d.get("filename") or meta.get("name") or "attachment")
        mime = str(meta.get("content_type") or mimetypes.guess_type(original)[0] or "application/octet-stream")
        size = int(meta.get("size") or 0)
        stored = media.stored_name_for({"id": fid, "name": original}) if media is not None else os.path.basename(d.get("path") or original)
        dst.execute(
            """INSERT OR REPLACE INTO files
               (id,user_id,original_name,stored_name,mime,size,library_visible,rag_document_id,rag_job_id,rag_state,rag_chunks,rag_embedding_model,rag_error,rag_indexed_at,created_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (fid, local_user_id, original, stored, mime, size, 0, "", "", "", 0, "", "", None, as_int_seconds(d.get("created_at"))),
        )
        count += 1
    return count

def convert_chats(src: sqlite3.Connection, dst: sqlite3.Connection, local_user_id: str, folder_map: dict[str, str], branch_mode: str, default_connection: Optional[str], media: Optional[MediaContext]) -> int:
    src.row_factory = sqlite3.Row
    count = 0
    rows = src.execute("SELECT * FROM chat ORDER BY created_at, title").fetchall()
    for r in rows:
        chat_json = json_loads_or(r["chat"], {})
        meta_json = json_loads_or(r["meta"], {})
        history = chat_json.get("history") if isinstance(chat_json.get("history"), dict) else {}
        model = None
        models = chat_json.get("models")
        if isinstance(models, list) and models:
            model = str(models[0])

        base_title = r["title"] or chat_json.get("title") or "Imported chat"
        base_chat_id = stable_id("chat", str(r["id"]))
        base_created = as_int_seconds(r["created_at"])
        base_updated = as_int_seconds(r["updated_at"], base_created)
        folder_id = folder_map.get(str(r["folder_id"])) if r["folder_id"] else None

        def insert_chat(
            *,
            chat_id: str,
            title: str,
            source_messages: list[dict[str, Any]],
            created_at: int,
            updated_at: int,
            branch_label: str,
            clone_meta: Optional[dict[str, Any]] = None,
        ) -> None:
            local_messages = [convert_one_message(m, model, default_connection, media) for m in source_messages]
            local_meta: dict[str, Any] = {
                "system_prompt": "",
                "params": [],
                "document": {"activeId": None, "documents": [], "collapsed": False, "maximized": False, "viewMode": "preview"},
                "openwebui": {
                    "source_chat_id": r["id"],
                    "source_meta": meta_json,
                    "source_tags": chat_json.get("tags", []),
                    "branch_mode": branch_mode,
                    "branch": branch_label,
                    "source_leaf_id": source_messages[-1].get("id") if source_messages else None,
                },
            }
            if clone_meta:
                local_meta["clone"] = clone_meta
            dst.execute(
                """INSERT OR REPLACE INTO chats
                   (id,user_id,title,preview,folder_id,connection_id,model,messages_json,meta_json,created_at,updated_at)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    chat_id,
                    local_user_id,
                    title,
                    preview_from_messages(local_messages),
                    folder_id,
                    default_connection,
                    model,
                    json_dumps(local_messages),
                    json_dumps(local_meta),
                    created_at,
                    updated_at,
                ),
            )

        if branch_mode == "branched":
            paths = branch_leaf_messages(history)
            if not paths:
                paths = [active_branch_messages(history)]

            # The first path is the active/current OpenWebUI branch. It becomes the root LLC chat.
            root_path = paths[0]
            insert_chat(
                chat_id=base_chat_id,
                title=base_title,
                source_messages=root_path,
                created_at=base_created,
                updated_at=base_updated,
                branch_label="root-active",
            )
            count += 1

            # Every other OpenWebUI leaf becomes an attached LLC clone chat.
            # This is exactly LLC's own variant model: a full linear chat copy with meta.clone.
            for i, path in enumerate(paths[1:], start=1):
                leaf_id = str(path[-1].get("id") if path else f"variant-{i}")
                chat_id = stable_id("chat", f"{r['id']}::branch::{leaf_id}")
                leaf_ts = as_int_seconds(path[-1].get("timestamp"), base_updated) if path else base_updated
                insert_chat(
                    chat_id=chat_id,
                    title=title_for_variant(base_title, i, path[-1] if path else None),
                    source_messages=path,
                    created_at=leaf_ts,
                    updated_at=max(leaf_ts, base_updated),
                    branch_label=f"variant-{i}",
                    clone_meta={
                        "attached": True,
                        "parent_id": base_chat_id,
                        "root_id": base_chat_id,
                        "created_at": leaf_ts,
                    },
                )
                count += 1
            continue

        source_messages = all_messages(history) if branch_mode == "all" else active_branch_messages(history)
        insert_chat(
            chat_id=base_chat_id,
            title=base_title,
            source_messages=source_messages,
            created_at=base_created,
            updated_at=base_updated,
            branch_label=branch_mode,
        )
        count += 1
    return count



def create_clean_local_db(output_db: Path, *, local_user_id: str) -> None:
    if output_db.exists():
        output_db.unlink()
    con = sqlite3.connect(output_db)
    try:
        con.executescript(LOCAL_LIGHT_CHAT_SCHEMA)
        seed_default_settings(con, local_user_id)
        con.commit()
    finally:
        con.close()


def seed_default_settings(dst: sqlite3.Connection, local_user_id: str) -> None:
    t = now_s()
    for k, v in GLOBAL_SETTINGS_DEFAULTS.items():
        dst.execute("INSERT OR REPLACE INTO global_settings (k,v) VALUES (?,?)", (k, v))
    for k, v in USER_SETTINGS_DEFAULTS.items():
        dst.execute("INSERT OR REPLACE INTO settings (user_id,k,v) VALUES (?,?,?)", (local_user_id, k, v))
    for c in DEFAULT_GLOBAL_CONNECTIONS:
        dst.execute(
            """INSERT OR REPLACE INTO global_connections
               (id,label,prefix,base_url,api_key,headers,notes,enabled,created_at,updated_at)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (c["id"], c["label"], c["prefix"], c["base_url"], c["api_key"], c["headers"], c["notes"], c["enabled"], t, t),
        )


def first_global_connection_id(dst: sqlite3.Connection) -> Optional[str]:
    try:
        row = dst.execute("SELECT id FROM global_connections WHERE enabled=1 ORDER BY created_at LIMIT 1").fetchone()
        return str(row[0]) if row else None
    except sqlite3.Error:
        return None


def wipe_local(dst: sqlite3.Connection) -> None:
    # The naked truth: LocalLightChat has no foreign keys in these tables here, so simple deletes are enough.
    for table in ["mcp_sessions", "artifacts", "chats", "folders", "files", "templates", "workspaces", "sessions", "users"]:
        try:
            dst.execute(f"DELETE FROM {table}")
        except sqlite3.Error:
            pass


def set_admin(dst: sqlite3.Connection, username: str, password: str, local_user_id: str) -> None:
    t = now_s()
    dst.execute(
        """INSERT OR REPLACE INTO users
           (id,username,email,pass_hash,role,created_at,updated_at)
           VALUES (?,?,?,?,?,?,?)""",
        (local_user_id, username, None, make_password_hash(password), "superadmin", t, t),
    )
    # Repoint existing per-user settings from template to the new admin user if needed.
    try:
        dst.execute("UPDATE settings SET user_id=?", (local_user_id,))
    except sqlite3.Error:
        pass


def convert(openwebui_db: Path, output_db: Path, *, template: Optional[Path], clean: bool, admin_user: str, admin_password: str, local_user_id: str, branch_mode: str, keep_existing: bool, uploads_dir: Optional[Path], llc_uploads_dir: Optional[Path], llc_upload_url_prefix: str, media_storage: str, image_storage: str, audio_storage: str, image_inline_limit_mb: int, audio_inline_limit_mb: int) -> dict[str, int | str]:
    if not openwebui_db.exists():
        raise FileNotFoundError(openwebui_db)

    if template and clean:
        raise ValueError("Use either --template or --clean, not both.")

    if template:
        if not template.exists():
            raise FileNotFoundError(template)
        if output_db.exists():
            output_db.unlink()
        shutil.copy2(template, output_db)
        db_mode = "template"
    else:
        create_clean_local_db(output_db, local_user_id=local_user_id)
        db_mode = "clean"

    if llc_uploads_dir is None:
        llc_uploads_dir = output_db.parent / "uploads"
    media = MediaContext(
        openwebui_db=openwebui_db,
        uploads_dir=uploads_dir,
        llc_uploads_dir=llc_uploads_dir,
        llc_upload_url_prefix=llc_upload_url_prefix,
        media_storage=media_storage,
        image_storage=image_storage,
        audio_storage=audio_storage,
        image_inline_limit_mb=image_inline_limit_mb,
        audio_inline_limit_mb=audio_inline_limit_mb,
    )

    src = sqlite3.connect(openwebui_db)
    src.row_factory = sqlite3.Row
    dst = sqlite3.connect(output_db)
    dst.row_factory = sqlite3.Row
    try:
        dst.execute("PRAGMA foreign_keys=OFF")
        if not keep_existing:
            wipe_local(dst)
        set_admin(dst, admin_user, admin_password, local_user_id)
        # Mirror LLC's own media settings in the generated DB.
        effective_img = image_storage if image_storage != "auto" else media_storage
        effective_aud = audio_storage if audio_storage != "auto" else media_storage
        if effective_img in {"inline", "uploads"}:
            dst.execute("INSERT OR REPLACE INTO settings (user_id,k,v) VALUES (?,?,?)", (local_user_id, "media_image_inline", "1" if effective_img == "inline" else "0"))
        if effective_aud in {"inline", "uploads"}:
            dst.execute("INSERT OR REPLACE INTO settings (user_id,k,v) VALUES (?,?,?)", (local_user_id, "media_audio_inline", "1" if effective_aud == "inline" else "0"))
        dst.execute("INSERT OR REPLACE INTO global_settings (k,v) VALUES (?,?)", ("media_image_inline_limit_mb", str(image_inline_limit_mb)))
        dst.execute("INSERT OR REPLACE INTO global_settings (k,v) VALUES (?,?)", ("media_audio_inline_limit_mb", str(audio_inline_limit_mb)))

        connection_id = first_global_connection_id(dst)
        folder_map = convert_folders(src, dst, local_user_id)
        file_count = insert_openwebui_files(src, dst, local_user_id, media)
        chat_count = convert_chats(src, dst, local_user_id, folder_map, branch_mode, connection_id, media)
        dst.commit()
        return {"folders": len(folder_map), "files": file_count, "chats": chat_count, "mode": db_mode, "warnings": len(media.warnings), "media_warnings": "\n".join(media.warnings)}
    finally:
        src.close()
        dst.close()


def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        description="Convert OpenWebUI SQLite DB to a clean LocalLightChat SQLite DB",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("openwebui_db", type=Path, help="OpenWebUI SQLite database to import")
    ap.add_argument("--out", "-o", type=Path, default=None, help="Output LocalLightChat SQLite database")
    ap.add_argument("--template", type=Path, default=None, help="Optional existing LocalLightChat DB to copy and fill instead of creating a clean DB")
    ap.add_argument("--clean", action="store_true", help="Force clean embedded-schema mode. This is already the default.")
    ap.add_argument("--admin-user", default="admin")
    ap.add_argument("--admin-password", default="admin")
    ap.add_argument("--local-user-id", default="u_admin")
    ap.add_argument("--branch-mode", choices=["active", "all", "branched"], default="active")
    ap.add_argument("--with-branched", "--with_branched", action="store_true", help="Shorthand for --branch-mode branched: create LLC cloned chats for OpenWebUI branches")
    ap.add_argument("--keep-existing", action="store_true", help="Only meaningful with --template")
    ap.add_argument("--uploads-dir", type=Path, default=None, help="OpenWebUI uploads folder. Auto-tries <openwebui_db>/../uploads and paths stored in OpenWebUI.")
    ap.add_argument("--llc-uploads-dir", type=Path, default=None, help="Where copied LocalLightChat upload files should be written. Default: <output_db_dir>/uploads")
    ap.add_argument("--llc-upload-url-prefix", default="./uploads", help="URL prefix written into LLC attachment urls")
    ap.add_argument("--media-storage", choices=["auto", "inline", "uploads"], default="auto", help="Default storage for image/audio attachments. auto follows LLC limits.")
    ap.add_argument("--image-storage", choices=["auto", "inline", "uploads"], default="auto", help="Override storage for images")
    ap.add_argument("--audio-storage", choices=["auto", "inline", "uploads"], default="auto", help="Override storage for audio")
    ap.add_argument("--image-inline-limit-mb", type=int, default=8, help="In auto mode, inline images up to this size; bigger images go to uploads. 0 means unlimited.")
    ap.add_argument("--audio-inline-limit-mb", type=int, default=15, help="In auto mode, inline audio up to this size; bigger audio goes to uploads. 0 means unlimited.")
    args = ap.parse_args(argv)

    if args.with_branched:
        args.branch_mode = "branched"

    output_db = args.out or args.openwebui_db.with_name("locallightchat_converted.sqlite")

    stats = convert(
        args.openwebui_db,
        output_db,
        template=args.template,
        clean=args.clean,
        admin_user=args.admin_user,
        admin_password=args.admin_password,
        local_user_id=args.local_user_id,
        branch_mode=args.branch_mode,
        keep_existing=args.keep_existing,
        uploads_dir=args.uploads_dir,
        llc_uploads_dir=args.llc_uploads_dir,
        llc_upload_url_prefix=args.llc_upload_url_prefix,
        media_storage=args.media_storage,
        image_storage=args.image_storage,
        audio_storage=args.audio_storage,
        image_inline_limit_mb=args.image_inline_limit_mb,
        audio_inline_limit_mb=args.audio_inline_limit_mb,
    )
    print(f"Done. Wrote {output_db}")
    print(f"Mode: {stats['mode']}")
    print(f"Admin login: {args.admin_user}/{args.admin_password}")
    print(f"Converted: {stats['folders']} folders, {stats.get('files', 0)} files, {stats['chats']} chats")
    if int(stats.get("warnings", 0)):
        print("Warnings:")
        print(stats.get("media_warnings", ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
