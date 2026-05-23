#!/bin/bash
# deploy.sh — Đẩy code lên GitHub Pages (Mac version)
# Tương đương deploy.bat trên Windows

set -e  # Thoát ngay nếu có lỗi

cd "$(dirname "$0")"

echo "🔍 Đang chạy syntax check..."
python3 check_syntax3.py || { echo "❌ Syntax check fail. Dừng deploy."; exit 1; }

echo ""
echo "🧪 Đang chạy auto_test.py..."
python3 auto_test.py || { echo "⚠️  Auto test có lỗi nhưng tiếp tục."; }

echo ""
echo "📦 Đang commit..."
git add .
git status --short

# Cho phép custom commit message hoặc dùng default
if [ -z "$1" ]; then
  COMMIT_MSG="Update app $(date '+%Y/%m/%d %H:%M:%S')"
else
  COMMIT_MSG="$1"
fi

git commit -m "$COMMIT_MSG" || { echo "ℹ️  Không có thay đổi để commit."; exit 0; }

echo ""
echo "🚀 Đang push lên GitHub..."
git push

echo ""
echo "✅ Deploy thành công!"
echo "🌐 https://trantuanbevn-cell.github.io/studio-design"
echo "⏰ Đợi ~30 giây để GitHub Pages cập nhật."
