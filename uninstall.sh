#!/usr/bin/env bash
# uninstall.sh for Backuper (lornaNET)

INSTALL_BIN_NAME="${INSTALL_BIN_NAME:-lornaNET}"
INSTALL_PATH="/usr/local/bin/${INSTALL_BIN_NAME}"

echo "🗑️ در حال حذف Backuper..."

if [ -e "${INSTALL_PATH}" ]; then
  sudo rm -f "${INSTALL_PATH}"
  echo "✅ حذف شد: ${INSTALL_PATH}"
else
  echo "⚠️ فایل ${INSTALL_PATH} پیدا نشد."
fi
