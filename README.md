# nginx_proxy_ssl
Nginx 一键部署 + 反向代理 + HTTPS 自动证书
一键安装 Nginx、配置反向代理、自动申请 SSL 证书、自动防火墙放行。

## 支持系统
- Ubuntu / Debian
- CentOS 7+ / RockyLinux

## 功能
- 自动安装 Nginx
- 自动配置反向代理
- 自动 HTTP 跳 HTTPS
- 自动申请 Let's Encrypt 证书
- 自动放行 80/443 端口
- 自动重载 Nginx

## 使用方法
**以 root 用户执行：**
-不使用 docker 部署：
```bash
bash <(curl -sL https://raw.githubusercontent.com/xkp201108/nginx_proxy_ssl/main/nginx_proxy_ssl.sh)
```
-用 docker 部署：
```
bash <(curl -sL https://raw.githubusercontent.com/xkp201108/nginx_proxy_ssl/main/nginx_proxy_ssl_docker.sh)
```
