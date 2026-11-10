# 一键入口：自动申请管理员权限，检查配置、更新防火墙并前台启动。
$ErrorActionPreference = 'Stop'
$scriptFile = $MyInvocation.MyCommand.Path
$base = Split-Path -Parent $scriptFile
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # 这是用户主动启动的交互窗口；UAC 需要用户确认。
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Normal -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $scriptFile + '"')) | Out-Null
    } catch { Write-Host "未能获得管理员权限：$_"; Read-Host '按 Enter 退出' }
    exit
}
try {
    . (Join-Path $base 'Common.ps1')
    $settings = Get-SocksSettings -ConfigPath (Join-Path $base 'settings.psd1')
    if (-not (Test-Path -LiteralPath $settings.ProxyExe)) { throw "程序不存在：$($settings.ProxyExe)" }
    if (-not (Get-NetIPAddress -AddressFamily IPv4 -IPAddress $settings.ListenAddress -ErrorAction SilentlyContinue)) { throw '监听 IP 不属于本机，请先配置虚拟机网卡。' }
    if (Get-NetTCPConnection -State Listen -LocalPort $settings.Port -ErrorAction SilentlyContinue) { throw '端口已有监听，请关闭旧代理后重试。' }
    & (Join-Path $base 'Set-Firewall.ps1')
    & (Join-Path $base 'Start-Socks5.ps1')
} catch { Write-Host "启动失败：$_" -ForegroundColor Red }
Read-Host '代理已停止，按 Enter 关闭窗口'
