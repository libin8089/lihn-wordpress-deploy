#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# lihn-wordpress-deploy
# WordPress 毛坯房部署工具
# 支持 Ubuntu 24.04 LTS
# 请仅在新建、没有现有网站的服务器上运行。

readonly DB_USER="adman_wp"
readonly DB_PREFIX="adman_wp_"
readonly INFO_FILE="/root/wordpress-install-info.txt"

DOMAIN=""
SITE_PORT=""
HTTPS_PORT=""
SITE_DIR=""
DB_NAME=""
DB_PASS=""
WP_ADMIN=""
WP_PASS=""
HTTPS_STATUS="未配置"

log()  { printf '\033[0;32m[完成]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[提示]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }

trap 'echo "[错误] 第 ${LINENO} 行执行失败，请检查上方输出。" >&2' ERR

[[ $EUID -eq 0 ]] || die "请使用 root 用户运行。"
command -v apt-get >/dev/null 2>&1 || die "当前系统不支持。"

source /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] ||
    die "本脚本仅支持 Ubuntu 24.04 LTS。"

echo "=========================================="
echo "       LIHN WordPress 自动部署工具"
echo "=========================================="

# 1. 检查资源
CPU_COUNT="$(nproc)"
MEM_MB="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
DISK_FREE_GB="$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')"

echo "系统：Ubuntu ${VERSION_ID}"
echo "CPU：${CPU_COUNT} 核"
echo "内存：${MEM_MB} MB"
echo "磁盘剩余：${DISK_FREE_GB} GB"

(( MEM_MB >= 1024 )) || warn "内存低于 1GB，运行 WordPress 可能较慢。"
(( DISK_FREE_GB >= 5 )) || die "磁盘可用空间不足 5GB。"

# 2. 检查是否已有网站
if command -v nginx >/dev/null 2>&1 ||
   command -v apache2 >/dev/null 2>&1 ||
   [[ -f /var/www/html/wp-config.php ]]; then
    die "检测到已有 Web 服务或 WordPress。为避免影响现有网站，已停止。"
fi

# 3. 检查端口
port_in_use() {
    ss -H -ltn "( sport = :$1 )" 2>/dev/null | grep -q .
}

choose_port() {
    local default_port="$1"
    local label="$2"
    local selected="$default_port"

    if ! port_in_use "$selected"; then
        printf '%s\n' "$selected"
        return
    fi

    warn "$label 端口 $selected 已被占用。"
    ss -ltnp "( sport = :$selected )" >&2 || true

    while true; do
        read -r -p "请输入其他未占用的 $label 端口（1024-65535，q 退出）：" selected
        [[ "$selected" == "q" ]] && exit 0

        [[ "$selected" =~ ^[0-9]+$ ]] ||
            { warn "端口必须是数字。"; continue; }

        (( selected >= 1024 && selected <= 65535 )) ||
            { warn "请输入 1024-65535 之间的端口。"; continue; }

        if ! port_in_use "$selected"; then
            printf '%s\n' "$selected"
            return
        fi

        warn "端口 $selected 仍被占用。"
    done
}

SITE_PORT="$(choose_port 80 HTTP)"
HTTPS_PORT="$(choose_port 443 HTTPS)"

echo "HTTP 端口：$SITE_PORT"
echo "HTTPS 端口：$HTTPS_PORT"

# 4. 输入域名
while true; do
    read -r -p "请输入已经解析到本服务器的域名：" DOMAIN

    DOMAIN="${DOMAIN,,}"
    DOMAIN="${DOMAIN%.}"

    if [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] &&
       [[ "$DOMAIN" == *.* && "$DOMAIN" != *..* ]]; then
        break
    fi

    warn "域名格式不正确，请重新输入。"
done

SITE_DIR="/var/www/$DOMAIN"

[[ ! -e "$SITE_DIR" ]] || die "目录 $SITE_DIR 已存在，拒绝覆盖。"

# 5. 检查 DNS
PUBLIC_IP="$(curl -4 -fsS --max-time 8 https://api.ipify.org || true)"
DNS_IPS="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u || true)"

[[ -n "$DNS_IPS" ]] || die "无法查询域名 IPv4 记录，请检查 DNS。"

