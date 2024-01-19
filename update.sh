#!/bin/bash

echo "开始压缩deb"
dpkg-scanpackages -m ./debs /dev/null > Packages
echo "压缩deb完成"

echo "开始压缩.bz2、.xz"
bzip2 -c Packages > Packages.bz2
xz -c Packages > Packages.xz
echo "压缩完成"

echo "推送到远程仓库github"
git add .
git commit -m "更新文件"
git push
echo "更新完成"