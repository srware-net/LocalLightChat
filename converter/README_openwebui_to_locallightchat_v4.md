# OpenWebUI → LocalLightChat SQLite Converter

A Python converter for migrating chats from an OpenWebUI SQLite database into a LocalLightChat SQLite database.

**Current converter version: v4.** The embedded clean database schema matches the current LocalLightChat database structure, including archive folders, workspaces, artifacts, MCP sessions, and file-library/RAG fields.

The converter is designed to be safe by default:

- It creates a fresh LocalLightChat-compatible database unless you explicitly provide a template database.
- It creates a single LocalLightChat admin account by default: `admin / admin`.
- It does **not** copy API keys, tokens, sessions, provider secrets, or OpenWebUI login credentials.
- It can convert regular chats, folders, file metadata, image/audio attachments, and optionally OpenWebUI branches as LocalLightChat cloned chats.

---

## Legal status and third-party notice

This project is an independent converter for interoperability and migration purposes. It is not affiliated with, endorsed by, sponsored by, or maintained by Open WebUI Inc.

The converter does not include Open WebUI source code. It only reads user-provided SQLite database files and, when configured, user-provided upload files in order to convert them into a LocalLightChat-compatible format.

Open WebUI is a separate third-party project and is licensed separately by its respective copyright holder. This converter is **not** licensed under the Open WebUI license, and Open WebUI is **not** licensed under this converter's license. The two projects have separate codebases, separate ownership, and separate licenses.

Open WebUI notice:

```text
Copyright (c) 2023- Open WebUI Inc.
Created by Timothy Jaeryang Baek.
All rights reserved.
```

Open WebUI, its name, source code, branding, and related materials belong to their respective owners. Any use of the name "Open WebUI" in this project is purely descriptive: it identifies the source database format that this converter can read.

Official Open WebUI repository:

```text
https://github.com/open-webui/open-webui
```

Official Open WebUI license:

```text
https://github.com/open-webui/open-webui/blob/main/LICENSE
```

---

## License of this converter

Unless stated otherwise in this repository, the converter code itself is licensed under the license provided with this project.

That license applies only to this converter's own source code and documentation. It does not apply to Open WebUI, LocalLightChat, user databases, exported chats, uploaded media files, model outputs, API keys, tokens, or any third-party software.

If you publish this tool, keep the third-party notice above visible in the README or in a separate `THIRD_PARTY_NOTICES.md` / `NOTICE` file.

---

## Basic usage

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db
```

This creates:

```text
locallightchat_converted.sqlite
```

next to `openwebui.db`.

The resulting LocalLightChat login is:

```text
username: admin
password: admin
```

---

## Recommended usage with media uploads

If your OpenWebUI database references uploaded files, images, or audio files, point the converter at the OpenWebUI uploads folder:

### Windows

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db ^
  --uploads-dir C:\finetune\openwebui\uploads
```

### Linux/macOS

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir /path/to/openwebui/uploads
```

Without `--uploads-dir`, the converter tries to find files automatically by checking paths stored in OpenWebUI and the folder next to the database:

```text
<directory-containing-openwebui.db>/uploads
```

If the original media files are not available, the converter can still preserve metadata, but it cannot embed or copy the actual file content.

---

## What gets converted

The converter currently migrates:

- OpenWebUI folders
- OpenWebUI chats
- Chat messages
- Active/current OpenWebUI message branches by default
- Optional OpenWebUI alternate branches as LocalLightChat cloned chats
- File metadata
- Image attachments
- Audio attachments
- Basic attachment references inside LocalLightChat `messages_json`

The generated LocalLightChat database also includes the current LocalLightChat schema for features such as archive folders, workspaces, artifacts, MCP sessions, and file-library/RAG metadata. These structures are created for compatibility; they are not populated from unrelated OpenWebUI data unless the converter has an explicit mapping for that data.

The converter intentionally does **not** migrate:

- API keys
- Provider secrets
- OpenWebUI sessions
- Login tokens
- Existing OpenWebUI user passwords
- OAuth credentials
- Hidden backend configuration that may contain secrets

LocalLightChat connections and global settings are created with empty/default API-key fields.

---

## Command overview

```bash
python convert_openwebui_to_locallightchat_v4.py [options] openwebui_db
```

The only required argument is:

```text
openwebui_db
```

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db
```

