#!/bin/bash
# ============================================
# Filza 源推送腳本 - huayuarc.github.io
# 自動更新 Packages → 提交 → 推送到 GitHub
# ============================================

REPO_DIR="/var/mobile/Containers/Shared/AppGroup/.jbroot-E4BD384C9F506280/var/mobile/huayuarc.github.io"
cd "$REPO_DIR" || { echo "錯誤：無法進入目錄 $REPO_DIR"; exit 1; }

echo "========================================"
echo "  Filza 源推送工具"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# 1. 重新生成 Packages
echo "[0/4] 重新生成 Packages..."
> Packages.tmp
for deb in debs/*.deb; do
    [ -f "$deb" ] || continue
    control=$(dpkg-deb -f "$deb" 2>/dev/null)
    size=$(stat -c%s "$deb" 2>/dev/null)
    md5=$(md5sum "$deb" 2>/dev/null | awk '{print $1}')
    sha1=$(shasum -a 1 "$deb" 2>/dev/null | awk '{print $1}')
    sha256=$(shasum -a 256 "$deb" 2>/dev/null | awk '{print $1}')

    echo "$control" >> Packages.tmp
    echo "Filename: $deb" >> Packages.tmp
    echo "Size: $size" >> Packages.tmp
    echo "MD5sum: $md5" >> Packages.tmp
    echo "SHA1: $sha1" >> Packages.tmp
    echo "SHA256: $sha256" >> Packages.tmp
    echo "" >> Packages.tmp
done
mv Packages.tmp Packages
echo "  套件數量: $(grep -c '^Package:' Packages)"
echo ""

# 2. 檢查是否有變更
if [[ -z $(git status --porcelain) ]]; then
    echo "沒有新的變更，無需提交。"
    exit 0
fi

# 3. 顯示變更
echo "將要提交的變更："
git status --short
echo ""

# 4. 提交
echo "[1/4] 添加檔案..."
git add -A
echo "[2/4] 提交變更..."
COMMIT_MSG="更新源 - $(date '+%Y-%m-%d %H:%M')"
git commit -m "$COMMIT_MSG"

# 5. 推送
echo "[3/4] 推送到 GitHub..."
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
