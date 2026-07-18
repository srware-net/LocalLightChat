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
https://github.com/srware-net/LocalLightChat/releases

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
  -p 127.0.0.1:8181:80 \
  -p 127.0.0.1:8182:443 \
  -v locallightchat:/var/lib/locallightchat \
  --restart unless-stopped \
  srwarenet/locallightchat:latest
```

Open:

```text
http://127.0.0.1:8181
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
├─ converter/
├─ LICENSE
└─ README.md
```

## License

See `LICENSE`.