---

## Positional argument

### `openwebui_db`

Path to the OpenWebUI SQLite database you want to import.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db
```

Example with an absolute Windows path:

```bash
python convert_openwebui_to_locallightchat_v4.py C:\finetune\openwebui\openwebui.db
```

Example with an absolute Linux/macOS path:

```bash
python convert_openwebui_to_locallightchat_v4.py /srv/openwebui/openwebui.db
```

---

## Output options

### `--out`, `-o`

Sets the output LocalLightChat SQLite database path.

Default:

```text
locallightchat_converted.sqlite
```

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --out my_llc.sqlite
```

Windows example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --out C:\finetune\converted\llc.sqlite
```

---

### `--clean`

Forces clean embedded-schema mode.

This is already the default behavior, so this option is mostly useful for explicitness in scripts.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --clean
```

Clean mode means the converter creates a fresh LocalLightChat database from the schema embedded in the converter script. In v4, that embedded schema includes the current LocalLightChat extensions such as archive-folder support, workspaces, artifacts, MCP sessions, and file-library/RAG fields.

---

### `--template TEMPLATE`

Uses an existing LocalLightChat database as a template instead of creating a database from the embedded schema.

The converter copies the template database to the output path and then imports the OpenWebUI data into that copy.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --template locallightchat.sqlite \
  --out converted.sqlite
```

Use this mainly when you want to preserve an installation-specific/customized schema, or when a future LocalLightChat release has moved beyond the schema embedded in this converter. For the LocalLightChat structure targeted by converter v4, a template is not required.

Important: by default, when using `--template`, existing imported/user-owned LocalLightChat data in the copied output database is cleared before import. This includes the standard user/chat/folder/file/template/session data as well as current user-owned areas such as MCP sessions, artifacts, and workspaces. Use `--keep-existing` if you want to preserve existing template data.

---

### `--keep-existing`

Only meaningful together with `--template`.

If this option is not used, the converter wipes existing LocalLightChat import/user data from the copied template before importing OpenWebUI data, including current user-owned tables such as MCP sessions, artifacts, and workspaces.

If this option is used, existing data in the template copy is kept and the imported OpenWebUI data is added to it.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --template locallightchat.sqlite \
  --out merged.sqlite \
  --keep-existing
```

Use this carefully. It is useful for merging into an existing LocalLightChat database, but it can also create duplicate-looking chats or folders if you run the converter more than once.

---

## Admin/user options

### `--admin-user ADMIN_USER`

Sets the LocalLightChat admin username.

Default:

```text
admin
```

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --admin-user stefan
```

Resulting login:

```text
username: stefan
password: admin
```

unless you also change `--admin-password`.

---

### `--admin-password ADMIN_PASSWORD`

Sets the LocalLightChat admin password.

Default:

```text
admin
```

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --admin-password secret123
```

Resulting login:

```text
username: admin
password: secret123
```

---

### `--local-user-id LOCAL_USER_ID`

Sets the internal LocalLightChat user ID for the imported account.

Default:

```text
u_admin
```

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --local-user-id u_stefan
```

Most users do not need to change this. It is mainly useful if you are merging into an existing LocalLightChat database and want to avoid ID collisions.

---

## Branch conversion options

OpenWebUI stores conversations as message trees. A chat can have alternate branches, for example when the user regenerates an assistant answer or continues from a previous point.

LocalLightChat can represent branches differently: as cloned/attached chats.

The converter supports three branch modes.

---

### `--branch-mode active`

Default mode.

Only the active/current OpenWebUI branch is converted into each LocalLightChat chat.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --branch-mode active
```

This is the safest and cleanest mode if you want one LocalLightChat chat per OpenWebUI chat.

---

### `--branch-mode all`

Converts all OpenWebUI messages chronologically into a single LocalLightChat chat.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --branch-mode all
```

This preserves more raw message content, but it can look odd because alternate branches get flattened into one linear conversation.

Use this mostly for forensic/archive-style imports where completeness matters more than conversational shape.

---

### `--branch-mode branched`

Converts OpenWebUI branch paths into separate LocalLightChat cloned chats.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --branch-mode branched
```

In this mode, the main active branch becomes the primary LocalLightChat chat. Alternate OpenWebUI branches become additional LocalLightChat chats with clone metadata in `meta_json`, using the LocalLightChat clone/attached-chat model.