echo "服务器公网 IPv4：${PUBLIC_IP:-无法自动获取}"
echo "域名解析结果："
echo "$DNS_IPS"

if [[ -n "$PUBLIC_IP" ]] && ! grep -Fxq "$PUBLIC_IP" <<< "$DNS_IPS"; then
    die "域名解析未匹配服务器公网 IPv4。请检查 A 记录、CDN 或代理配置。"
fi

if [[ -z "$PUBLIC_IP" ]]; then
    read -r -p "无法自动获取公网 IP。确认 DNS 已正确配置？输入 YES 继续：" CONFIRM
    [[ "$CONFIRM" == "YES" ]] || exit 1
fi

read -r -p "确认使用域名 $DOMAIN？输入 YES 继续：" CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

# 6. 生成随机凭据
command -v openssl >/dev/null 2>&1 || {
    apt-get update
    apt-get install -y openssl
}

DB_NAME="${DB_PREFIX}$(openssl rand -hex 4)"
DB_PASS="$(openssl rand -hex 32)"
WP_ADMIN="admin_$(openssl rand -hex 4)"
WP_PASS="$(openssl rand -hex 24)"

# 7. 安装运行环境
export DEBIAN_FRONTEND=noninteractive

log "更新软件包索引……"
apt-get update

log "安装 Nginx、MariaDB、PHP 8.3……"
apt-get install -y \
    nginx mariadb-server \
    php8.3-fpm php8.3-mysql php8.3-curl \
    php8.3-gd php8.3-mbstring php8.3-xml \
    php8.3-zip php8.3-intl php8.3-bcmath \
    curl ca-certificates openssl unzip

systemctl enable --now nginx
systemctl enable --now mariadb
systemctl enable --now php8.3-fpm

# 8. 创建数据库
log "创建数据库……"

