#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限或 sudo 运行此脚本。"
  exit 1
fi

echo "--- 开始系统检查与 Nginx 配置 ---"

# 1. 检查并安装 Nginx
if ! command -v nginx &> /dev/null; then
    echo "未检测到 Nginx，正在开始安装..."
    apt update
    apt install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "Nginx 安装完成。"
else
    echo "检测到 Nginx 已安装，跳过安装步骤。"
fi

# 2. 获取用户输入
read -p "请输入您要监听的端口 (默认 80): " PORT
PORT=${PORT:-80}

read -p "请输入您的域名 (例如 example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "域名不能为空，退出脚本。"
    exit 1
fi

read -p "请输入后端代理地址 (例如 http://127.0.0.1:8080): " PROXY_PASS
if [ -z "$PROXY_PASS" ]; then
    echo "后端地址不能为空，退出脚本。"
    exit 1
fi

# 3. 创建 Nginx 配置文件
CONF_PATH="/etc/nginx/sites-available/$DOMAIN"

echo "正在生成配置文件..."
cat <<EOF > $CONF_PATH
server {
    listen $PORT;
    server_name $DOMAIN;

    location / {
        proxy_pass $PROXY_PASS;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 启用配置并检查语法
ln -sf $CONF_PATH /etc/nginx/sites-enabled/
nginx -t
if [ $? -eq 0 ]; then
    systemctl reload nginx
    echo "Nginx 基础配置已生效。"
else
    echo "Nginx 配置语法错误，请检查。"
    exit 1
fi

# 4. 申请 HTTPS 证书 (Certbot)
echo "--- 准备申请 HTTPS 证书 ---"
if ! command -v certbot &> /dev/null; then
    echo "正在安装 Certbot..."
    apt install -y certbot python3-certbot-nginx
fi

echo "正在为 $DOMAIN 申请证书（需确保域名已解析并开启 80 端口）..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email

if [ $? -eq 0 ]; then
    echo "------------------------------------------------"
    echo "恭喜！配置完成。"
    echo "访问地址: https://$DOMAIN"
    echo "------------------------------------------------"
else
    echo "HTTPS 证书申请失败，请检查域名解析或网络连通性。"
fi
