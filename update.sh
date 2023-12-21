#!/bin/sh

# 检查当前的执行环境
if [ -t 0 ]; then
  # 终端执行环境，设置为0100755
  chmod 755 "$0"
else
  # 非终端执行环境（如Git提交），设置为0100644
  chmod 644 "$0"
fi

echo "开始重新压缩deb"
dpkg-scanpackages -m debs/rootless/ /dev/null > Packages
echo "完成压缩deb"

echo "压缩Packages.bz2、Packages.xz"
bzip2 -c Packages > Packages.bz2
gzip -c Packages > Packages.xz
echo "重新产生Packages.bz2、Packages.xz完成"
