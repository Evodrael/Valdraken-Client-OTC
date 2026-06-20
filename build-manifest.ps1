<#
.SYNOPSIS
    Gera o manifest.json do client a partir da raiz do repositorio.

.DESCRIPTION
    Para cada arquivo registra: caminho relativo (com '/'), SHA256 (minusculo) e tamanho.
    A versao do manifest e lida de version.txt (ex.: 15.24.01).

    Uso tipico (fluxo de release, sem bot / sem conflito de merge):
        1. Edite os arquivos do client.
        2. Suba a versao em version.txt  (ex.: 15.24.00 -> 15.24.01).
        3. Rode este script:   powershell -ExecutionPolicy Bypass -File .\build-manifest.ps1
        4. git add -A; git commit -m "client 15.24.01"; git push   (um unico push).

    Funciona em Windows PowerShell 5.1 e PowerShell 7+ (pwsh), por isso tambem
    serve para a Action de validacao em .github/workflows/.
#>

[CmdletBinding()]
param(
    # Se informado, apenas valida que o manifest.json atual esta atualizado
    # (nao escreve nada). Sai com codigo 1 se estiver desatualizado.
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

# Raiz = pasta onde este script esta.
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

# Pastas (no inicio do caminho relativo) e arquivos que NAO fazem parte do client.
$excludeDirPrefixes = @('.git/', '.github/')
$excludeNames = @(
    'manifest.json',
    'build-manifest.ps1',
    'launcher.log',
    'otclient.log',
    '.launcher_cache.json',
    '.installed_version',
    'config.json',
    'otclientrc.lua',
    'ValdrakenLauncher.exe',
    'ValdrakenLauncher.pdb'
)

# Versao legivel lida de version.txt (cai para timestamp se o arquivo nao existir).
$versionFile = Join-Path $root 'version.txt'
if (Test-Path $versionFile) {
    $version = (Get-Content -Path $versionFile -Raw).Trim()
} else {
    $version = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    Write-Warning "version.txt nao encontrado; usando timestamp '$version'."
}

$rootLen = $root.Length + 1
$files = New-Object System.Collections.Generic.List[object]

Get-ChildItem -Path $root -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($rootLen).Replace('\', '/')

    foreach ($p in $excludeDirPrefixes) {
        if ($rel.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    }
    if ($excludeNames -contains $_.Name) { return }

    $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLower()
    $files.Add([ordered]@{
        path   = $rel
        sha256 = $hash
        size   = $_.Length
    })
}

$sorted = $files | Sort-Object { $_.path } -Culture ([System.Globalization.CultureInfo]::InvariantCulture)

$manifest = [ordered]@{
    version   = $version
    generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:sszzz')
    count     = $sorted.Count
    files     = @($sorted)
}

$json = $manifest | ConvertTo-Json -Depth 6
$manifestPath = Join-Path $root 'manifest.json'

if ($Check) {
    # Validacao: compara a lista de arquivos (path/sha256/size) ignorando
    # formatacao e o campo 'generated'. Nao escreve nada.
    if (-not (Test-Path $manifestPath)) {
        Write-Error "manifest.json nao existe."
        exit 1
    }
    $current = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $a = $current.files | Sort-Object path | ForEach-Object { "$($_.path)|$($_.sha256)|$($_.size)" }
    $b = $sorted        | ForEach-Object { "$($_.path)|$($_.sha256)|$($_.size)" }
    $diff = Compare-Object -ReferenceObject @($a) -DifferenceObject @($b)
    if ($diff -or $current.version -ne $version) {
        Write-Error "manifest.json esta DESATUALIZADO. Rode .\build-manifest.ps1 e commite o resultado."
        exit 1
    }
    Write-Host "OK: manifest.json esta atualizado ($($sorted.Count) arquivos, versao $version)."
    exit 0
}

# PS 5.1 grava UTF-16 por padrao; forcamos UTF-8 sem BOM.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, $json, $utf8NoBom)

Write-Host "Manifest gerado: $($sorted.Count) arquivos, versao $version."
