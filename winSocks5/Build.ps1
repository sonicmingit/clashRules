param(
    [string]$EngineDirectory,
    [string]$EmbedEngine
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (!$EmbedEngine -and !$EngineDirectory) { $EmbedEngine = Join-Path $root 'bin\3proxy.exe' }
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$exe = Join-Path $root 'Socks5Manager.exe'
$icon = Join-Path $root 'Socks5Manager.ico'
$resources = @()
if ($EmbedEngine) {
    if ($EngineDirectory) { throw 'Choose either EmbedEngine or EngineDirectory.' }
    $engine = Get-Item -LiteralPath $EmbedEngine
    if ($engine.PSIsContainer -or $engine.Name -ne '3proxy.exe') { throw 'Select 3proxy.exe.' }
    $resources += "/resource:$($engine.FullName),Embedded.3proxy.exe"
    $resources += "/resource:$(Join-Path $root 'bin\LICENSE-3proxy.txt'),Embedded.3proxy.License"
    $exe = Join-Path $root 'Socks5Manager-embedded.exe'
}

Add-Type -AssemblyName System.Drawing
$stream = [System.IO.File]::Create($icon)
try { [System.Drawing.SystemIcons]::Shield.Save($stream) }
finally { $stream.Dispose() }

& "$framework\csc.exe" /nologo /target:winexe /platform:x64 "/out:$exe" "/win32icon:$icon" `
    "/r:$framework\WPF\PresentationFramework.dll" "/r:$framework\WPF\PresentationCore.dll" `
    "/r:$framework\WPF\WindowsBase.dll" /r:System.Xaml.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll `
    @resources (Join-Path $root 'Manager.cs')
if ($LASTEXITCODE -ne 0) { throw 'C# compilation failed.' }

$files = @($exe, (Join-Path $root 'README.md'))
$archive = 'Socks5Manager-win-x64.zip'
if ($EmbedEngine) {
    $files += Join-Path $root 'bin\LICENSE-3proxy.txt'
    $archive = 'Socks5Manager-embedded-win-x64.zip'
}
if ($EngineDirectory) {
    $bin = Get-Item -LiteralPath $EngineDirectory
    if (!$bin.PSIsContainer -or $bin.Name -ne 'bin' -or
        !(Test-Path -LiteralPath (Join-Path $bin.FullName '3proxy.exe') -PathType Leaf)) {
        throw 'EngineDirectory must be a bin directory containing 3proxy.exe, its runtime dependencies and upstream license notices.'
    }
    $files += $bin.FullName
    $archive = 'Socks5Manager-with-3proxy-win-x64.zip'
}
$temporaryArchive = Join-Path $root ([guid]::NewGuid().ToString('N') + '.zip')
try {
    Compress-Archive -LiteralPath $files -DestinationPath $temporaryArchive
    Move-Item -LiteralPath $temporaryArchive -Destination (Join-Path $root $archive) -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryArchive) { Remove-Item -LiteralPath $temporaryArchive }
}