The clone metadata looks conceptually like this:

```json
{
  "clone": {
    "attached": true,
    "parent_id": "...",
    "root_id": "...",
    "created_at": 1710000000000
  }
}
```

This is the preferred mode if you want OpenWebUI branching to feel natural inside LocalLightChat.

---

### `--with-branched`, `--with_branched`

Shortcut for:

```bash
--branch-mode branched
```

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --with-branched
```

The underscore alias also works:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --with_branched
```

---

## Media and upload options

OpenWebUI may store uploaded files outside the SQLite database, usually in an `uploads` folder. The database often contains only paths and metadata.

LocalLightChat can handle media in two ways:

1. Inline inside the database as Base64 `data_url`
2. Stored externally in an `uploads` folder and referenced by URL/file metadata

The converter supports both approaches.

---

### `--uploads-dir UPLOADS_DIR`

Path to the OpenWebUI uploads folder.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --uploads-dir C:\finetune\openwebui\uploads
```

Linux/macOS:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --uploads-dir /srv/openwebui/uploads
```

Use this when images or audio files are missing after conversion. The SQLite database often does not contain the actual file bytes, so the converter needs access to the external files.

---

### `--llc-uploads-dir LLC_UPLOADS_DIR`

Sets the folder where the converter should copy files for LocalLightChat when using upload-based media storage.

Default:

```text
<output_db_directory>/uploads
```

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --media-storage uploads \
  --llc-uploads-dir ./uploads
```

Windows example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db ^
  --media-storage uploads ^
  --llc-uploads-dir C:\finetune\locallightchat\uploads
```

---

### `--llc-upload-url-prefix LLC_UPLOAD_URL_PREFIX`

Sets the URL prefix written into LocalLightChat attachment references when media is stored externally.

Default:

```text
./uploads
```

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --media-storage uploads \
  --llc-upload-url-prefix ./uploads
```

If your LocalLightChat instance expects a different public path, set it here:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --media-storage uploads \
  --llc-upload-url-prefix /uploads
```

The converter writes attachment URLs similar to:

```json
{
  "url": "./uploads/example.png",
  "file_id": "...",
  "stored_only": true
}
```

---

## Media storage modes

### `--media-storage auto|inline|uploads`

Controls the default storage strategy for image and audio attachments.

Default:

```text
auto
```

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --media-storage auto
```

This option applies to both images and audio unless overridden by `--image-storage` or `--audio-storage`.

---

### `--media-storage auto`

Uses LocalLightChat-style size-based behavior.

Small media files are embedded inline. Larger media files are copied to the LocalLightChat uploads folder and referenced from the chat.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir C:\finetune\openwebui\uploads \
  --media-storage auto
```

The default auto limits are:

```text
images: 8 MB
audio: 15 MB
```

---

### `--media-storage inline`

Embeds all image and audio attachments directly into the LocalLightChat database as Base64 data URLs.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir C:\finetune\openwebui\uploads \
  --media-storage inline
```

Inline media looks conceptually like this inside `messages_json`:

```json
{
  "type": "image",
  "name": "example.png",
  "data_url": "data:image/png;base64,..."
}
```

Advantages:

- One single SQLite file contains everything.
- Easier to move around.
- No separate uploads folder required after conversion.

Disadvantages:

- The SQLite database can become very large.
- Large Base64 blobs can make database operations slower.

---

### `--media-storage uploads`

Copies image and audio attachments into a LocalLightChat uploads folder and references them from the database.

Example:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir C:\finetune\openwebui\uploads \
  --media-storage uploads
```

Upload-based media looks conceptually like this inside `messages_json`:

```json
{
  "type": "image",
  "name": "example.png",
  "url": "./uploads/example.png",
  "file_id": "...",
  "stored_only": true
}
```

The converter also creates a matching row in LocalLightChat's `files` table.

Advantages:

- Keeps the SQLite database smaller.
- Better for large media files.
- Matches the behavior of LocalLightChat installations that prefer filesystem-backed uploads.

Disadvantages:

- You must keep the SQLite database and the uploads folder together.
- Moving the database without the uploads folder will break media display.

---

## Image-specific media options

### `--image-storage auto|inline|uploads`

Overrides `--media-storage` for images only.

