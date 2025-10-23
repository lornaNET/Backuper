#!/usr/bin/env bash
# install.sh for Backuper (lornaNET)
# installs launcher to /usr/local/bin/lornaNET and makes it executable

set -e

INSTALL_BIN_NAME="${INSTALL_BIN_NAME:-lornaNET}"
INSTALL_PATH="/usr/local/bin/${INSTALL_BIN_NAME}"
SOURCE_URL="https://raw.githubusercontent.com/lornaNET/Backuper/main/Backuper.sh"

echo "🚀 نصب Backuper شروع شد..."
echo "دانلود از ${SOURCE_URL}"

# 1) دانلود آخرین نسخه
curl -fsSL "${SOURCE_URL}" | sed '1s/^\xEF\xBB\xBF//' | tr -d '\r' > /tmp/Backuper.sh

# 2) بررسی صحت
if ! grep -q "Backuper (Unified Launcher)" /tmp/Backuper.sh; then
  echo "❌ خطا: فایل درست دانلود نشد."
  exit 1
fi

# 3) نصب در مسیر
sudo install -m 0755 /tmp/Backuper.sh "${INSTALL_PATH}"

# 4) بررسی نهایی
if [ -x "${INSTALL_PATH}" ]; then
  echo "✅ نصب با موفقیت انجام شد!"
  echo "برای اجرا از دستور زیر استفاده کن:"
  echo "  sudo ${INSTALL_BIN_NAME}"
else
  echo "⚠️  نصب انجام نشد. مسیر ${INSTALL_PATH} بررسی شود."
fi

# 5) گزینهٔ حذف (uninstall)
echo
echo "برای حذف، دستور زیر را اجرا کن:"
echo "  sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/lornaNET/Backuper/main/uninstall.sh)\""
