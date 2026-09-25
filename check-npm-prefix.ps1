#Requires -Version 5.1
<#
.SYNOPSIS
    迁移后巡检本机 npm 全局安装与缓存配置。

.DESCRIPTION
    读取 npm 的 prefix / cache / root -g 配置，判断它们是否已落到目标盘，
    并统计旧位置仍占用的磁盘空间，便于确认迁移效果。

.PARAMETER ExpectedRoot
    期望的根目录，默认 D:\大模型\skill。

.EXAMPLE
    .\check-npm-prefix.ps1
    .\check-npm-prefix.ps1 -ExpectedRoot 'D:\npm'
#>
[CmdletBinding()]
param(
    [string]$ExpectedRoot = 'D:\大模型\skill'
)

$ErrorActionPreference = 'Stop'

function Get-DirSizeMB {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum

    if ($null -eq $sum) {
        return 0
    }

    return [math]::Round($sum / 1MB, 1)
}

function Get-TreeSizeMB {
    param([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return 0
    }

    $total = 0
    foreach ($child in Get-ChildItem -LiteralPath $Root -Force -Directory -ErrorAction SilentlyContinue) {
        $total += Get-DirSizeMB -Path $child.FullName
    }

    return [math]::Round($total, 1)
}

# --- 读取 npm 配置 ------------------------------------------------------
$prefix = (npm config get prefix) -join ''
$cache  = (npm config get cache) -join ''
$rootG  = (npm root -g) -join ''

$legacyPrefix = Join-Path $env:APPDATA 'npm'
$legacyCache  = Join-Path $env:LOCALAPPDATA 'npm-cache'

# --- 输出 --------------------------------------------------------------
Write-Host '=== 当前 npm 配置 ==='
Write-Host ("prefix  : {0}" -f $prefix)
Write-Host ("cache   : {0}" -f $cache)
Write-Host ("root -g : {0}" -f $rootG)

Write-Host ''
Write-Host '=== 迁移状态 ==='
$allOnTarget = $true
foreach ($item in @(
        @{ Name = 'prefix'; Value = $prefix }
        @{ Name = 'cache';  Value = $cache  }
    )) {
    if ($item.Value.StartsWith($ExpectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("[OK]   {0} 已在 {1}" -f $item.Name, $ExpectedRoot)
    }
    else {
        Write-Host ("[WARN] {0} 不在 {1}，实际为 {2}" -f $item.Name, $ExpectedRoot, $item.Value)
        $allOnTarget = $false
    }
}

# --- 旧位置占用 --------------------------------------------------------
Write-Host ''
Write-Host '=== 旧位置占用 ==='
$legacyTotal = 0
foreach ($dir in @($legacyPrefix, $legacyCache)) {
    $size = Get-DirSizeMB -Path $dir
    $legacyTotal += $size
    Write-Host ("{0} = {1} MB" -f $dir, $size)
}
Write-Host ("合计 = {0} MB" -f [math]::Round($legacyTotal, 1))

# --- 目标位置占用 ------------------------------------------------------
Write-Host ''
Write-Host '=== 目标位置占用 ==='
Write-Host ("{0} = {1} MB" -f $ExpectedRoot, (Get-TreeSizeMB -Root $ExpectedRoot))

if ($allOnTarget) {
    exit 0
}

exit 1
