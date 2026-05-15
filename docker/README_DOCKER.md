# LocalLightChat Docker

Dieses Docker-Setup startet LocalLightChat in **einem Container** mit:

- nginx
- php-fpm
- persistenten Docker-Volumes für `data`, `uploads` und `tmp`
- HTTP und HTTPS
- dem mitgelieferten self-signed Zertifikat

## Start

```bash
docker compose up --build
```

Standard-URLs:

```text
http://127.0.0.1:8181/
https://127.0.0.1:8182/
```

Beim HTTPS-Aufruf meckert der Browser, weil das Zertifikat self-signed ist. Das ist erwartbar.

## Konfiguration über `.env`

Die Ports und Bind-Adressen werden über `LLC_*` Variablen gesetzt.

Mitgeliefert sind:

```text
.env
.env.example
```

Default ist absichtlich **nur lokal erreichbar**:

```env
LLC_HTTP_BIND=127.0.0.1
LLC_HTTP_PORT=8181

LLC_HTTPS_BIND=127.0.0.1
LLC_HTTPS_PORT=8182
```

Damit geht der Zugriff nur auf derselben Maschine:

```text
http://127.0.0.1:8181/
https://127.0.0.1:8182/
```

## Zugriff aus dem LAN

Wenn LocalLightChat im lokalen Netzwerk erreichbar sein soll, ändere `.env` z. B. so:

```env
LLC_HTTP_BIND=0.0.0.0
LLC_HTTP_PORT=8181

LLC_HTTPS_BIND=0.0.0.0
LLC_HTTPS_PORT=8182
```

Danach neu starten:

```bash
docker compose down
docker compose up --build
```

Dann ist der Dienst über die LAN-IP des Hosts erreichbar, z. B.:

```text
http://192.168.0.2:8181/
https://192.168.0.2:8182/
```

Alternativ kannst du statt `0.0.0.0` direkt eine konkrete LAN-IP binden:

```env
LLC_HTTP_BIND=192.168.0.2
LLC_HTTP_PORT=8181

LLC_HTTPS_BIND=192.168.0.2
LLC_HTTPS_PORT=8182
```

## Bedeutung der Port-Syntax

In `docker-compose.yml` steht:

```yaml
ports:
  - "${LLC_HTTP_BIND:-127.0.0.1}:${LLC_HTTP_PORT:-8181}:80"
  - "${LLC_HTTPS_BIND:-127.0.0.1}:${LLC_HTTPS_PORT:-8182}:443"
```

Das bedeutet:

```text
Host-IP:Host-Port:Container-Port
```

Beispiele:

```text
127.0.0.1:8181:80   = HTTP nur lokal
0.0.0.0:8181:80     = HTTP auf allen Interfaces, also auch LAN
192.168.0.2:8181:80 = HTTP nur auf dieser LAN-IP
```

Im Container hört nginx immer auf `80` und `443`. Ob der Dienst lokal oder im LAN sichtbar ist, entscheidet das Docker-Port-Binding.

## HTTPS-Zertifikat

Die mitgelieferten self-signed Dateien liegen hier:

```text
certs/nginx-selfsigned.crt
certs/nginx-selfsigned.key
```

Sie werden read-only in den Container gemountet:

```yaml
- ./certs:/etc/nginx/certs:ro
```

nginx nutzt dann:

```text
/etc/nginx/certs/nginx-selfsigned.crt
/etc/nginx/certs/nginx-selfsigned.key
```

Wenn du eigene Zertifikate verwenden willst, ersetze diese beiden Dateien oder passe `docker/nginx.conf` an.

## Persistente Daten

App-Daten liegen nicht im Webroot, sondern in Docker-Volumes:

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

`/uploads/...` wird von nginx gezielt ausgeliefert, aber die Dateien liegen physisch außerhalb von `/var/www/html`.

## Nützliche Checks

Laufende Container:

```bash
docker ps
```

Ports prüfen:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

nginx-Konfiguration und Webroot im Container prüfen:

```bash
docker exec locallightchat sh -lc 'nginx -T | sed -n "1,260p"; echo ---; ls -la /var/www/html'
```

Logs:

```bash
docker logs -f locallightchat
```

Sauber neu bauen:

```bash
docker compose down
docker compose build --no-cache
docker compose up
```
