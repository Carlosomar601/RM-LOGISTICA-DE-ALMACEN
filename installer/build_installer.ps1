# Genera installer\Output\RMLogistics-Setup-<version>.exe (instalador fuera de línea).
#   powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1 [-SkipBuild]
# Internet solo se usa aquí, la primera vez, para descargar el runtime de Visual C++ y WinSW.
# Incluye la app (cliente) y el servidor (rm_server.exe + servicio de Windows).
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$version = (Select-String -Path "$root\pubspec.yaml" -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
Write-Host "Versión $version"

# 1) Compilación release de Windows.
if (-not $SkipBuild) {
    $flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
    if (-not $flutter) { $flutter = 'D:\FLUTTER SDK\flutter\bin\flutter.bat' }
    Push-Location $root
    try {
        & $flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows falló ($LASTEXITCODE)" }
    } finally { Pop-Location }
}
$exe = "$root\build\windows\x64\runner\Release\piqueo_fifo_centeno.exe"
if (-not (Test-Path $exe)) { throw "No existe $exe; ejecuta sin -SkipBuild." }

# 1b) Servidor (Dart AOT, sin dependencias). La versión sale de pubspec.yaml de la app.
$serverExe = "$root\build\server\rm_server.exe"
if (-not $SkipBuild) {
    $flutterCmd = (Get-Command flutter -ErrorAction SilentlyContinue).Source
    $flutterBin = if ($flutterCmd) { Split-Path $flutterCmd } else { 'D:\FLUTTER SDK\flutter\bin' }
    $dart = Join-Path $flutterBin 'dart.bat'
    # UTF-8 sin BOM (Set-Content de PowerShell 5.1 agrega BOM).
    [IO.File]::WriteAllLines("$root\server\lib\version.dart", [string[]]@(
        '/// Versión del servidor (la escribe build_installer.ps1 desde pubspec.yaml de la app).',
        "const kServerVersion = '$version';"), (New-Object Text.UTF8Encoding $false))
    Push-Location "$root\server"
    try {
        & $dart pub get
        if ($LASTEXITCODE -ne 0) { throw "dart pub get (servidor) falló ($LASTEXITCODE)" }
        New-Item -ItemType Directory -Force (Split-Path $serverExe) | Out-Null
        & $dart compile exe bin\rm_server.dart -o $serverExe
        if ($LASTEXITCODE -ne 0) { throw "dart compile exe (servidor) falló ($LASTEXITCODE)" }
    } finally { Pop-Location }
}
if (-not (Test-Path $serverExe)) { throw "No existe $serverExe; ejecuta sin -SkipBuild." }

# 1c) WinSW 2.12.0: registra el servidor como servicio de Windows. No viene firmado, así que se
#     verifica su SHA-256 (de la publicación oficial https://github.com/winsw/winsw/releases/tag/v2.12.0).
$winsw = "$PSScriptRoot\redist\WinSW-x64.exe"
$winswSha256 = '05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA'
if (-not (Test-Path $winsw)) {
    New-Item -ItemType Directory -Force (Split-Path $winsw) | Out-Null
    Write-Host 'Descargando WinSW-x64.exe 2.12.0 (solo la primera vez)...'
    Invoke-WebRequest 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe' -OutFile $winsw
}
$got = (Get-FileHash $winsw -Algorithm SHA256).Hash
if ($got -ne $winswSha256) {
    Remove-Item $winsw -Force
    throw "WinSW-x64.exe no coincide con el SHA-256 esperado (llegó $got). Se borró; vuelve a ejecutar."
}

# 2) Runtime de Visual C++ (se empaqueta dentro del instalador).
$redist = "$PSScriptRoot\redist\VC_redist.x64.exe"
if (-not (Test-Path $redist)) {
    New-Item -ItemType Directory -Force (Split-Path $redist) | Out-Null
    Write-Host 'Descargando VC_redist.x64.exe de Microsoft (solo la primera vez)...'
    Invoke-WebRequest 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $redist
}
$sig = Get-AuthenticodeSignature $redist
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
    throw "VC_redist.x64.exe no tiene una firma válida de Microsoft ($($sig.Status))."
}

# 3) Compilador de Inno Setup 6.
$candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
                 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1') {
    $loc = (Get-ItemProperty $key -ErrorAction SilentlyContinue).InstallLocation
    if ($loc) { $candidates += (Join-Path $loc 'ISCC.exe') }
}
$iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'No se encontró Inno Setup 6 (ISCC.exe). Instálalo: winget install JRSoftware.InnoSetup' }

& $iscc "/DAppVersion=$version" "$PSScriptRoot\piqueo_fifo.iss"
if ($LASTEXITCODE -ne 0) { throw "ISCC falló ($LASTEXITCODE)" }
Write-Host "Listo: $PSScriptRoot\Output\RMLogistics-Setup-$version.exe"
