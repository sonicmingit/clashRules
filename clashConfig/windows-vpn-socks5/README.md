# Windows 虚拟机 VPN SOCKS5：一键启动

## 使用步骤

1. 在 VMware 给 Windows 虚拟机增加网卡，接入 VMnet11（op-vm）。例如虚拟机设为 `10.0.10.20/24`，网关和 DNS 留空；宿主机为 `10.0.10.1`。先确认地址未被占用。保留原 USB 和 win-op 网卡。
2. 从 [3proxy 官方发布页](https://github.com/3proxy/3proxy/releases)下载 Windows 发行包，将程序和所需配套文件放到 bin，保证存在 bin/3proxy.exe。
3. 编辑 **settings.psd1**，这是新的统一配置入口。
4. 在虚拟机登录 VPN，并确认虚拟机能够访问目标业务。
5. 双击 **Start.cmd**，确认 UAC。脚本校验参数、程序和监听 IP，更新防火墙，生成 runtime/3proxy.cfg，然后前台运行代理。
6. 保持新窗口开启，Ctrl+C 停止；修改参数后先停止旧代理，再重新双击启动。不自动安装服务或计划任务。

## 参数

```powershell
@{
    ListenAddress = '10.0.10.20'
    Port = 1080
    AllowedClients = @('10.0.10.1', '10.0.10.30')
    ProxyExe = 'bin\3proxy.exe'
    EnableLogging = $true
    LogDirectory = 'logs'
    LogRetention = 14
}
```

- ListenAddress：虚拟机已有的内侧网卡地址；只设置代理监听，不自动修改网卡。
- AllowedClients：允许连接的 IPv4 列表，也支持如 `10.0.20.0/24` 的网段。默认只有宿主机 `10.0.10.1`，其他来源会被代理拒绝；防火墙同步设置来源限制。设备必须能路由到虚拟机该地址。
- ProxyExe：相对于配置文件目录，或绝对路径。
- LogDirectory：本目录下的 ASCII 相对目录，如 logs。
- LogRetention：保留的历史日志份数，默认 14；不代表所有情况下精确保留 14 天。

配置数据使用 PowerShell 数据文件安全读取；不支持用户名密码，目前按来源 IP 授权。IP 白名单不是用户身份认证，适用于可信网络。代理配置会自动生成，不要直接编辑 runtime/3proxy.cfg。

## 日志与流量

按天轮转，默认在 logs。每条记录用分号分隔，字段为：本地时间、服务、错误码、客户端 IP:端口、目标 IP:端口、代理发出字节、代理收到字节、耗时毫秒、请求域名。

日志通常在连接结束时写入；长连接需结束后再看字节统计。它是连接及字节记录，不是流量实时图表、抓包、HTTP 内容记录或网卡级计费。日志可能包含内部访问目标，请自行管理保存范围。更换日志目录后，旧目录日志不会自动清除。

[3proxy 官方日志格式说明](https://github.com/3proxy/3proxy/wiki/3proxy.cfg/)

## Proxifier（宿主机）

1. 添加 SOCKS5 服务器 `10.0.10.20:1080`，不开启用户名密码认证。
2. 保留 Localhost 直连，并在业务规则之前把代理地址 `10.0.10.20` 设为 Direct，避免回环。
3. VPN 业务域名规则使用该代理，放在 OpenWrt 业务规则前；其他规则保持原样，Default 为 Direct。
4. Name Resolution 中选择通过代理解析，Resolve ONLY the following 中加入相同业务域名和后缀。

宿主机 Direct 出口由宿主机路由决定，不会自动锁定 Wi-Fi。VPN 连接使用虚拟机当前路由与 DNS，不指定物理出口，VPN 断开不自动禁止出站。aTrust 是否允许代理访问资源需实测。

测试（替换实际业务域名）：

```powershell
Test-NetConnection 10.0.10.20 -Port 1080
curl.exe -I --proxy socks5h://10.0.10.20:1080 https://实际VPN业务域名
```

收到 HTTP 状态码只说明有响应；403 不代表业务可用，仍需实际登录验证。本方案只允许 TCP CONNECT，不开放 SOCKS UDP/BIND，不提供 ping 或完整 VPN 转发。

## 单独运行与撤销

在虚拟机管理员 PowerShell 中，可以分别执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Set-Firewall.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Socks5.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Set-Firewall.ps1 -Remove
```

关闭代理窗口、删除防火墙规则并移除 Proxifier 对应规则即可撤销。脚本仅管理本项目命名的防火墙规则，不关闭防火墙，不删除其他规则。已有其他宽泛规则仍需自行检查。若单位策略禁止运行脚本或本地网络访问，应联系管理员。

## 文件与验证范围

settings.psd1 维护参数；Common.ps1 校验并生成配置；Start-OneClick.ps1 / Start.cmd 为一键入口；Set-Firewall.ps1 同步白名单；Start-Socks5.ps1 前台启动。中文注释已包含在脚本中。

只进行离线语法、参数校验与配置生成检查；实际防火墙、UAC、代理及 VPN 联网应在虚拟机运行后验证。配置文件不会自动同步到已有下载副本。
