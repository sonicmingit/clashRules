#!/bin/sh
# 首次安装：在 OpenWrt 解压后的目录中，以 root 执行本脚本。
# 安装过程会应用清单并重启 DNS/OpenClash，网络可能短暂中断。
# 任一命令失败或读取未定义变量时退出，避免继续安装不完整配置。
set -eu
# SOURCE 是脚本所在目录；BASE 是设备上的固定安装目录。
SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BASE=/etc/openclash/custom/office
HOOK=/etc/openclash/custom/openclash_custom_overwrite.sh
# 先检查依赖、清单及已有 OpenClash 入口，再写入系统文件。
command -v ruby >/dev/null
command -v uci >/dev/null
ruby "$SOURCE/apply.rb" validate "$SOURCE/office.yaml"
[ -f "$HOOK" ] || { echo 'OpenClash overwrite hook not found' >&2; exit 1; }
# 备份已有入口、DHCP/DNS 配置，以及已经安装的清单，便于回退。
BACKUP=/root/openclash-office-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP" "$BASE"
cp -p "$HOOK" /etc/config/dhcp "$BACKUP/"
[ ! -f "$BASE/office.yaml" ] || cp -p "$BASE/office.yaml" "$BACKUP/office.yaml"
# 复制运行时所需文件；重复安装时避免将文件复制到自身。
for file in apply.rb overwrite.sh update.sh office.yaml; do
  [ "$SOURCE/$file" = "$BASE/$file" ] || cp "$SOURCE/$file" "$BASE/$file"
done
chmod 755 "$BASE/overwrite.sh" "$BASE/update.sh"
# 仅首次加入托管调用，并放在 shebang 后，避免被已有 exit 提前跳过。
# 保留原脚本其他内容；旧覆写脚本仍可能随后覆盖相同配置。
if ! grep -q '^# BEGIN SONIC OFFICE$' "$HOOK"; then
  tmp=$(mktemp)
  head -n 1 "$HOOK" > "$tmp"
  cat >> "$tmp" <<'HOOKBLOCK'
# BEGIN SONIC OFFICE
/etc/openclash/custom/office/overwrite.sh "$1" || exit 1
# END SONIC OFFICE
HOOKBLOCK
  tail -n +2 "$HOOK" >> "$tmp"
  cat "$tmp" > "$HOOK"
  rm -f "$tmp"
fi
# 统一调用更新脚本，维护域名例外并重启服务，使本地清单生效。
sh "$BASE/update.sh"
echo "Installed. Backup: $BACKUP"
echo 'Existing hooks are preserved; review any older office-appfix.rb overrides for conflicts.'
