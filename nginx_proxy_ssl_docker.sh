#!/bin/bash

# 1. 权限检查
[[ $EUID -ne 0 ]] && echo "❌ 请使用 root 权限运行" && exit 1

# 2. 检测并安装 Docker & Docker Compose
echo "🔍 正在检查 Docker 环境..."
if ! command -v docker &> /dev/null; then
    echo "🐳 未检测到 Docker，正在安装官方版本..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker
else
    echo "👌 Docker 已安装"
fi

if ! docker compose version &> /dev/null; then
    echo "📦 正在安装 Docker Compose 插件..."
    if command -v apt &> /dev/null; then
        apt update && apt install -y docker-compose-plugin
    else
        yum install -y docker-compose-plugin
    fi
fi

# 3. 获取用户配置
echo "------------------------------------------------"
read -p "🌐 请输入完整域名 (如 abc.abc.com): " DOMAIN
if [[ ! "$DOMAIN" =~ \. ]]; then echo "❌ 域名格式错误"; exit 1; fi

read -p "🔌 宿主机后端端口 (你程序运行的端口，如 8080): " APP_PORT
APP_PORT=${APP_PORT:-8080}
echo "------------------------------------------------"

# 4. 准备 Docker 工作目录
WORK_DIR="/opt/docker-proxy-$DOMAIN"
mkdir -p $WORK_DIR/nginx
cd $WORK_DIR

# 5. 使用容器申请 SSL 证书 (Standalone 模式)
echo "🔑 正在通过 Certbot 容器申请证书..."
# 确保宿主机 80 端口没被占用
docker stop $(docker ps -q --filter "publish=80") 2>/dev/null

docker run --rm -it --name certbot-helper \
    -p 80:80 \
    -v "/etc/letsencrypt:/etc/letsencrypt" \
    certbot/certbot certonly --standalone \
    -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "❌ 证书申请失败。请检查：1. 域名 A 记录 2. 防火墙 80 端口是否放行。"
    exit 1
fi

# 6. 生成容器内使用的 Nginx 配置文件
cat <<EOF > ./nginx/default.conf
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
        # host.docker.internal 允许容器访问宿主机上的服务
        proxy_pass http://host.docker.internal:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 7. 生成 Docker Compose 编排文件
cat <<EOF > docker-compose.yml
services:
  nginx-proxy:
    image: nginx:alpine
    container_name: proxy-${DOMAIN//./-}
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx:/etc/nginx/conf.d:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    extra_hosts:
      - "host.docker.internal:host-gateway"
EOF

# 8. 启动代理
echo "🚢 正在启动 Docker 代理服务..."
docker compose up -d

echo "------------------------------------------------"
echo "✅ 部署完成！"
echo "📂 项目配置目录: $WORK_DIR"
echo "🌍 访问地址: https://$DOMAIN"
echo "🔗 代理目标: 宿主机端口 $APP_PORT"
echo "------------------------------------------------"
