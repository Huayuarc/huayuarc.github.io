#!/bin/bash

echo "开始压缩deb"
dpkg-scanpackages -m . /dev/null > Packages
echo "压缩deb完成"

echo "开始压缩.bz2、.xz"
bzip2 -c Packages > Packages.bz2
xz -c Packages > Packages.xz
echo "压缩完成"
