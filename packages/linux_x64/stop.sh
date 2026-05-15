#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"
echo "Stopping LocalLightChat..."

# PHP-FPM
if [ -f "php/php-fpm.pid" ]; then
    kill $(cat php/php-fpm.pid) 2>/dev/null
    rm -f php/php-fpm.pid
fi

# Nginx graceful shutdown
if [ -f "nginx/nginx.pid" ]; then
    nginx -s quit -p "$DIR/nginx" -c nginx.conf 2>/dev/null
    rm -f nginx/nginx.pid
fi

# Fallback cleanup
pkill -f "php-fpm.*master" 2>/dev/null
pkill -f "nginx.*nginx" 2>/dev/null

rm -f php/php-fpm.conf

echo "✓ Stopped PHP-FPM"
echo "✓ Stopped Nginx"
echo "Stopped."
