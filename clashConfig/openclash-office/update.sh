#!/bin/sh
# 不带参数：应用设备上的 office.yaml。
# 带 HTTPS URL：下载并校验新清单，成功后替换本地文件并应用。
# 出错即退出；下载和清单校验失败时不会替换当前清单。
set -eu
BASE=/etc/openclash/custom/office
LOCK=/tmp/sonic-office-update.lock
# 用目录锁防止并发更新；临时下载文件也放在锁目录内。
mkdir "$LOCK" 2>/dev/null || { echo 'Another update is running' >&2; exit 1; }
# 无论正常退出还是收到终止信号，都清理本次锁目录。
trap 'rm -rf "$LOCK"' EXIT HUP INT TERM
candidate="$BASE/office.yaml"
# 远端更新仅接受 HTTPS，并设置连接、整体下载超时。
if [ "$#" -gt 0 ]; then
  case "$1" in https://*) ;; *) echo 'HTTPS URL required' >&2; exit 1;; esac
  command -v curl >/dev/null
  curl -fL --connect-timeout 10 --max-time 60 "$1" -o "$LOCK/office.yaml"
  candidate="$LOCK/office.yaml"
fi
# 在改动 dnsmasq 配置和本地清单前，完整校验候选文件。
ruby "$BASE/apply.rb" validate "$candidate"
ruby "$BASE/apply.rb" domains "$candidate" > "$LOCK/domains"
# 只撤销本工具上次添加的重绑定例外，不删除用户原有条目。
if [ -f "$BASE/managed-domains" ]; then
  while IFS= read -r domain; do
    [ -z "$domain" ] || uci -q del_list "dhcp.@dnsmasq[0].rebind_domain=$domain" || true
done < "$BASE/managed-domains"
fi
# 重建本工具拥有的域名记录；原本就存在的白名单不纳入管理。
: > "$LOCK/managed"
while IFS= read -r domain; do
  [ -n "$domain" ] || continue
  if ! uci -q get 'dhcp.@dnsmasq[0].rebind_domain' | tr ' ' '\n' | grep -Fxq "$domain"; then
    uci add_list "dhcp.@dnsmasq[0].rebind_domain=$domain"
    echo "$domain" >> "$LOCK/managed"
  fi
done < "$LOCK/domains"
# 提交域名白名单；不关闭全局 DNS 重绑定保护。
uci commit dhcp
# 远端清单校验通过后保留上一版，并在同目录替换当前清单。
if [ "$candidate" != "$BASE/office.yaml" ]; then
  cp -p "$BASE/office.yaml" "$BASE/office.yaml.previous"
  cp "$candidate" "$BASE/office.yaml.new"
  mv "$BASE/office.yaml.new" "$BASE/office.yaml"
fi
# 保存本工具管理的域名，供下次更新精确清理。
cp "$LOCK/managed" "$BASE/managed-domains"
# 重启 DNS 和 OpenClash；后者生成配置时会自动调用覆写脚本。
/etc/init.d/dnsmasq restart
/etc/init.d/openclash restart
echo 'Office configuration applied. Verify OpenClash startup and office access.'
