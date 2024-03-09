#!/bin/bash
dpkg-scanpackages -m . /dev/null > Packages
bzip2 -c Packages > Packages.bz2
xz -c Packages > Packages.xz

git add .
git commit -m "更新文件"
git push