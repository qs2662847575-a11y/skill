#Requires -Version 5.1
<#
.SYNOPSIS
    迁移后巡检本机 npm 全局安装与缓存配置。

.DESCRIPTION
    读取 npm 的 prefix / cache / root -g 配置，判断它们是否已落到目标盘，
    并统计旧位置仍占用的磁盘空间，便于确认迁移效果。

    退出码：0 表示三项配置均已在目标盘；1 表示存在未迁移项；
            2 表示 npm 不可用或读取配置失败；3 表示存在 npm_config_* 环境变量覆盖，结果不确定。

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
        return $null   # 路径不存在；与「存在但为空」返回 0 区分开
    }

    # 走管道逐对象累加以保持 O(1) 内存；
    # 注意不要改成 foreach 语句，foreach 会先把整棵树的 FileInfo 全部缓冲进内存
    # 跳过重解析点（junction/symlink），避免重复计算甚至无限递归
    $sum = 0
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) } |
        ForEach-Object { $sum += $_.Length }

    return [math]::Round($sum / 1MB, 1)
}

function Test-PathWithin {
    <#
        判断 $Child 是否真的位于 $Root 之内。
        直接对字符串做 StartsWith 会把 D:\x\skill-backup 误判为在 D:\x\skill 内，
        因此先把正斜杠统一成反斜杠，再在两侧补上目录分隔符后比较。
    #>
    param(
        [AllowEmptyString()][AllowNull()][Parameter(Mandatory)][string]$Root,
        [AllowEmptyString()][AllowNull()][Parameter(Mandatory)][string]$Child
    )

    # 空值或非法路径无法归一化，直接判为不在根目录内（而不是抛异常中断脚本）
    if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Child)) {
        return $false
    }

    try {
        # 先归一化为绝对路径（同时消掉相对路径、. 与 .. 片段），再统一分隔符方向。
        # 顺序很重要：先 GetFullPath 再补尾部分隔符，否则 `\..\..` 这类片段会被拼接破坏。
        # 括号必须保留：方法调用里的 `$x -replace '/','\'` 会被解析成两个参数
        $rootFull  = [System.IO.Path]::GetFullPath(($Root  -replace '/', '\'))
        $childFull = [System.IO.Path]::GetFullPath(($Child -replace '/', '\'))
    }
    catch {
        return $false
    }

    $rootWithSep  = $rootFull.TrimEnd('\') + '\'
    $childWithSep = $childFull.TrimEnd('\') + '\'

    return $childWithSep.StartsWith($rootWithSep, [StringComparison]::OrdinalIgnoreCase)
}

# --- 读取 npm 配置 ------------------------------------------------------
# npm 不在 PATH 时给出明确诊断，而不是让 CommandNotFoundException 直接终止脚本
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host '[ERROR] 未找到 npm，请确认已安装并已加入 PATH。'
    exit 2
}

# npm 输出可能带首尾空白或残留的 CR（.cmd shim 常见），一律 trim 后再比较
$prefix = ((npm config get prefix) -join '').Trim()
if ($LASTEXITCODE -ne 0) { Write-Host '[ERROR] npm config get prefix 执行失败。'; exit 2 }

$cache = ((npm config get cache) -join '').Trim()
if ($LASTEXITCODE -ne 0) { Write-Host '[ERROR] npm config get cache 执行失败。'; exit 2 }

$rootG = ((npm root -g) -join '').Trim()
if ($LASTEXITCODE -ne 0) { Write-Host '[ERROR] npm root -g 执行失败。'; exit 2 }

# npm_config_* 环境变量优先级高于 .npmrc：在 DSH 等会话中会把配置覆盖回旧路径，
# 此时下面读到的 prefix/cache 并不代表 .npmrc 的真实迁移状态。
$overrides = @(Get-ChildItem env: |
        Where-Object { $_.Name -like 'npm_config_*' -and $_.Name -match 'prefix|cache' } |
        ForEach-Object { "{0}={1}" -f $_.Name, $_.Value })

$legacyPrefix = if ($env:APPDATA) { Join-Path $env:APPDATA 'npm' } else { $null }
$legacyCache  = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'npm-cache' } else { $null }

# --- 输出 --------------------------------------------------------------
Write-Host '=== 当前 npm 配置 ==='
Write-Host ("prefix  : {0}" -f $prefix)
Write-Host ("cache   : {0}" -f $cache)
Write-Host ("root -g : {0}" -f $rootG)

Write-Host ''
Write-Host '=== 迁移状态 ==='

if ($overrides.Count -gt 0) {
    Write-Host '[WARN] 检测到 npm_config_* 环境变量覆盖，下列结果反映的是当前 shell 环境而非 .npmrc：'
    foreach ($o in $overrides) {
        Write-Host ("       {0}" -f $o)
    }
}

$allOnTarget = $true
foreach ($item in @(
        @{ Name = 'prefix';  Value = $prefix }
        @{ Name = 'cache';   Value = $cache  }
        @{ Name = 'root -g'; Value = $rootG  }
    )) {
    if (Test-PathWithin -Root $ExpectedRoot -Child $item.Value) {
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
    if (-not $dir) { continue }
    $size = Get-DirSizeMB -Path $dir
    if ($null -eq $size) {
        Write-Host ("{0} = 不存在" -f $dir)
        continue
    }
    $legacyTotal += $size
    Write-Host ("{0} = {1} MB" -f $dir, $size)
}
Write-Host ("合计 = {0} MB" -f [math]::Round($legacyTotal, 1))

# --- 目标位置占用 ------------------------------------------------------
Write-Host ''
Write-Host '=== 目标位置占用 ==='
$targetSize = Get-DirSizeMB -Path $ExpectedRoot
if ($null -eq $targetSize) {
    Write-Host ("{0} = 不存在" -f $ExpectedRoot)
}
else {
    Write-Host ("{0} = {1} MB" -f $ExpectedRoot, $targetSize)
}

if ($allOnTarget) {
    # 存在 npm_config_* 覆盖时，结论反映的是当前 shell 而非 .npmrc，
    # 用独立退出码 3 表达「不确定」，避免把环境问题误报成配置问题
    if ($overrides.Count -gt 0) {
        Write-Host '[INCONCLUSIVE] 结果受 npm_config_* 覆盖影响，无法代表 .npmrc 的真实状态。'
        exit 3
    }
    exit 0
}

exit 1
