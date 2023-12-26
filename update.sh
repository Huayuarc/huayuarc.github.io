#!/bin/bash

echo "开始压缩deb"
dpkg-scanpackages -m . /dev/null > Packages
echo "压缩deb完成"

echo "开始压缩.bz2、.xz、.gz、.lzma、.zst"
bzip2 -c Packages > Packages.bz2
xz -c Packages > Packages.xz
gzip -c Packages > Packages.gz
lzma -c Packages > Packages.lzma
zstd -c Packages > Packages.zst
echo "压缩完成"

echo "git到远程仓库github"
git add .
git commit -m "更新文件"
git push