Example: store images in uploads, but keep the default behavior for audio:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --image-storage uploads
```

Example: always inline images:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir C:\finetune\openwebui\uploads \
  --image-storage inline
```

---

### `--image-inline-limit-mb IMAGE_INLINE_LIMIT_MB`

Sets the maximum image size that will be embedded inline when image storage is `auto`.

Default:

```text
8
```

Example: inline images up to 4 MB, store bigger images in uploads:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --media-storage auto \
  --image-inline-limit-mb 4
```

Example: inline all images in auto mode, regardless of size:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --media-storage auto \
  --image-inline-limit-mb 0
```

`0` means unlimited.

---

## Audio-specific media options

### `--audio-storage auto|inline|uploads`

Overrides `--media-storage` for audio only.

Example: store audio files in uploads, while images follow the default behavior:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --audio-storage uploads
```

Example: inline audio files:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir C:\finetune\openwebui\uploads \
  --audio-storage inline
```

---

### `--audio-inline-limit-mb AUDIO_INLINE_LIMIT_MB`

Sets the maximum audio file size that will be embedded inline when audio storage is `auto`.

Default:

```text
15
```

Example: inline audio up to 5 MB, store bigger audio files in uploads:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --media-storage auto \
  --audio-inline-limit-mb 5
```

Example: inline all audio in auto mode, regardless of size:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --media-storage auto \
  --audio-inline-limit-mb 0
```

`0` means unlimited.

---

## Practical examples

### 1. Minimal conversion

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db
```

Creates a clean LocalLightChat database with the default name:

```text
locallightchat_converted.sqlite
```

---

### 2. Minimal conversion with custom output path

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --out llc.sqlite
```

---

### 3. Convert and preserve OpenWebUI branches as LocalLightChat clones

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --with-branched
```

This is usually the best choice if your OpenWebUI chats contain regenerated answers or alternate paths.

---

### 4. Convert with media files from OpenWebUI uploads

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir /path/to/openwebui/uploads
```

On Windows:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db ^
  --uploads-dir C:\finetune\openwebui\uploads
```

---

### 5. Convert branches and store media in LocalLightChat uploads

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --with-branched \
  --uploads-dir /path/to/openwebui/uploads \
  --media-storage uploads
```

Windows:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db ^
  --with-branched ^
  --uploads-dir C:\finetune\openwebui\uploads ^
  --media-storage uploads
```

---

### 6. Convert branches and embed all media into SQLite

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --with-branched \
  --uploads-dir /path/to/openwebui/uploads \
  --media-storage inline
```

This produces a more portable but potentially much larger SQLite database.

---

### 7. Use LocalLightChat-like automatic media behavior

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir /path/to/openwebui/uploads \
  --media-storage auto \
  --image-inline-limit-mb 8 \
  --audio-inline-limit-mb 15
```

This is also the default behavior, except that explicitly setting `--uploads-dir` makes media conversion more reliable.

---

### 8. Store images in uploads, but inline audio

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir /path/to/openwebui/uploads \
  --image-storage uploads \
  --audio-storage inline
```

---

### 9. Use an existing LocalLightChat database as template

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --template locallightchat.sqlite \
  --out converted.sqlite
```

Good when your LocalLightChat database schema has changed and you want to preserve that exact schema.

---

### 10. Merge into a copied template without deleting existing data

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --template locallightchat.sqlite \
  --out merged.sqlite \
  --keep-existing
```

Use carefully. This can create duplicates if you run it repeatedly.

---

## Expected output

A successful run prints a summary similar to:

```text
Done. Wrote locallightchat_converted.sqlite
Mode: clean
Admin login: admin/admin
Converted: 2 folders, 3 files, 5 chats
```

With branched conversion, you may see a higher chat count because OpenWebUI branches become separate LocalLightChat cloned chats:

```text
Done. Wrote locallightchat_converted.sqlite
Mode: clean
Admin login: admin/admin
Converted: 2 folders, 3 files, 7 chats
```

If media files are missing, the converter may print warnings. This usually means OpenWebUI stored only a path in SQLite and the original file was not found on disk.

---

## Notes about images and audio

OpenWebUI often stores uploaded images/audio files outside the database. The SQLite database may contain only metadata such as:

```text
filename: h200.png
path: C:\finetune\openwebui\uploads\some-id_h200.png
```

