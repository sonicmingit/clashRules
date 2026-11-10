# 共享配置读取、校验和 3proxy 配置生成逻辑。
function Get-SocksSettings {
    param([string]$ConfigPath)
    if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'settings.psd1' }
    $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    $base = Split-Path -Parent $ConfigPath
    # 数据文件不允许任意脚本执行；不使用 Invoke-Expression。
    $data = Import-PowerShellDataFile -LiteralPath $ConfigPath
    $checkAddress = {
        param([string]$Value, [bool]$AllowNetwork)
        $items = $Value.Split('/')
        if ($items.Count -gt 2 -or (-not $AllowNetwork -and $items.Count -gt 1)) { throw "无效地址：$Value" }
        $parts = $items[0].Split('.')
        if ($parts.Count -ne 4 -or @($parts | Where-Object {
            $_ -notmatch '^(0|[1-9][0-9]{0,2})$' -or [int]$_ -gt 255
        }).Count) { throw "无效 IPv4：$Value" }
        if ([int]$parts[0] -eq 0 -or [int]$parts[0] -eq 127 -or [int]$parts[0] -ge 224) { throw "不支持的地址：$Value" }
        if ($items.Count -eq 2 -and ($items[1] -notmatch '^[0-9]{1,2}$' -or [int]$items[1] -gt 32)) { throw "无效网段：$Value" }
    }
    & $checkAddress ([string]$data.ListenAddress) $false
    if ($data.Port -isnot [int] -or $data.Port -lt 1 -or $data.Port -gt 65535) { throw 'Port 必须是 1～65535 的整数。' }
    $clients = @($data.AllowedClients | Select-Object -Unique)
    if (-not $clients.Count) { throw 'AllowedClients 不能为空。' }
    foreach ($client in $clients) { & $checkAddress ([string]$client) $true }
    if ($data.EnableLogging -isnot [bool]) { throw 'EnableLogging 必须为 $true 或 $false。' }
    if ($data.LogRetention -isnot [int] -or $data.LogRetention -lt 1 -or $data.LogRetention -gt 3650) { throw 'LogRetention 必须为 1～3650。' }
    # 日志目录限定为本目录下的 ASCII 相对路径，避免配置指令注入和中文路径兼容问题。
    if ($data.LogDirectory -notmatch '^[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*$') { throw 'LogDirectory 请使用如 logs 或 logs/socks 的相对目录。' }
    if ([string]::IsNullOrWhiteSpace($data.ProxyExe)) { throw 'ProxyExe 不能为空。' }
    $exe = [string]$data.ProxyExe
    if (-not [IO.Path]::IsPathRooted($exe)) { $exe = Join-Path $base $exe }
    [pscustomobject]@{ ListenAddress=[string]$data.ListenAddress; Port=$data.Port;
        AllowedClients=$clients; ProxyExe=$exe; BaseDirectory=$base;
        EnableLogging=$data.EnableLogging; LogDirectory=$data.LogDirectory; LogRetention=$data.LogRetention }
}
function New-SocksRuntimeConfig {
    param([Parameter(Mandatory=$true)]$Settings)
    $dir = Join-Path $Settings.BaseDirectory 'runtime'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $lines = @('# Generated from settings.psd1; do not edit.')
    if ($Settings.EnableLogging) {
        New-Item -ItemType Directory -Path (Join-Path $Settings.BaseDirectory $Settings.LogDirectory) -Force | Out-Null
        $lines += ('log "{0}/socks.log" D' -f $Settings.LogDirectory)
        $lines += ('rotate {0}' -f $Settings.LogRetention)
        # 分号分隔：本地时间、服务、错误、来源、实际目标、上行/下行字节、耗时、请求域名。
        $lines += 'logformat "L%Y-%m-%d %H:%M:%S;%N;%E;%C:%c;%R:%r;%O;%I;%D;%n"'
    }
    $lines += 'auth iponly'
    # ACL 与防火墙使用同一份来源列表，只允许 TCP CONNECT，不开放 UDP/BIND。
    foreach ($client in $Settings.AllowedClients) { $lines += "allow * $client * * CONNECT" }
    $lines += 'deny *'
    $lines += "socks -p$($Settings.Port) -i$($Settings.ListenAddress)"
    $target = Join-Path $dir '3proxy.cfg'
    [IO.File]::WriteAllLines($target, [string[]]$lines, [Text.Encoding]::ASCII)
    $target
}
