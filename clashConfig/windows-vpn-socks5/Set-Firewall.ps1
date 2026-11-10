# 在 Windows 虚拟机的管理员 PowerShell 中运行。
# 只管理本项目命名的规则，不关闭防火墙，不修改其他规则。
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Remove,
    [string]$ProxyExe = '',
    [string]$ConfigPath = ''
)
$ErrorActionPreference = 'Stop'
# 在参数解析完成后定位脚本目录，避免参数默认值求值时目录变量为空。
$scriptDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
    throw '无法确定脚本目录，请使用 powershell.exe -File 运行此文件。'
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $scriptDirectory 'settings.psd1'
}
$ruleName = 'Sonic-WindowsVpn-SOCKS5-HostOnly'
# 操作防火墙需要管理员权限；脚本不自行弹出提权窗口。
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '请右键 PowerShell，选择“以管理员身份运行”。'
}
if ($Remove) {
    if ($PSCmdlet.ShouldProcess($ruleName, '删除本项目防火墙规则')) {
        Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    }
    return
}
. (Join-Path $scriptDirectory 'Common.ps1')
$settings = Get-SocksSettings -ConfigPath $ConfigPath
if (-not $ProxyExe) { $ProxyExe = $settings.ProxyExe }
if (-not (Test-Path -LiteralPath $ProxyExe -PathType Leaf)) { throw "找不到程序：$ProxyExe" }
$ProxyExe = (Resolve-Path -LiteralPath $ProxyExe).Path
# 地址、来源、端口、程序四重限制；不开放 SOCKS UDP 转发。
if ($PSCmdlet.ShouldProcess($ruleName, '创建或更新允许列表客户端可访问的 TCP 入站规则')) {
    Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -Name $ruleName -DisplayName 'Sonic VPN SOCKS5（来源白名单）' `
        -Direction Inbound -Action Allow -Protocol TCP `
        -LocalAddress $settings.ListenAddress -LocalPort $settings.Port `
        -RemoteAddress $settings.AllowedClients -Program $ProxyExe -Profile Any | Out-Null
    Write-Host "已放行 $($settings.AllowedClients -join ", ") → $($settings.ListenAddress):$($settings.Port)（TCP）"
}
