#!/bin/sh
set -eu

mkdir -p \
  /run/nginx \
  /var/lib/locallightchat/data \
  /var/lib/locallightchat/uploads \
  /var/lib/locallightchat/tmp

# Some code paths still resolve __DIR__ . '/uploads/...'. Keep that path working
# without storing upload data inside the image/webroot.
ln -sfn /var/lib/locallightchat/uploads /var/www/html/uploads

chown -R www-data:www-data /var/lib/locallightchat || true

php-fpm -D
exec nginx -g 'daemon off;'
