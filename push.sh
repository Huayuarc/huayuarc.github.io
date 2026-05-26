#!/bin/bash
# ============================================
# Filza 源推送腳本 - huayuarc.github.io
# 將本地改動一鍵提交並推送到 GitHub
# ============================================

REPO_DIR="/var/mobile/Containers/Shared/AppGroup/.jbroot-E4BD384C9F506280/var/mobile/huayuarc.github.io"
cd "$REPO_DIR" || { echo "錯誤：無法進入目錄 $REPO_DIR"; exit 1; }

echo "========================================"
echo "  Filza 源推送工具"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# 1. 檢查是否有變更
if [[ -z $(git status --porcelain) ]]; then
    echo "沒有新的變更，無需提交。"
    exit 0
fi

# 2. 顯示將要提交的檔案
echo ""
echo "將要提交的變更："
git status --short
echo ""

# 3. 添加所有變更
echo "[1/3] 添加檔案..."
git add -A

# 4. 提交
echo "[2/3] 提交變更..."
COMMIT_MSG="更新源 - $(date '+%Y-%m-%d %H:%M')"
git commit -m "$COMMIT_MSG"

# 5. 推送
echo "[3/3] 推送到 GitHub..."
git push -u origin main

# 6. 結果
if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "  ✓ 推送成功！"
    echo "  https://github.com/Huayuarc/huayuarc.github.io"
    echo "========================================"
else
    echo ""
    echo "  ✗ 推送失敗，請檢查網路連線。"
    exit 1
fi
