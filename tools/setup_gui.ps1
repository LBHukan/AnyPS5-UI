$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$downloadDirectory = Join-Path $projectDirectory 'downloads'
New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null

function Get-VerifiedAsset {
    param([string]$AssetName, [string]$Destination, [string]$ExpectedHash)
    if (Test-Path -LiteralPath $Destination) {
        if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ieq $ExpectedHash) {
            return
        }
    }
    $temporaryAsset = "$Destination.download"
    Write-Host "Baixando $AssetName da release oficial v0.1.3..."
    Invoke-WebRequest -Uri "https://github.com/boykopovar/AnyPS5/releases/download/v0.1.3/$AssetName" -OutFile $temporaryAsset
    $actualHash = (Get-FileHash -LiteralPath $temporaryAsset -Algorithm SHA256).Hash
    if ($actualHash -ine $ExpectedHash) {
        throw "O SHA-256 de $AssetName difere do esperado. Download preservado em $temporaryAsset."
    }
    Move-Item -LiteralPath $temporaryAsset -Destination $Destination -Force
}

Get-VerifiedAsset -AssetName 'relinker-v0.1.3.exe' -Destination (Join-Path $downloadDirectory 'relinker.exe') -ExpectedHash 'c0de554bd426c35d3a38b67720879a0ec8dbdb06d89b0360442e45c7c268d021'
$runtimeArchive = Join-Path $downloadDirectory 'prx-windows-v0.1.3.zip'
Get-VerifiedAsset -AssetName 'prx-windows-v0.1.3.zip' -Destination $runtimeArchive -ExpectedHash 'a0d6ce41859368f7be43bb7ceefda8542f9abaaa80f16d157a1847287d46d0e0'
$runtimeDirectory = Join-Path $downloadDirectory 'runtime-windows'
if (!(Test-Path -LiteralPath (Join-Path $runtimeDirectory 'libs/libkernel.prx'))) {
    Expand-Archive -LiteralPath $runtimeArchive -DestinationPath $runtimeDirectory -Force
}
Write-Host 'Relinker e bibliotecas oficiais preparados.'
