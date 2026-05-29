#!/bin/bash
# deploy.sh — Đẩy code lên GitHub Pages (Mac version)
# Tương đương deploy.bat trên Windows

set -e  # Thoát ngay nếu có lỗi

cd "$(dirname "$0")"

# ── Pull code mới nhất từ GitHub trước khi deploy ──
# Tự stash thay đổi local → pull → pop. Cross-machine an toàn.
echo "🔄 Đang pull code mới nhất từ GitHub..."

HAS_CHANGES=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  HAS_CHANGES=1
  echo "   Có thay đổi local — tạm stash..."
  # No -u: stashing untracked files breaks cmd.exe on Windows when deploy.bat
  # itself is untracked; keep both scripts symmetric and stash tracked only.
  git stash push -m "deploy.sh auto-stash $(date '+%H:%M:%S')" || {
    echo "❌ Stash fail. Dừng deploy."
    exit 1
  }
fi

if ! git pull --rebase; then
  echo "❌ Pull fail — có thể có conflict."
  if [ $HAS_CHANGES -eq 1 ]; then
    echo "   Đang restore stash..."
    git stash pop || echo "   ⚠️  Stash pop fail — chạy 'git stash list' để check."
  fi
  exit 1
fi

if [ $HAS_CHANGES -eq 1 ]; then
  echo "   Restore thay đổi local..."
  if ! git stash pop; then
    echo "❌ Stash pop fail — có conflict với code vừa pull."
    echo "   Chạy: git status + git stash list để xử lý."
    exit 1
  fi
fi
echo ""

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
echo "🌐 https://gendaisougo-vietnam.github.io/gsa"
echo "⏰ Đợi ~30 giây để GitHub Pages cập nhật."