mariadb <<SQL
CREATE DATABASE \`${DB_NAME}\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER '${DB_USER}'@'localhost'
  IDENTIFIED BY '${DB_PASS}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.*
  TO '${DB_USER}'@'localhost';

FLUSH PRIVILEGES;
SQL

# 9. 下载 WordPress
log "下载 WordPress 官方程序……"

install -d -o www-data -g www-data -m 0755 "$SITE_DIR"

curl -fL --retry 3 \
    https://wordpress.org/latest.tar.gz \
    -o /tmp/lihn-wordpress-latest.tar.gz

mkdir -p /tmp/lihn-wp-install
tar -xzf /tmp/lihn-wordpress-latest.tar.gz -C /tmp/lihn-wp-install

cp -a /tmp/lihn-wp-install/wordpress/. "$SITE_DIR/"

# 10. 配置 WordPress
log "配置 WordPress……"

cp "$SITE_DIR/wp-config-sample.php" "$SITE_DIR/wp-config.php"

export DB_NAME DB_USER DB_PASS SITE_DIR

php <<'PHP'
<?php
$file = getenv('SITE_DIR') . '/wp-config.php';
$config = file_get_contents($file);

$config = str_replace(
    ['database_name_here', 'username_here', 'password_here'],
    [
        addslashes(getenv('DB_NAME')),
        addslashes(getenv('DB_USER')),
        addslashes(getenv('DB_PASS'))
    ],
    $config
);

$keys = [
    'AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY',
    'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT'
];

foreach ($keys as $key) {
    $salt = bin2hex(random_bytes(48));
    $pattern = "/define\\('" . $key . "',\\s*'[^']*'\\);/";
    $replacement = "define('" . $key . "', '" . $salt . "');";
    $config = preg_replace($pattern, $replacement, $config);
}

file_put_contents($file, $config);
PHP

chown -R www-data:www-data "$SITE_DIR"
chmod 640 "$SITE_DIR/wp-config.php"

# 11. 安装 WP-CLI，用于完成真正的 WordPress 初始化
log "安装 WP-CLI……"

curl -fL --retry 3 \
    https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp

chmod 755 /usr/local/bin/wp
php /usr/local/bin/wp --info >/dev/null

# 12. 配置 Nginx
log "配置 Nginx……"

cat > "/etc/nginx/sites-available/$DOMAIN" <<NGINX
server {
    listen $SITE_PORT;
    server_name $DOMAIN;

    root $SITE_DIR;
    index index.php index.html;

    client_max_body_size 32m;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGINX

ln -s "/etc/nginx/sites-available/$DOMAIN" \
      "/etc/nginx/sites-enabled/$DOMAIN"

nginx -t
systemctl reload nginx

# 13. 完成 WordPress 初始化
log "创建 WordPress 管理员并完成初始化……"

WP_URL="http://${DOMAIN}:${SITE_PORT}"

sudo -u www-data wp core install \
    --path="$SITE_DIR" \
    --url="$WP_URL" \
    --title="WordPress Site" \
    --admin_user="$WP_ADMIN" \
    --admin_password="$WP_PASS" \
    --admin_email="admin@${DOMAIN}" \
    --skip-email

# 14. 防火墙提示
echo
echo "=========================================="
echo "防火墙提示"
echo "=========================================="
echo "请确认云平台安全组允许 TCP $SITE_PORT 入站。"
echo "如需 HTTPS，还必须允许相应的验证和访问端口。"
echo "本脚本不会默认放行全部端口。"

# 15. HTTPS
if [[ "$SITE_PORT" == "80" && "$HTTPS_PORT" == "443" ]]; then
    echo
    read -r -p "尝试申请 Let's Encrypt HTTPS 证书？[Y/n]：" SSL_CHOICE
    SSL_CHOICE="${SSL_CHOICE:-Y}"

    if [[ "$SSL_CHOICE" =~ ^[Yy]$ ]]; then
        apt-get install -y certbot python3-certbot-nginx

        if certbot --nginx \
            -d "$DOMAIN" \
            --non-interactive \
            --agree-tos \
            --register-unsafely-without-email \
            --redirect; then
            HTTPS_STATUS="已配置"
            WP_URL="https://${DOMAIN}"
            sudo -u www-data wp option update home "$WP_URL" --path="$SITE_DIR"
            sudo -u www-data wp option update siteurl "$WP_URL" --path="$SITE_DIR"
        else
            HTTPS_STATUS="申请失败，请检查 DNS、端口和云平台安全组"
        fi
    fi
else
    HTTPS_STATUS="未自动配置：非标准端口需要额外配置"
fi

# 16. 保存安装信息
cat > "$INFO_FILE" <<INFO
WordPress 安装信息
生成时间：$(date -Is)

网站域名：${DOMAIN}
网站访问地址：${WP_URL}
HTTP 端口：${SITE_PORT}
HTTPS 端口：${HTTPS_PORT}
网站目录：${SITE_DIR}
HTTPS 状态：${HTTPS_STATUS}

数据库地址：localhost
数据库名称：${DB_NAME}
数据库用户名：${DB_USER}
数据库密码：${DB_PASS}

WordPress 管理员用户名：${WP_ADMIN}
WordPress 管理员密码：${WP_PASS}

注意：
1. 本文件包含敏感凭据。
2. 不要上传到 GitHub。
3. 不要放入网站公开目录。
4. 请另外备份数据库和网站文件。
INFO

chown root:root "$INFO_FILE"
chmod 600 "$INFO_FILE"

# 17. 最终检查与输出
systemctl is-active --quiet nginx || die "Nginx 未正常运行。"
systemctl is-active --quiet mariadb || die "MariaDB 未正常运行。"
systemctl is-active --quiet php8.3-fpm || die "PHP-FPM 未正常运行。"

echo
echo "=========================================="
echo "      WordPress 毛坯房部署完成"
echo "=========================================="
echo "网站地址：${WP_URL}"
echo "网站目录：${SITE_DIR}"
echo "数据库地址：localhost"
echo "数据库名称：${DB_NAME}"
echo "数据库用户名：${DB_USER}"
echo "数据库密码：${DB_PASS}"
echo "管理员用户名：${WP_ADMIN}"
echo "管理员密码：${WP_PASS}"
echo "HTTPS 状态：${HTTPS_STATUS}"
echo "安装信息：${INFO_FILE}"
echo "=========================================="
echo "请立即安全保存安装信息，不要公开分享。"
