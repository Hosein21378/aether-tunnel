#!/bin/bash

set -e

# ==================== تنظیمات ====================
APP_NAME="aether"
INSTALL_DIR="/opt/aether"
DATA_DIR="/var/lib/aether"
CONFIG_DIR="/etc/aether"
SERVICE_NAME="aether"
XRAY_VERSION="25.1.1"          # در صورت نیاز آپدیت شود
PANEL_PORT=2053
GITHUB_REPO="YOUR_USERNAME/aether-tunnel"   # بعداً تغییر بده

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==================== چک‌های اولیه ====================
if [ "$(id -u)" -ne 0 ]; then
    print_error "این اسکریپت باید با دسترسی root اجرا شود."
    exit 1
fi

# ==================== توابع کمکی ====================
generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

get_public_ip() {
    curl -s --max-time 5 https://api.ipify.org || \
    curl -s --max-time 5 https://ifconfig.me || \
    hostname -I | awk '{print $1}'
}

# ==================== شروع نصب ====================
clear
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════╗"
echo "║         Aether Tunnel Installer            ║"
echo "║     Multi-Node Smart Routing + Xray        ║"
echo "╚════════════════════════════════════════════╝"
echo -e "${NC}"

print_info "در حال آماده‌سازی..."

# ایجاد پوشه‌ها
mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$CONFIG_DIR" /var/log/aether

# ==================== نصب وابستگی‌ها ====================
print_info "نصب پکیج‌های مورد نیاز..."

if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq curl wget unzip jq openssl ca-certificates > /dev/null
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget unzip jq openssl > /dev/null
else
    print_error "سیستم‌عامل پشتیبانی نمی‌شود (فعلاً فقط Debian/Ubuntu و CentOS)."
    exit 1
fi

print_ok "وابستگی‌ها نصب شدند."

# ==================== نصب Xray ====================
print_info "در حال نصب هسته Xray..."

ARCH=$(uname -m)
case $ARCH in
    x86_64)  XRAY_ARCH="64" ;;
    aarch64) XRAY_ARCH="arm64-v8a" ;;
    armv7l)  XRAY_ARCH="arm32-v7a" ;;
    *)       print_error "معماری پشتیبانی نمی‌شود: $ARCH"; exit 1 ;;
esac

XRAY_ZIP="Xray-linux-${XRAY_ARCH}.zip"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/${XRAY_ZIP}"

cd /tmp
wget -q "$XRAY_URL" -O "$XRAY_ZIP" || {
    print_error "دانلود Xray ناموفق بود."
    exit 1
}

unzip -qo "$XRAY_ZIP" -d /tmp/xray
mkdir -p /usr/local/share/xray
cp /tmp/xray/xray /usr/local/bin/xray
cp /tmp/xray/geoip.dat /tmp/xray/geosite.dat /usr/local/share/xray/ 2>/dev/null || true
chmod +x /usr/local/bin/xray
rm -rf /tmp/xray /tmp/"$XRAY_ZIP"

print_ok "Xray نصب شد: $(xray version | head -n1)"

# ==================== تولید رمز و تنظیمات اولیه ====================
print_info "تولید تنظیمات اولیه..."

ADMIN_USER="admin"
ADMIN_PASS=$(generate_password)
SECRET_KEY=$(openssl rand -hex 32)
PUBLIC_IP=$(get_public_ip)

# ذخیره اطلاعات
cat > "$CONFIG_DIR/panel.env" <<EOF
ADMIN_USER=${ADMIN_USER}
ADMIN_PASS=${ADMIN_PASS}
SECRET_KEY=${SECRET_KEY}
PANEL_PORT=${PANEL_PORT}
DATA_DIR=${DATA_DIR}
INSTALL_DIR=${INSTALL_DIR}
PUBLIC_IP=${PUBLIC_IP}
EOF

chmod 600 "$CONFIG_DIR/panel.env"

# ==================== کپی فایل‌های برنامه (فعلاً placeholder) ====================
print_info "آماده‌سازی فایل‌های برنامه..."

# در نسخه نهایی اینجا باینری یا سورس دانلود و بیلد می‌شود
# فعلاً یک سرویس ساده placeholder می‌گذاریم

cat > "$INSTALL_DIR/aether-panel" << 'EOF'
#!/bin/bash
# Placeholder - در نسخه‌های بعدی باینری واقعی جایگزین می‌شود
source /etc/aether/panel.env
echo "Aether Panel is running on port $PANEL_PORT"
echo "Admin: $ADMIN_USER / $ADMIN_PASS"
# اینجا بعداً برنامه Go اجرا می‌شود
while true; do sleep 3600; done
EOF

chmod +x "$INSTALL_DIR/aether-panel"

# ==================== سرویس systemd ====================
print_info "ایجاد سرویس systemd..."

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Aether Tunnel Panel
After=network.target

[Service]
Type=simple
EnvironmentFile=${CONFIG_DIR}/panel.env
ExecStart=${INSTALL_DIR}/aether-panel
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME} > /dev/null
systemctl start ${SERVICE_NAME}

print_ok "سرویس راه‌اندازی شد."

# ==================== فایروال (اختیاری) ====================
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PANEL_PORT}/tcp > /dev/null 2>&1 || true
fi

# ==================== خروجی نهایی ====================
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}          نصب با موفقیت انجام شد!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BLUE}لینک ورود به پنل:${NC}  http://${PUBLIC_IP}:${PANEL_PORT}"
echo -e "  ${BLUE}نام کاربری:${NC}       ${ADMIN_USER}"
echo -e "  ${BLUE}رمز عبور:${NC}         ${ADMIN_PASS}"
echo ""
echo -e "  ${YELLOW}نکته:${NC} این اطلاعات را در جای امنی ذخیره کنید."
echo -e "  فایل تنظیمات: ${CONFIG_DIR}/panel.env"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
