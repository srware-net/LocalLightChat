	#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

mkdir -p nginx/logs php/logs

CURRENT_USER=$(whoami)
CURRENT_GROUP=$(id -gn)

cat > php/php-fpm.conf << EOFPHP
[global]
pid = $DIR/php/php-fpm.pid
error_log = $DIR/php/logs/error.log
daemonize = yes

[www]
user = $CURRENT_USER
group = $CURRENT_GROUP
listen = 127.0.0.1:9002
pm = dynamic
pm.max_children = 15
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
catch_workers_output = yes

request_terminate_timeout = 999s

php_admin_value[memory_limit] = 1024M
php_admin_value[max_execution_time] = 999
php_admin_value[max_input_time] = 999
php_admin_value[post_max_size] = 200M
php_admin_value[upload_max_filesize] = 200M
php_admin_value[max_file_uploads] = 20
php_admin_value[default_socket_timeout] = 999

env[PATH] = /usr/local/bin:/usr/bin:/bin
EOFPHP

pkill -9 -f "php-fpm" 2>/dev/null || true
pkill -9 -f "nginx" 2>/dev/null || true
sleep 1

./php/php-fpm -y ./php/php-fpm.conf 2>> ./php/logs/error_log --prefix $(pwd)/php
./nginx/nginx -p $(pwd)/nginx -c $(pwd)/nginx/conf/nginx.conf


# Warte bis PHP-FPM tatsächlich antwortet
for i in $(seq 1 30); do
    if nc -z 127.0.0.1 9002 2>/dev/null; then
        break
    fi
    sleep 0.1
done

# Zusätzlich: Warte bis nginx HTTP liefert
for i in $(seq 1 30); do
    if curl -s http://127.0.0.1:8081 > /dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

echo "✓ Running on http://localhost:8081"
echo "✓ Running on https://localhost:8082"
echo "";
echo "Press F5 to see chats on first launch".

#if command -v xdg-open > /dev/null; then
#    xdg-open https://127.0.0.1:8082 2>/dev/null &
#fi
