#!/bin/bash

echo "开始压缩deb"
dpkg-scanpackages -m . /dev/null > Packages
echo "完成压缩deb"

echo "压缩.bz2、.xz、.gz"
bzip2 -c Packages > Packages.bz2
xz -c Packages > Packages.xz
gzip -c Packages > Packages.gz
echo "压缩完成"