In that case, the converter needs access to the original uploads folder.

If the file exists, the converter can either:

- embed it into `messages_json` as a Base64 `data_url`, or
- copy it into the LocalLightChat uploads folder and reference it by URL and `file_id`.

If the file does not exist, the converter cannot reconstruct the binary file from the SQLite database alone.

---

## Notes about API keys and secrets

The converter intentionally does not migrate API keys or secrets.

In clean mode, generated LocalLightChat settings use empty values for keys such as:

```text
OpenAI API key
OpenRouter API key
Search provider API keys
Image provider API keys
Voice provider API keys
```

This is deliberate. Migration should not silently copy secrets from one application context into another.

If you use `--template --keep-existing`, existing API keys already present in the LocalLightChat template database may remain there, because you explicitly asked the converter to preserve existing data.

---

## Troubleshooting

### The script still asks for three positional arguments

You are running an old version of the converter.

The current version requires only one positional argument:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db
```

If your help output still shows this:

```text
openwebui_db locallightchat_template output_db
```

replace the old script with the current `convert_openwebui_to_locallightchat_v4.py`.

---

### Images are missing after conversion

Most likely the converter could not find the original OpenWebUI upload files.

Run with `--uploads-dir`:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir /path/to/openwebui/uploads
```

Windows:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db ^
  --uploads-dir C:\finetune\openwebui\uploads
```

Also check whether the files still exist in the OpenWebUI uploads folder.

---

### The SQLite file is very large

You probably used inline media storage, or auto mode inlined many files.

Use upload-backed media storage:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir /path/to/openwebui/uploads \
  --media-storage uploads
```

---

### Branches look flattened

You probably used:

```bash
--branch-mode all
```

Use LocalLightChat clone-style branch conversion instead:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db --with-branched
```

---

### I want one single file without an uploads folder

Use inline media storage:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir /path/to/openwebui/uploads \
  --media-storage inline
```

This embeds media directly in the SQLite database.

---

### I want a small database and separate media files

Use upload-backed media storage:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --uploads-dir /path/to/openwebui/uploads \
  --media-storage uploads
```

Keep the generated SQLite database and the generated uploads folder together.

---

## Full option reference

```text
openwebui_db
    Required. Path to the OpenWebUI SQLite database.

--out, -o
    Output LocalLightChat SQLite database path.

--template
    Optional LocalLightChat database to copy and use as schema/template.

--clean
    Force clean embedded-schema mode. This is already the default.

--admin-user
    LocalLightChat admin username. Default: admin.

--admin-password
    LocalLightChat admin password. Default: admin.

--local-user-id
    Internal LocalLightChat user ID. Default: u_admin.

--branch-mode active|all|branched
    active: only the current OpenWebUI branch.
    all: flatten all messages chronologically.
    branched: create LocalLightChat cloned chats for branches.

--with-branched, --with_branched
    Shortcut for --branch-mode branched.

--keep-existing
    Only meaningful with --template. Preserve existing data in the copied template.

--uploads-dir
    Path to the OpenWebUI uploads folder.

--llc-uploads-dir
    Destination folder for LocalLightChat copied uploads.

--llc-upload-url-prefix
    URL prefix stored in LocalLightChat attachment references. Default: ./uploads.

--media-storage auto|inline|uploads
    Default image/audio storage strategy. Default: auto.

--image-storage auto|inline|uploads
    Override storage strategy for images.

--audio-storage auto|inline|uploads
    Override storage strategy for audio.

--image-inline-limit-mb
    Auto-mode inline limit for images in MB. Default: 8. 0 means unlimited.

--audio-inline-limit-mb
    Auto-mode inline limit for audio in MB. Default: 15. 0 means unlimited.
```

---

## Suggested default command

For most real migrations, use:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db \
  --with-branched \
  --uploads-dir /path/to/openwebui/uploads \
  --media-storage auto
```

Windows:

```bash
python convert_openwebui_to_locallightchat_v4.py openwebui.db ^
  --with-branched ^
  --uploads-dir C:\finetune\openwebui\uploads ^
  --media-storage auto
```

This gives you:

- a clean LocalLightChat database,
- LocalLightChat-style cloned chats for OpenWebUI branches,
- reasonable media handling,
- no copied API keys or secrets,
- and an admin login of `admin / admin` unless changed explicitly.
