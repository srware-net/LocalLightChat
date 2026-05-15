# LocalLightChat

**Portable. Fast. Yours.**

The ultimate chat UI for Local AI and Cloud APIs.

- Cold start: `<1s`
- Context: `500k+` tokens
- Download size: `<60MB`
- Portable: `100%`

Website: https://www.locallightai.com/llc/

## Features

- Folder structure and chat management
- Fulltext search across unlimited chat history
- Compress & Clone: compress large chats while preserving decision-critical context
- Documents and editable artifacts
- Efficient web search and fetch tools
- Image generation via API or ComfyUI bindings
- Voice transcription and text-to-speech
- Attachments: PDF, images, CSV, YAML, XML, logs and more
- URL sources and text notes
- Markdown, Mermaid, Math/TeX and code rendering
- Templates, auto-rename, clone/compress, import/export
- Advanced LLM parameters: temperature, sampling, DRY, Mirostat
- Connection management and telemetry
- Role-based user system: superadmin, admin and user

## Download

Ready-to-use portable packages:

| Platform | Download |
|---|---|
| Windows x64 | [Windows x64](https://www.locallightai.com/llc/downloads/llc_windows_x64.zip) |
| Linux x64 | [Linux x64](https://www.locallightai.com/llc/downloads/llc-linux_x64.tar.gz) |
| Linux ARM64 | [Linux ARM64](https://www.locallightai.com/llc/downloads/llc-linux-arm64.tar.gz) |
| macOS | [macOS](https://www.locallightai.com/llc/downloads/llc-macos.zip) |

Current version: **0.5**

## Docker

Docker image:

```text
srwarenet/locallightchat:latest
```

Docker Hub:

https://hub.docker.com/r/srwarenet/locallightchat

Run locally:

```bash
docker run -d \
  --name locallightchat \
  -p 127.0.0.1:8080:80 \
  srwarenet/locallightchat:latest
```

Open:

```text
http://127.0.0.1:8080
```

Stop:

```bash
docker stop locallightchat
docker rm locallightchat
```

## Docker Compose

Using the included Docker setup:

```bash
cd docker
docker compose up -d --build
```

Stop:

```bash
docker compose down
```

## Self-Hosted

Use this if you want to deploy LocalLightChat on your own nginx/PHP stack.

Requires:

- nginx or similar
- PHP 8.x
- SQLite

Upload the contents of:

```text
www/
```

to your web server document root, for example:

```text
htdocs/
public_html/
www/
```

Usually you should upload the contents of `www/`, not the folder itself.

## Project Structure

```text
LocalLightChat/
├─ www/
├─ docker/
├─ packages/
├─ LICENSE
└─ README.md
```

## License

See `LICENSE`.
