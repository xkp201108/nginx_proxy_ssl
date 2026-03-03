#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 权限运行：sudo $0"
  exit 1
fi

# 1. 检查并安装 Nginx 和 Certbot
install_pkg() {
    if ! command -v $1 &> /dev/null; then
        echo "正在安装 $1..."
        apt update && apt install -y $1
    fi
}

install_pkg nginx
install_pkg certbot
install_pkg python3-certbot-nginx

# 2. 获取用户输入
read -p "请输入域名 (例如 19960000.xyz): " DOMAIN
read -p "请输入后端代理地址 (例如 http://127.0.0.1:8080): " PROXY_PASS
read -p "请输入监听端口 (默认 80): " PORT
PORT=${PORT:-80}

CONF_PATH="/etc/nginx/sites-available/$DOMAIN"
LINK_PATH="/etc/nginx/sites-enabled/$DOMAIN"

# 3. 第一步：创建一个临时的 HTTP 配置用于 Certbot 验证
echo "正在创建临时验证配置..."
cat <<EOF > $CONF_PATH
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        root /var/www/html;
    }
}
EOF

ln -sf $CONF_PATH $LINK_PATH
systemctl reload nginx

# 4. 第二步：申请证书
echo "正在为 $DOMAIN 申请证书..."
certbot certonly --nginx -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email

if [ $? -ne 0 ]; then
    echo "❌ 证书申请失败！请检查域名 A 记录是否已指向此 IP，且 80 端口已开放。"
    exit 1
fi

# 5. 第三步：证书申请成功，写入最终的生产环境配置
echo "证书申请成功，正在配置 HTTPS 反向代理..."
cat <<EOF > $CONF_PATH
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

    # 安全优化
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass $PROXY_PASS;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 检查语法并重启
nginx -t
if [ $? -eq 0 ]; then
    systemctl restart nginx
    echo "------------------------------------------------"
    echo "✅ 恭喜！站点已成功配置。"
    echo "🌍 访问地址: https://$DOMAIN"
    echo "📂 配置文件: $CONF_PATH"
    echo "------------------------------------------------"
else
    echo "❌ Nginx 配置语法错误，请检查 $CONF_PATH"
fi
