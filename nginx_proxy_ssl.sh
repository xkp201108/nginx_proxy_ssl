#!/bin/bash

# ====================================================
# 脚本名称: Nginx 通用部署与 SSL 自动化工具
# 适用系统: Ubuntu / Debian / CentOS (基础支持)
# ====================================================

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 权限运行：sudo $0"
  exit 1
fi

# --- 1. 环境准备 ---
echo "🔍 正在检查运行环境..."

# 识别包管理器
if command -v apt &> /dev/null; then
    PKG_MANAGER="apt"
    INSTALL_CMD="apt update && apt install -y"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    INSTALL_CMD="yum install -y"
else
    echo "❌ 不支持的操作系统类型。"
    exit 1
fi

# 安装基础组件
for pkg in nginx certbot python3-certbot-nginx; do
    if ! command -v $pkg &> /dev/null; then
        echo "正在安装 $pkg..."
        eval "$INSTALL_CMD $pkg"
    fi
done

# --- 2. 获取用户参数 ---
read -p "🌐 请输入域名 (例如 abc.abc.com): " DOMAIN
read -p "🔌 请输入后端代理地址 (例如 http://127.0.0.1:8080): " PROXY_PASS
read -p "🛡️ 请输入监听端口 (默认 80): " PORT
PORT=${PORT:-80}

# 自动处理配置路径 (兼容不同 Linux 发行版)
CONF_DIR="/etc/nginx/conf.d"
[ ! -d "$CONF_DIR" ] && CONF_DIR="/etc/nginx/sites-enabled"
CONF_FILE="$CONF_DIR/$DOMAIN.conf"

# --- 3. 彻底清理冲突配置 (解决报错核心) ---
echo "🧹 正在清理可能导致冲突的旧配置..."
# 搜索所有包含该域名的配置文件并暂时移除，确保 nginx -t 能通过
grep -rl "$DOMAIN" /etc/nginx/ | xargs -r rm -f

# 确保 Nginx 此时是干净且可运行的
nginx -t &> /dev/null
if [ $? -ne 0 ]; then
    echo "⚠️ Nginx 存在其他全局配置错误，请先修复 /etc/nginx/nginx.conf"
    nginx -t
    exit 1
fi
systemctl restart nginx

# --- 4. 影子验证：申请证书 ---
echo "🔑 正在申请 SSL 证书 (Webroot 模式)..."
mkdir -p /var/www/cert_verify

# 创建临时 HTTP 验证入口
cat <<EOF > "$CONF_FILE"
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ {
        root /var/www/cert_verify;
    }
}
EOF
systemctl reload nginx

# 申请证书
certbot certonly --webroot -w /var/www/cert_verify -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

# --- 5. 写入最终生产配置 ---
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "✅ 证书获取成功！正在部署最终 HTTPS 配置..."
    
    cat <<EOF > "$CONF_FILE"
server {
    listen $PORT;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    # SSL 证书路径
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # 安全增强配置
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
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

    nginx -t && systemctl restart nginx
    echo "------------------------------------------------"
    echo "🎉 部署成功！"
    echo "🌍 访问地址: https://$DOMAIN"
    echo "📄 配置文件: $CONF_FILE"
    echo "------------------------------------------------"
else
    echo "❌ 证书申请失败。常见原因："
    echo "1. 域名 A 记录未指向本服务器 IP"
    echo "2. 服务器 80 端口被云厂商防火墙拦截"
    echo "3. 域名请求频率触发 Let's Encrypt 限制"
fi
