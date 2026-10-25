param(
    [string]$OutputDirectory = '',
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$') {
    throw 'Versao invalida.'
}
$projectDirectory = Split-Path -Parent $PSScriptRoot
if (!$OutputDirectory) { $OutputDirectory = Join-Path $projectDirectory 'dist' }
$buildDirectory = Join-Path $projectDirectory 'gui/build/windows/x64/runner/Release'
foreach ($required in @('anyps5_gui.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat')) {
    if (!(Test-Path -LiteralPath (Join-Path $buildDirectory $required))) {
        throw "Build incompleto: $required. Execute flutter build windows --release na pasta gui."
    }
}
& (Join-Path $PSScriptRoot 'setup_gui.ps1')
$packageName = "AnyPS5-Studio-$Version-windows-x64"
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$archive = Join-Path $OutputDirectory "$packageName.zip"
if (Test-Path -LiteralPath $archive) { throw "O pacote ja existe: $archive" }
$stage = Join-Path $OutputDirectory "$packageName-stage-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $stage | Out-Null
Get-ChildItem -LiteralPath $buildDirectory | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stage -Recurse
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (!(Test-Path -LiteralPath $vswhere)) { throw 'vswhere nao encontrado para localizar o runtime C++ redistribuivel.' }
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$redistVersionFile = Join-Path $visualStudio 'VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt'
$redistVersion = (Get-Content -LiteralPath $redistVersionFile -Raw).Trim()
$redistDirectory = Join-Path $visualStudio "VC/Redist/MSVC/$redistVersion/x64"
$crt = Get-ChildItem -LiteralPath $redistDirectory -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
if (!$crt) { throw "Runtime C++ nao encontrado: $redistDirectory" }
foreach ($required in @('vcruntime140.dll', 'msvcp140.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $crt.FullName $required))) { throw "Runtime C++ incompleto: $required" }
}
Get-ChildItem -LiteralPath $crt.FullName -Filter '*.dll' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stage
}
$downloads = Join-Path $stage 'downloads'
New-Item -ItemType Directory -Path $downloads | Out-Null
Copy-Item -LiteralPath (Join-Path $projectDirectory 'downloads/relinker.exe') -Destination $downloads
Copy-Item -LiteralPath (Join-Path $projectDirectory 'downloads/runtime-windows') -Destination $downloads -Recurse
New-Item -ItemType Directory -Path (Join-Path $stage 'docs') | Out-Null
Copy-Item -LiteralPath (Join-Path $projectDirectory 'docs/user') -Destination (Join-Path $stage 'docs') -Recurse
Copy-Item -LiteralPath (Join-Path $projectDirectory 'LICENSE') -Destination $stage
@'
@echo off
cd /d "%~dp0"
start "" "%~dp0anyps5_gui.exe"
'@ | Set-Content -LiteralPath (Join-Path $stage 'Iniciar AnyPS5.cmd') -Encoding ascii
@"
AnyPS5 Studio $Version - Windows x64

Extraia TODO o ZIP para uma pasta e abra Iniciar AnyPS5.cmd ou anyps5_gui.exe.
Nao e necessario instalar Flutter, Visual Studio ou Python.

O pacote inclui a interface Flutter, o runtime C++ redistribuivel e os binarios
oficiais AnyPS5 v0.1.3. Nao inclui jogos, firmware ou chaves.
Selecione seu ELF, configure a saida e clique em Converter executavel.
Prepare libs/ com o botao de copiar bibliotecas e coloque os recursos originais
do titulo em app0/, ao lado da saida. A compatibilidade depende do AnyPS5.
Consulte docs/user/USAGE.md e docs/user/INPUT_MAPPING.md para detalhes.

Codigo-fonte da interface e licenca GPL-2.0:
https://github.com/LBHukan/AnyPS5-UI/tree/gui-v$Version
Codigo-fonte dos binarios oficiais incluidos:
https://github.com/boykopovar/AnyPS5/tree/v0.1.3
Licencas do Flutter e dependencias: data/flutter_assets/NOTICES.Z
"@ | Set-Content -LiteralPath (Join-Path $stage 'LEIAME.txt') -Encoding utf8
$sourceCommit = git -C $projectDirectory rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel identificar o commit de origem.' }
"AnyPS5 Studio $Version`nSource commit: $sourceCommit`nAnyPS5 runtime: v0.1.3" | Set-Content -LiteralPath (Join-Path $stage 'VERSION.txt') -Encoding ascii
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $archive, [System.IO.Compression.CompressionLevel]::Optimal, $false)
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $packageName.zip" | Set-Content -LiteralPath (Join-Path $OutputDirectory "$packageName.sha256.txt") -Encoding ascii
Write-Host "Pacote criado: $archive"
Write-Host "SHA-256: $hash"
