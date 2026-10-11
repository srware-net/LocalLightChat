FROM php:8.3-fpm-bookworm

ARG TARGETARCH

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      gosu \
      libstdc++6 \
      libzip4 \
      libzip-dev \
      nginx \
      tini; \
    docker-php-ext-install -j"$(nproc)" zip; \
    apt-get purge -y --auto-remove libzip-dev; \
    rm -f /etc/nginx/sites-enabled/default; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

COPY public/ /var/www/html/
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY docker/php-overrides.ini /usr/local/etc/php/conf.d/99-overrides.ini
COPY docker/php-fpm-pool.conf /usr/local/etc/php-fpm.d/zz-locallightchat.conf
COPY docker/entrypoint.sh /entrypoint.sh
COPY certs/ /etc/nginx/certs/
COPY config/ /config/
COPY native/ /tmp/llc-native/

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) expected_machine='3e00' ;; \
      arm64) expected_machine='b700' ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    src="/tmp/llc-native/$TARGETARCH"; \
    for binary in ragd mcp_server; do \
      file="$src/$binary"; \
      if [ ! -f "$file" ]; then \
        echo "Missing $TARGETARCH binary: native/$TARGETARCH/$binary" >&2; \
        echo "For arm64 replace the supplied *.binary.txt placeholders with the real executables." >&2; \
        exit 1; \
      fi; \
      magic="$(od -An -tx1 -N4 "$file" | tr -d ' \n')"; \
      machine="$(od -An -tx1 -j18 -N2 "$file" | tr -d ' \n')"; \
      if [ "$magic" != '7f454c46' ]; then \
        echo "native/$TARGETARCH/$binary is not an ELF executable" >&2; \
        exit 1; \
      fi; \
      if [ "$machine" != "$expected_machine" ]; then \
        echo "Wrong architecture for native/$TARGETARCH/$binary (ELF e_machine=$machine)" >&2; \
        exit 1; \
      fi; \
    done; \
    install -d /opt/locallightchat/rag /opt/locallightchat/mcp; \
    install -m 0755 "$src/ragd" /opt/locallightchat/rag/ragd; \
    install -m 0755 "$src/mcp_server" /opt/locallightchat/mcp/mcp_server; \
    rm -rf /tmp/llc-native; \
    mkdir -p \
      /run/nginx \
      /var/lib/locallightchat/data/rag \
      /var/lib/locallightchat/data/mcp \
      /var/lib/locallightchat/data/artifacts \
      /var/lib/locallightchat/uploads \
      /var/lib/locallightchat/workspaces \
      /var/lib/locallightchat/tmp; \
    chmod 0755 /entrypoint.sh; \
    chown -R www-data:www-data /var/lib/locallightchat

EXPOSE 80 443

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
