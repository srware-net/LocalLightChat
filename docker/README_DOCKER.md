# LocalLightChat Docker

This Docker setup starts LocalLightChat in **a single container** with:

- nginx
- php-fpm
- persistent Docker volumes for `data`, `uploads`, and `tmp`
- HTTP and HTTPS
- the included self-signed certificate

## Start

```bash
docker compose up --build
```

Default URLs:

```text
http://127.0.0.1:8181/
https://127.0.0.1:8182/
```

When opening the HTTPS URL, the browser will complain because the certificate is self-signed. This is expected.

## Configuration via `.env`

Ports and bind addresses are set via `LLC_*` variables.

Included files:

```text
.env
.env.example
```

By default, access is intentionally **local only**:

```env
LLC_HTTP_BIND=127.0.0.1
LLC_HTTP_PORT=8181

LLC_HTTPS_BIND=127.0.0.1
LLC_HTTPS_PORT=8182
```

This means access only works from the same machine:

```text
http://127.0.0.1:8181/
https://127.0.0.1:8182/
```

## Access from the LAN

If LocalLightChat should be reachable from the local network, change `.env`, for example, like this:

```env
LLC_HTTP_BIND=0.0.0.0
LLC_HTTP_PORT=8181

LLC_HTTPS_BIND=0.0.0.0
LLC_HTTPS_PORT=8182
```

Then restart:

```bash
docker compose down
docker compose up --build
```

The service will then be reachable via the host's LAN IP, for example:

```text
http://192.168.0.2:8181/
https://192.168.0.2:8182/
```

Alternatively, instead of `0.0.0.0`, you can bind directly to a specific LAN IP:

```env
LLC_HTTP_BIND=192.168.0.2
LLC_HTTP_PORT=8181

LLC_HTTPS_BIND=192.168.0.2
LLC_HTTPS_PORT=8182
```

## Meaning of the Port Syntax

In `docker-compose.yml`:

```yaml
ports:
  - "${LLC_HTTP_BIND:-127.0.0.1}:${LLC_HTTP_PORT:-8181}:80"
  - "${LLC_HTTPS_BIND:-127.0.0.1}:${LLC_HTTPS_PORT:-8182}:443"
```

This means:

```text
Host-IP:Host-Port:Container-Port
```

Examples:

```text
127.0.0.1:8181:80   = HTTP local only
0.0.0.0:8181:80     = HTTP on all interfaces, including LAN
192.168.0.2:8181:80 = HTTP only on this LAN IP
```

Inside the container, nginx always listens on `80` and `443`. Whether the service is visible locally only or also on the LAN is determined by the Docker port binding.

## HTTPS Certificate

The included self-signed files are located here:

```text
certs/nginx-selfsigned.crt
certs/nginx-selfsigned.key
```

They are mounted read-only into the container:

```yaml
- ./certs:/etc/nginx/certs:ro
```

nginx then uses:

```text
/etc/nginx/certs/nginx-selfsigned.crt
/etc/nginx/certs/nginx-selfsigned.key
```

If you want to use your own certificates, replace these two files or adjust `docker/nginx.conf`.

## Persistent Data

Application data is not stored in the webroot, but in Docker volumes:

```text
/var/lib/locallightchat/data
/var/lib/locallightchat/uploads
/var/lib/locallightchat/tmp
```

In Compose:

```yaml
volumes:
  - locallightchat_data:/var/lib/locallightchat/data
  - locallightchat_uploads:/var/lib/locallightchat/uploads
  - locallightchat_tmp:/var/lib/locallightchat/tmp
```

`/uploads/...` is deliberately served by nginx, but the files are physically located outside `/var/www/html`.

## Useful Checks

Running containers:

```bash
docker ps
```

Check ports:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Check nginx configuration and webroot inside the container:

```bash
docker exec locallightchat sh -lc 'nginx -T | sed -n "1,260p"; echo ---; ls -la /var/www/html'
```

Logs:

```bash
docker logs -f locallightchat
```

Clean rebuild:

```bash
docker compose down
docker compose build --no-cache
docker compose up
```
