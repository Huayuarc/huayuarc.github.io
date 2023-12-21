#!/usr/bin/env bash
cd $(dirname "$0")

echo "开始重新压缩deb"
dpkg-scanpackages -m debs/rootless/ /dev/null > Packages
echo "完成压缩deb"

echo "压缩Packages.bz2、Packages.xz"
bzip2 -c Packages > Packages.bz2
gzip -c Packages > Packages.xz
echo "压缩完成"
