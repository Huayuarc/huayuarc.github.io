#!/bin/sh

echo "开始重新压缩deb"
dpkg-scanpackages -m debs/rootless/ /dev/null >Packages
echo "完成压缩deb"

echo "压缩Paackages.bz2、Packages.xz"
bzip2 -c Packages > Packages.bz2
gzip -c Packages > Packages.xz
echo "重新产生Paackages.bz2、Packages.xz完成"
