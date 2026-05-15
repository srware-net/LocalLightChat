FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
      nginx \
      curl \
      libzip \
      sqlite-libs \
    && apk add --no-cache --virtual .build-deps \
      $PHPIZE_DEPS \
      libzip-dev \
    && docker-php-ext-install -j"$(nproc)" \
      zip \
    && apk del .build-deps

WORKDIR /var/www/html

COPY public/ /var/www/html/
COPY docker/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/php-overrides.ini /usr/local/etc/php/conf.d/99-overrides.ini
COPY docker/entrypoint.sh /entrypoint.sh
COPY certs/ /etc/nginx/certs/

RUN mkdir -p /run/nginx \
      /var/lib/locallightchat/data \
      /var/lib/locallightchat/uploads \
      /var/lib/locallightchat/tmp \
    && ln -sfn /var/lib/locallightchat/uploads /var/www/html/uploads \
    && chmod +x /entrypoint.sh \
    && chown -R www-data:www-data /var/lib/locallightchat

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
