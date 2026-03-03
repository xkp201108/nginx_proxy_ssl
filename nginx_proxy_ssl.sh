#!/bin/bash

# 1. 环境初始化
[[ $EUID -ne 0 ]] && echo "❌ 请使用 root 权限" && exit 1

# 2. 用户输入
read -p "🌐 请输入完整域名 (如 test.928287764.xyz): " DOMAIN
if [[ ! "$DOMAIN" =~ \. ]]; then echo "❌ 域名格式错误"; exit 1; fi

read -p "🔌 代理地址 (默认 http://127.0.0.1:8080): " PROXY_PASS
PROXY_PASS=${PROXY_PASS:-http://127.0.0.1:8080}

# --- 3. 强力清理阶段 (解决你目前的报错) ---
echo "🧹 正在深度清理 Nginx 僵尸配置..."
# 删除断开的软链接
find /etc/nginx/sites-enabled/ -xtype l -delete
# 删除所有包含该域名的配置文件（无论在哪个目录）
find /etc/nginx/ -name "*$DOMAIN*" -delete
# 再次清理可能残留的链接
rm -f /etc/nginx/sites-enabled/$DOMAIN
rm -f /etc/nginx/conf.d/$DOMAIN.conf

# 强制重启 Nginx 验证干净状态
systemctl restart nginx
if ! nginx -t; then
    echo "❌ Nginx 仍有其他全局错误，请手动检查 /etc/nginx/nginx.conf"
    exit 1
fi

# --- 4. 影子验证与证书申请 ---
echo "🔑 正在申请证书..."
mkdir -p /var/www/html
cat <<EOF > /etc/nginx/conf.d/$DOMAIN.conf
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/html; }
}
EOF
systemctl reload nginx

certbot certonly --webroot -w /var/www/html -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

# --- 5. 部署 HTTPS ---
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    cat <<EOF > /etc/nginx/conf.d/$DOMAIN.conf
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    location / {
        proxy_pass $PROXY_PASS;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    nginx -t && systemctl restart nginx
    echo "✅ 成功！https://$DOMAIN 已就绪。"
else
    echo "❌ 证书申请失败，请检查 80 端口和域名解析。"
fi
