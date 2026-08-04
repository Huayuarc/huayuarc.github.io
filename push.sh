#!/bin/bash
#==========================================
# Huayuarc Cydia 源一键推送脚本
# - Python 引擎处理全部 deb（增量缓存）
# - Release 只发布 Packages/Packages.gz，避免 GitHub Pages 压缩索引缓存不同步
#==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "========================================"
echo "  Huayuarc 源一键推送"
echo "  目录: $SCRIPT_DIR"
echo "========================================"

DEBS_DIR="$SCRIPT_DIR/debs"
[ -d "$DEBS_DIR" ] || { echo "[错误] debs/ 目录不存在!"; exit 1; }

PACKAGES_FILE="$SCRIPT_DIR/Packages"
CACHE_DIR="$SCRIPT_DIR/.deb_cache"
mkdir -p "$CACHE_DIR"

DEB_FILES=("$DEBS_DIR"/*.deb)
TOTAL=${#DEB_FILES[@]}
echo "[信息] debs 目录共 $TOTAL 个包"

#=== 处理 git safe.directory ===
if ! GIT_TOP=$(git rev-parse --show-toplevel 2>/dev/null); then
    GIT_ERR=$(git rev-parse --show-toplevel 2>&1)
    GIT_PATH=$(echo "$GIT_ERR" | grep -o "dubious ownership in repository at '[^']*'" | sed "s/^.*at '//;s/'$//")
    [ -n "$GIT_PATH" ] && git config --global --add safe.directory "$GIT_PATH" 2>/dev/null
fi

#=== 检查 python3 ===
PYTHON3=""
for _cmd in python3 python; do
    command -v "$_cmd" >/dev/null 2>&1 && { PYTHON3="$_cmd"; break; }
done

#=== 1. 重建 Packages（Python 引擎处理）===
echo ""
echo "[1/4] 重建 Packages..."

if [ -z "$PYTHON3" ]; then
    echo "  [警告] python3 未安装，跳过 Packages 重建（使用现有 Packages）"
    echo "  [提示] 安装: apt install python3"
    CACHED=0; CHANGED=0; SKIPPED=0
else
    STATS_FILE=$(mktemp "$SCRIPT_DIR/.stats.XXXXXX")

"$PYTHON3" - "$DEBS_DIR" "$CACHE_DIR" "$PACKAGES_FILE" "$STATS_FILE" << 'PYEOF'
import sys, os, hashlib, tarfile, io

debs_dir = sys.argv[1]
cache_dir = sys.argv[2]
packages_file = sys.argv[3]
stats_file = sys.argv[4]

deb_names = sorted([
    f for f in os.listdir(debs_dir) if f.endswith('.deb')
])
changed = 0
cached = 0
skipped = 0

entries = []

for name in deb_names:
    deb_path = os.path.join(debs_dir, name)
    cache_key = name.replace('/', '_')
    cache_path = os.path.join(cache_dir, cache_key + '.cache')

    try:
        file_mtime = int(os.stat(deb_path).st_mtime)
    except OSError:
        skipped += 1
        continue

    #--- 检查快取 ---
    cache_mtime = None
    if os.path.isfile(cache_path):
        try:
            with open(cache_path, 'r') as cf:
                first = cf.readline().strip()
                if first:
                    cache_mtime = int(first)
        except (ValueError, OSError):
            pass

    if cache_mtime == file_mtime and cache_mtime is not None:
        with open(cache_path, 'r') as cf:
            cf.readline()
            entries.append(cf.read())
        cached += 1
        continue

    #--- 读取 .deb 一次 ---
    try:
        with open(deb_path, 'rb') as fh:
            data = fh.read()
    except OSError:
        print(f"  [警告] 无法读取: {name}")
        skipped += 1
        continue

    size = len(data)
    md5 = hashlib.md5(data).hexdigest()
    sha256 = hashlib.sha256(data).hexdigest()

    #--- 解析 ar 包提取 control ---
    control = None
    if data[:8] == b'!<arch>\n':
        pos = 8
        while pos + 60 <= len(data):
            header = data[pos:pos+60]
            hdr_name = header[:16].rstrip(b' ').rstrip(b'/').decode('ascii', errors='replace')
            try:
                member_size = int(header[48:58].rstrip(b' ').decode('ascii'))
            except ValueError:
                break
            pos += 60
            content = data[pos:pos+member_size]
            if hdr_name.startswith('control.tar'):
                try:
                    tf = tarfile.open(fileobj=io.BytesIO(content))
                    try:
                        try:
                            cf_member = tf.extractfile('./control')
                        except KeyError:
                            cf_member = None
                        if cf_member is None:
                            try:
                                cf_member = tf.extractfile('control')
                            except KeyError:
                                cf_member = None
                        if cf_member is not None:
                            control = cf_member.read().decode('utf-8', errors='replace')
                    finally:
                        tf.close()
                except Exception:
                    pass
                break
            pos += member_size
            if pos % 2 != 0:
                pos += 1

    if control is None:
        print(f"  [警告] 无法提取 control: {name}")
        skipped += 1
        continue

    #--- 组装并快取 ---
    entry = control.rstrip('\n') + '\n'
    entry += f'Filename: debs/{name}\n'
    entry += f'Size: {size}\n'
    entry += f'MD5sum: {md5}\n'
    entry += 'SHA1: \n'
    entry += f'SHA256: {sha256}\n\n'

    try:
        with open(cache_path, 'w') as cf:
            cf.write(f'{file_mtime}\n{entry}')
    except OSError:
        pass

    entries.append(entry)
    changed += 1

#--- 写入 Packages ---
with open(packages_file, 'w') as pf:
    for entry in entries:
        pf.write(entry)

with open(stats_file, 'w') as sf:
    sf.write(f'{cached} {changed} {skipped}')
PYEOF

# 读取统计
read -r CACHED CHANGED SKIPPED < "$STATS_FILE"
rm -f "$STATS_FILE"
echo "  [完成]（快取命中: $CACHED / 重新计算: $CHANGED${SKIPPED:+/ 跳过: $SKIPPED}）"
wc -c < "$PACKAGES_FILE" | xargs printf "  [信息] Packages 大小: %s 字节\n"
fi

#=== 2. 压缩 ===
echo ""
echo "[2/4] 压缩 Packages..."
# 使用 -n 不写入 gzip 原文件名/时间戳，降低重复推送时的哈希变化。
gzip -9knf "$PACKAGES_FILE" 2>/dev/null && echo "  [OK] Packages.gz"
echo "  [跳过] Packages.xz/Packages.lzma 不再写入 Release，避免 CDN 缓存导致哈希错误"

#=== 3. 生成 Release ===
echo ""
echo "[3/4] 生成 Release 文件..."

DATE=$(TZ='Asia/Shanghai' date '+%a, %d %b %Y %H:%M:%S %z' 2>/dev/null || date -R)
RELEASE_FILE="$SCRIPT_DIR/Release"

calc_size() { stat -c%s "$1" 2>/dev/null || echo "0"; }
calc_md5() { local h; h=$(md5sum "$1" 2>/dev/null); echo "${h%% *}"; }
calc_sha1() { local h; h=$(sha1sum "$1" 2>/dev/null); echo "${h%% *}"; }
calc_sha256() { local h; h=$(sha256sum "$1" 2>/dev/null); echo "${h%% *}"; }

PS=$PACKAGES_FILE
cat > "$RELEASE_FILE" << EOF
Origin: Huayuarc
Label: Huayuarc
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
Components: main
Description: QQ交流群：797075691
Date: $DATE
NotAutomatic: No

MD5Sum:
 $(calc_md5 "$PS") $(calc_size "$PS") Packages
 $(calc_md5 "${PS}.gz") $(calc_size "${PS}.gz") Packages.gz
SHA1:
 $(calc_sha1 "$PS") $(calc_size "$PS") Packages
 $(calc_sha1 "${PS}.gz") $(calc_size "${PS}.gz") Packages.gz
SHA256:
 $(calc_sha256 "$PS") $(calc_size "$PS") Packages
 $(calc_sha256 "${PS}.gz") $(calc_size "${PS}.gz") Packages.gz
EOF
echo "  [OK] Release 已生成"

#=== 4. Git 提交推送 ===
echo ""
echo "[4/4] Git 提交并推送..."

if [ -d "$SCRIPT_DIR/.git" ]; then
    # 清理上次残留的 index 锁，防止 git add 报权限错误
    [ -f "$SCRIPT_DIR/.git/index.lock" ] && rm -f "$SCRIPT_DIR/.git/index.lock"
    git reset HEAD 2>/dev/null
    # 从发布分支移除旧压缩索引；Sileo 会回退使用 Packages.gz。
    git rm --cached --ignore-unmatch Packages.xz Packages.lzma 2>/dev/null || true

    git add index.html css/ CydiaIcon.png Categories debs/ icon/ sileodepiction/ Packages Packages.gz Release push.sh 2>&1

    CHANGES=$(git diff --name-only --cached 2>/dev/null)
    if [ -z "$CHANGES" ]; then
        echo "  [提示] 无变更，跳过提交"
    else
        echo "  [信息] 变更文件:"
        echo "$CHANGES" | sed 's/^/    - /'
        git commit -m "源更新: $(date '+%Y-%m-%d %H:%M')"
        echo "  [OK] 已提交"

        #=== SSH 推送配置（自动创建 wrapper）===
        SSH_KEY="$SCRIPT_DIR/.ssh/id_ed25519"
        SSH_WRAPPER="$SCRIPT_DIR/.ssh/git-ssh-wrapper.sh"
        if [ -f "$SSH_KEY" ]; then
            cat > "$SSH_WRAPPER" << WRAPEOF
#!/bin/bash
# BatchMode=yes          禁止任何交互式提示（密码/指纹等），避免 push 卡在等待输入
# ConnectTimeout=15      连接阶段 15 秒超时，网络抖动时快速失败而不是无限等
# ServerAlive*           保活探测，连接假死时主动断开
# AddressFamily inet     强制走 IPv4，避免 iOS 半配置 IPv6 路由导致 TCP 连接反复重试
exec /var/jb/usr/bin/ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o AddressFamily=inet "\$@"
WRAPEOF
            chmod +x "$SSH_WRAPPER" 2>/dev/null
            git config core.sshCommand "$SSH_WRAPPER"
        fi

        REMOTE=$(git remote 2>/dev/null)
        if [ -n "$REMOTE" ]; then
            #=== 检测远程默认分支 ===
            CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
            echo "  [信息] 推送至 $REMOTE (分支: $CURRENT_BRANCH) ..."

            #=== 检测 upstream 是否匹配当前分支 ===
            UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
            if [ "$UPSTREAM" != "refs/remotes/$REMOTE/$CURRENT_BRANCH" ]; then
                echo "  [注意] 重置 upstream → $REMOTE/$CURRENT_BRANCH"
                git branch --set-upstream-to="$REMOTE/$CURRENT_BRANCH" 2>/dev/null || \
                git branch --unset-upstream 2>/dev/null
            fi

            #=== 带超时和重试的推送 ===
            if command -v timeout >/dev/null 2>&1; then
                PUSH_TIMEOUT=300
                PUSH_ATTEMPTS=3
            else
                PUSH_TIMEOUT=0   # 0 = 不限时（无 timeout 命令时兜底）
                PUSH_ATTEMPTS=1
            fi
            PUSH_OK=0
            attempt=1
            while [ "$attempt" -le "$PUSH_ATTEMPTS" ]; do
                if [ "$PUSH_TIMEOUT" -gt 0 ]; then
                    if timeout "$PUSH_TIMEOUT" git push origin "$CURRENT_BRANCH" 2>&1; then
                        PUSH_OK=1; break
                    else
                        RC=$?
                        if [ "$RC" -eq 124 ]; then
                            echo "  [警告] 推送超时(>${PUSH_TIMEOUT}s)，第 $attempt/$PUSH_ATTEMPTS 次失败"
                        else
                            echo "  [警告] 推送失败(exit=$RC)，第 $attempt/$PUSH_ATTEMPTS 次失败"
                        fi
                    fi
                else
                    if git push origin "$CURRENT_BRANCH" 2>&1; then
                        PUSH_OK=1; break
                    else
                        echo "  [警告] 推送失败，第 $attempt/$PUSH_ATTEMPTS 次失败"
                    fi
                fi
                attempt=$((attempt+1))
                [ "$attempt" -le "$PUSH_ATTEMPTS" ] && sleep 5
            done

            if [ "$PUSH_OK" -ne 1 ]; then
                echo "  [错误] 推送多次失败！请检查网络连接 / SSH 密钥配置。"
                echo "  [提示] 运行: ssh -T git@github.com"
                echo "  [提示] 检查密钥: ls -la ~/.ssh/"
                exit 1
            fi
            echo "  [OK] 推送成功"
        else
            echo "  [信息] 无远程仓库，跳过推送"
        fi
    fi
else
    echo "  [跳过] 非 Git 仓库"
fi

echo ""
echo "========================================"
echo "  更新完成！包数量: $TOTAL"
echo "========================================"
