#!/bin/bash
# listen_local_or_network.sh

cd "$(dirname "$0")"

echo "========================================"
echo "   NGINX Network Configuration"
echo "========================================"
echo
echo "Select listening mode:"
echo
echo "[1] Local only (127.0.0.1) - accessible from this machine only"
echo "[2] Network access (0.0.0.0) - accessible from other devices"
echo
read -p "Enter your choice (1 or 2): " choice

case $choice in
    1)
        # Local only - beide Ports
        sed -i 's/^\s*listen\s\+\(0\.0\.0\.0:\|127\.0\.0\.1:\)\?[0-9]\+\(\s\+ssl\)\?;/        listen       127.0.0.1:8081;/' nginx/conf/nginx.conf
        sed -i 's/^\s*listen\s\+\(0\.0\.0\.0:\|127\.0\.0\.1:\)\?[0-9]\+\s\+ssl;/        listen       127.0.0.1:8082 ssl;/' nginx/conf/nginx.conf
        
        echo
        echo "Configuration updated: Local access only"
        echo "  - HTTP:  127.0.0.1:8081"
        echo "  - HTTPS: 127.0.0.1:8082"
        ;;
    2)
        # Network access - beide Ports
        sed -i '/listen.*8081/s/^\s*listen\s\+\(0\.0\.0\.0:\|127\.0\.0\.1:\)\?[0-9]\+;/        listen       0.0.0.0:8081;/' nginx/conf/nginx.conf
        sed -i '/listen.*8082/s/^\s*listen\s\+\(0\.0\.0\.0:\|127\.0\.0\.1:\)\?[0-9]\+\s\+ssl;/        listen       0.0.0.0:8082 ssl;/' nginx/conf/nginx.conf
        
        echo
        echo "Configuration updated: Network access enabled"
        echo "  - HTTP:  0.0.0.0:8081"
        echo "  - HTTPS: 0.0.0.0:8082"
        ;;
    *)
        echo
        echo "Invalid choice. Configuration unchanged."
        exit 1
        ;;
esac

echo
read -p "Press Enter to exit..."
