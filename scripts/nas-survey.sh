#!/usr/bin/env bash
# Collect the facts about the NAS that decide whether a Buildroot build
# belongs on it. The remote command is one long string on purpose, a
# heredoc over ssh tends to stall.
set -uo pipefail

NAS="${NAS:-sun@192.168.0.157}"
PASS="${NAS_PASS:-1}"

REMOTE='
echo "=== 系统 ==="
uname -a
cat /etc/os-release 2>/dev/null | grep PRETTY
echo ""
echo "=== CPU ==="
nproc
grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed "s/^ //"
echo ""
echo "=== 内存 ==="
free -h
echo ""
echo "=== 文件系统 ==="
df -hT | grep -vE "^(tmpfs|devtmpfs|overlay|shm)"
echo ""
echo "=== HOME 分区 ==="
df -hT "$HOME"
echo ""
echo "=== HOME 占用 TOP10 ==="
du -sh "$HOME"/* 2>/dev/null | sort -rh | head -10
echo ""
echo "=== 全盘大目录 TOP10 (1 层) ==="
for d in / /home /opt /srv /var /mnt /media /data; do
    [ -d "$d" ] && echo "$d: $(du -sh $d 2>/dev/null | cut -f1)"
done
echo ""
echo "=== 容器运行时 ==="
command -v docker >/dev/null 2>&1 && docker --version || echo "  无 docker"
command -v podman >/dev/null 2>&1 && podman --version || echo "  无 podman"
echo ""
echo "=== 关键服务 ==="
ps -eo comm= 2>/dev/null | sort -u | grep -iE "synology|samba|smbd|nfsd|docker|containerd|plex|jellyfin|qbittorrent|mysql|postgres|redis|minio|immich|nextcloud" | head -12 || echo "  无明显 NAS 服务"
echo ""
echo "=== 可写测试 ==="
for d in "$HOME" /tmp /var/tmp /opt /srv; do
    if [ -d "$d" ] && touch "$d/.wt_$$" 2>/dev/null; then echo "  可写: $d"; rm -f "$d/.wt_$$"; elif [ -d "$d" ]; then echo "  只读: $d"; fi
done
'

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    "$NAS" "$REMOTE" 2>&1 | tr -d '\0'
