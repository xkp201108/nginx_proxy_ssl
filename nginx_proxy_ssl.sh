#!/bin/bash
set -e

#==============================
# 一键脚本：Nginx + 反向代理 + HTTPS
# 适配：Ubuntu/Debian/CentOS/Rocky
#==============================

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

info() { echo -e "${GREEN}[INFO] $*${RESET}"; }
warn() { echo -e "${YELLOW}[WARN] $*${RESET}"; }
err() { echo -e "${RED}[ERROR] $*${RESET}"; exit 1; }

# 检查 root
[ "$(id -u)" -ne 0 ] && err "请使用 root 运行"

# 识别系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    err "无法识别系统"
fi

# 安装依赖
install() {
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt update -y
        apt install -y "$@"
    elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "rhel" ]]; then
        yum install -y "$@"
    fi
}

# 安装 Nginx
if ! command -v nginx &>/dev/null; then
    info "安装 Nginx..."
    install nginx
    systemctl enable --now nginx
else
    info "Nginx 已安装"
fi

# 安装 certbot
if ! command -v certbot &>/dev/null; then
    info "安装 Certbot..."
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        install certbot python3-certbot-nginx
    else
        install certbot python3-certbot-nginx
    fi
fi

# 输入参数
read -p "请输入域名 (例如: abc.com): " DOMAIN
[ -z "$DOMAIN" ] && err "域名不能为空"

read -p "请输入代理目标 (例如 http://127.0.0.1:8080): " PROXY
[ -z "$PROXY" ] && err "代理目标不能为空"

read -p "请输入对外监听端口 [默认 80]: " PORT
PORT=${PORT:-80}

# 配置文件
CONF="/etc/nginx/conf.d/${DOMAIN}.conf"

cat > "$CONF" << EOF
server {
    listen 80;
    server_name $DOMAIN;
    # 强制跳转 HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass $PROXY;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_max_temp_file_size 0;
        client_max_body_size 100M;
    }
}
EOF

# 防火墙放行
info "放行 80 443 端口..."
if command -v ufw &>/dev/null; then
    ufw allow 80
    ufw allow 443
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --add-service=http --permanent
    firewall-cmd --add-service=https --permanent
    firewall-cmd --reload
fi

# 测试并重启
nginx -t
systemctl restart nginx

# 申请证书
info "开始申请 SSL 证书..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

info "================ 部署完成 ================"
info "访问地址：https://$DOMAIN"
info "代理转发：$DOMAIN → $PROXY"
info "自动 HTTPS 已开启"
