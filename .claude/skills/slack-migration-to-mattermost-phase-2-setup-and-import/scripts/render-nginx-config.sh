#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <domain> [upstream=127.0.0.1:8065] [cert=/etc/nginx/ssl/origin.pem] [key=/etc/nginx/ssl/origin-key.pem] [body=50M]" >&2
  exit 1
fi

domain="$1"
upstream="${2:-127.0.0.1:8065}"
cert="${3-}"
key="${4-}"
body="${5:-50M}"

render_proxy_locations() {
cat <<EOF
    location ~ /api/v[0-9]+/(users/)?websocket$ {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 600s;
        proxy_pass http://mattermost;
    }

    location / {
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Frame-Options SAMEORIGIN;
        client_max_body_size ${body};
        proxy_read_timeout 600s;
        proxy_pass http://mattermost;
    }
EOF
}

if [[ -n "${cert}" && -n "${key}" ]]; then
cat <<EOF
upstream mattermost {
    server ${upstream};
    keepalive 32;
}

server {
    listen 443 ssl;
    http2 on;
    server_name ${domain};

    ssl_certificate     ${cert};
    ssl_certificate_key ${key};
$(render_proxy_locations)
}

server {
    listen 80;
    server_name ${domain};
    return 301 https://\$server_name\$request_uri;
}
EOF
else
cat <<EOF
upstream mattermost {
    server ${upstream};
    keepalive 32;
}

server {
    listen 80;
    server_name ${domain};
$(render_proxy_locations)
}
EOF
fi
