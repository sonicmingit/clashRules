# 只修改本文件；启动时自动生成 runtime/3proxy.cfg 并同步防火墙。
@{
    # 虚拟机已有的内侧网卡 IP；脚本不自动修改 Windows 网卡地址。
    ListenAddress = '10.0.10.20'
    Port = 1080

    # 允许连接的客户端 IPv4，可填写多个 IP 或网段；其他来源由代理拒绝。
    # 示例：@('10.0.10.1', '10.0.10.30', '10.0.20.0/24')
    AllowedClients = @('10.0.10.1')

    # 相对于本目录，也可填写绝对路径。
    ProxyExe = 'bin\3proxy.exe'

    # 按天记录连接、目标、错误码、收发字节；保留 14 份归档。
    EnableLogging = $true
    LogDirectory = 'logs'
    LogRetention = 14
}
