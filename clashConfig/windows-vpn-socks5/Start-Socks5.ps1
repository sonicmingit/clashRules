# 在登录 aTrust 的 Windows 虚拟机内运行，不要在宿主机运行。
# 前台启动：关闭当前窗口或按 Ctrl+C 即停止；不安装服务或计划任务。
[CmdletBinding()]
param(
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
. (Join-Path $scriptDirectory 'Common.ps1')
$settings = Get-SocksSettings -ConfigPath $ConfigPath
if (-not $ProxyExe) { $ProxyExe = $settings.ProxyExe }
if (-not (Test-Path -LiteralPath $ProxyExe -PathType Leaf)) {
    throw "找不到 3proxy.exe：$ProxyExe。请从官方发布页下载 Windows 版本，或通过 -ProxyExe 指定位置。"
}
$ProxyExe = (Resolve-Path -LiteralPath $ProxyExe).Path
# 验证监听 IP 确实属于当前虚拟机；不自动修改网卡、网关或 VPN 路由。
if (-not (Get-NetIPAddress -AddressFamily IPv4 -IPAddress $settings.ListenAddress -ErrorAction SilentlyContinue)) {
    throw "本机不存在地址 $($settings.ListenAddress)，请先配置虚拟机 VMnet11 网卡。"
}
if (Get-NetTCPConnection -State Listen -LocalPort $settings.Port -ErrorAction SilentlyContinue) {
    throw "TCP 端口 $($settings.Port) 已有监听，请确认是否已启动代理。"
}
Write-Host "启动 SOCKS5：$($settings.ListenAddress):$($settings.Port)"
Write-Host "仅允许宿主机 $($settings.AllowedClients -join ", ")；出口遵循 Windows/VPN 路由，不保证强制走 VPN。"
# 使用独立配置文件参数；调用运算符能正确处理带空格的路径。
$runtimeConfig = New-SocksRuntimeConfig -Settings $settings
# 日志相对路径以配置目录为基准，确保从任意工作目录启动都正确。
Push-Location $settings.BaseDirectory
try { & $ProxyExe $runtimeConfig } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { throw "3proxy 异常退出，退出码：$LASTEXITCODE" }
