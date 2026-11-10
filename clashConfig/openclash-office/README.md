# OpenClash 公司网络统一配置

只维护 `office.yaml`，由固定脚本生成公司域名直连、公司 DNS、Fake-IP 排除、网段直连和 dnsmasq 重绑定例外。这里的 DIRECT 是 OpenWrt → Windows 共享 → 单位网络。宿主机 Wi-Fi 分流仍由宿主机路由或 Proxifier 管理。

## 文件

- `office.yaml`：日常维护入口；不是 rule-provider，不能直接填到 rule-providers。
- `apply.rb`：校验清单、合并生成的 Clash YAML。
- `overwrite.sh`：每次 OpenClash 生成配置时调用。
- `install.sh`：备份并安装文件、接入已有覆写入口、应用本地清单。
- `update.sh`：应用本地清单，或下载校验远端清单再应用。

## 首次安装

需要已有 OpenClash、Ruby（含 YAML）、uci；远端更新额外需要 curl 和有效 CA 证书。将本目录完整上传到 OpenWrt，例如 `/root/openclash-office`，以 root 执行：

```sh
cd /root/openclash-office
sh install.sh
```

安装位置：`/etc/openclash/custom/office/`。安装会重启 dnsmasq 和 OpenClash，短暂影响网络。备份保存在 `/root/openclash-office-backup-时间/`。无需修改订阅本体。

脚本在现有 `openclash_custom_overwrite.sh` 的开头加入一次调用，保留原有内容。**当前设备之前建立过 `office-appfix.rb`：部署前应检查其与本清单重复的公司 DNS、hosts 和分流条目，防止旧脚本随后覆盖新值。不要直接删除其中仍需要的 OneDrive 等非办公规则。** 本项目创建文件不代表已部署到设备。

## 日常维护

```yaml
office:
  dns: 10.93.10.1
  outbound: DIRECT
  domain_suffixes:
    - chinaunicom.cn
  networks:
    - 10.236.0.221/32
  hosts: {}
```

本工具目前只支持 IPv4 DNS、网段和 hosts。

域名后缀覆盖根域名及所有子域名，不填通配符、协议、路径。相同后缀下新增网站无需修改。直接使用 IP 的系统添加单个 `/32` 或经过确认的网段；不要盲目添加整个 `10.0.0.0/8`。固定 hosts 仅用于必要时覆盖 DNS，IP 变化需手工更新。

本机修改安装后的 YAML，执行：

```sh
sh /etc/openclash/custom/office/update.sh
```

如果维护 GitHub 上的文件，提交并推送后执行（文件推送前链接不可用）：

```sh
sh /etc/openclash/custom/office/update.sh 'https://raw.githubusercontent.com/sonicmingit/clashRules/refs/heads/main/clashConfig/openclash-office/office.yaml'
```

下载或清单校验失败时不替换当前清单。没有默认定时任务；需要时可自行定时调用上面的命令。远端 YAML 使用安全解析，不执行其中代码。公司内部信息是否公开请自行选择仓库可见性。

覆写每次合并新生成的订阅配置，新增规则置顶；保留其他代理和规则。支持默认 blacklist Fake-IP 过滤模式，遇到 whitelist 模式会报错，不自动修改其语义。不要对同一个已合并配置反复手动执行 apply；删除条目的清理依赖 OpenClash 从订阅重新生成配置。

## 验证

```sh
ruby /etc/openclash/custom/office/apply.rb validate /etc/openclash/custom/office/office.yaml
nslookup aiportal.chinaunicom.cn 10.0.10.11
curl -I --connect-timeout 5 --max-time 15 https://aiportal.chinaunicom.cn
```

检查 OpenClash 启动日志，公司连接应命中 DIRECT。HTTP 403 表示收到服务端拒绝，不代表业务登录正常。测试实际登录和宿主机访问。

## 回退

先恢复备份中的 `openclash_custom_overwrite.sh` 与 `/etc/config/dhcp`，再重启 dnsmasq 和 OpenClash。若安装后又修改过 DHCP/DNS，按差异恢复，避免覆盖其他新设置。仅恢复 YAML 不会移除已经安装的 hook 或已写入的 dnsmasq 白名单。

## 当前验证范围

文件生成后做离线清单、语法与合并行为验证；尚未安装到 OpenWrt。实际系统版本和原有覆写脚本可能影响运行，首次部署应检查启动日志并保留备份。
