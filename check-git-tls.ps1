#Requires -Version 5.1
<#
.SYNOPSIS
    检查 git 访问 GitHub 的 TLS 配置是否正常。

.DESCRIPTION
    本机 git 默认使用 schannel 后端时报
    "schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS"，
    切换为 openssl 后可正常访问。本脚本读取当前配置并做一次实际连通性测试。

    ls-remote 由 busybox 的 timeout 施加硬超时：git 自己的
    GIT_HTTP_LOW_SPEED_* 只约束低速传输时长，盖不住 DNS、TCP 与 TLS 握手阶段的挂起。

.PARAMETER Remote
    远端名（如 origin）或直接的仓库 URL，默认 origin。

.PARAMETER TimeoutSec
    连通性测试硬超时秒数，默认 30。

.EXAMPLE
    .\check-git-tls.ps1
    .\check-git-tls.ps1 -Remote https://github.com/owner/repo.git
#>
[CmdletBinding()]
param(
    [string]$Remote = 'origin',
    [ValidateRange(1, 3600)]
    [int]$TimeoutSec = 30
)

# 注意用 Continue 而不是 Stop：git 失败时会往 stderr 写内容，
# PS 5.1 在 Stop 下会把它升级为终止性错误，导致后面基于 $LASTEXITCODE 的
# 诊断分支根本执行不到。需要终止时在调用处显式 -ErrorAction Stop。
$ErrorActionPreference = 'Continue'

function Hide-Credential {
    <#
        抹掉 URL 里内嵌的 userinfo（user:token@），避免凭据进入终端或 CI 日志。
    #>
    param([AllowEmptyString()][string]$Url)

    if ([string]::IsNullOrEmpty($Url)) { return $Url }
    return ($Url -replace '(?<=://)[^/@]*(?=@)', '***')
}

function Get-TimeoutExe {
    <#
        返回带 timeout 语义的可执行文件。Git for Windows 的 usr\bin 里有 coreutils 版
        timeout.exe，语义与 busybox timeout 一致。
        （Git 用硬链接组织这些命令，busybox.exe 这个名字通常并不存在。）
    #>
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\usr\bin\timeout.exe'),
        (Join-Path $env:ProgramFiles 'Git\mingw64\bin\timeout.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host '[ERROR] 未找到 git，请确认已安装并已加入 PATH。'
    exit 2
}

# --- 当前 TLS 配置 ------------------------------------------------------
$globalBackend = ((git config --global http.sslBackend) -join '').Trim()
$localBackend = ((git config --local http.sslBackend) -join '').Trim()
$effective = if ($localBackend) { $localBackend } else { $globalBackend }

Write-Host '=== 当前 git TLS 配置 ==='
Write-Host ("全局 sslBackend  : {0}" -f $(if ($globalBackend) { $globalBackend } else { '(未设置，默认 schannel)' }))
Write-Host ("本仓库 sslBackend : {0}" -f $(if ($localBackend) { $localBackend } else { '(未设置)' }))
Write-Host ("生效值            : {0}" -f $(if ($effective) { $effective } else { 'schannel' }))

if ($effective -ne 'openssl') {
    Write-Host ''
    Write-Host '[WARN] 生效的不是 openssl。修复命令取决于本仓库是否覆盖了该值：'
    if ($localBackend) {
        Write-Host '       本仓库已单独设置，只改全局不会生效（本仓库的值优先）：'
        Write-Host '       git config --local http.sslBackend openssl'
    }
    else {
        Write-Host '       git config --global http.sslBackend openssl'
    }
}

# --- 解析远端 ----------------------------------------------------------
Write-Host ''
Write-Host '=== 远端 ==='
$looksLikeUrl = ($Remote -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') -or ($Remote -match '^[^/]+@[^/]+:')
if ($looksLikeUrl) {
    # 直接给了 URL（含 scp 风格的 user@host:path），无需查远端名
    Write-Host ("(直接使用 URL) -> {0}" -f (Hide-Credential $Remote))
}
else {
    $remoteUrl = ((git remote get-url $Remote 2>$null) -join '').Trim()
    if (-not $remoteUrl) {
        Write-Host ("[WARN] 远端 {0} 不存在。" -f $Remote)
        exit 1
    }
    # 输出前脱敏，避免内嵌 token 进入日志
    Write-Host ("{0} -> {1}" -f $Remote, (Hide-Credential $remoteUrl))
}

# --- 实际连通性测试（硬超时）-------------------------------------------
Write-Host ''
Write-Host '=== 连通性测试 ==='

$timeoutExe = Get-TimeoutExe
$stdoutFile = [System.IO.Path]::GetTempFileName()
$stderrFile = [System.IO.Path]::GetTempFileName()
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$exitCode = 0

# Git 自带的 timeout.exe 是 cygwin 程序，在受限沙箱里可能因
# "couldn't create signal pipe" 直接崩掉（退出码 0xC0000142 = -1073741502）。
# 那种情况下退回低速阈值方案，而不是把崩溃当成连通性失败。
$hardTimeoutUsable = [bool]$timeoutExe

if ($hardTimeoutUsable) {
    # 硬超时：DNS、TCP 连接、TLS 握手阶段挂起同样会被掐断
    & $timeoutExe $TimeoutSec git ls-remote $Remote HEAD 1> $stdoutFile 2> $stderrFile
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq -1073741502) {
        $hardTimeoutUsable = $false
        Write-Host "[WARN] timeout.exe 在当前环境无法启动（couldn't create signal pipe），"
        Write-Host '       退回低速阈值超时（无法覆盖连接与握手阶段的挂起）。'
        $exitCode = 0
    }
}

if (-not $hardTimeoutUsable) {
    if (-not $timeoutExe) {
        Write-Host '[WARN] 未找到 timeout.exe，退回低速阈值超时（无法覆盖连接与握手阶段的挂起）。'
    }
    $env:GIT_HTTP_LOW_SPEED_LIMIT = '1000'
    $env:GIT_HTTP_LOW_SPEED_TIME = "$TimeoutSec"
    git ls-remote $Remote HEAD 1> $stdoutFile 2> $stderrFile
    $exitCode = $LASTEXITCODE
}

$sw.Stop()

$stdout = @(Get-Content -LiteralPath $stdoutFile -ErrorAction SilentlyContinue)
$stderr = @(Get-Content -LiteralPath $stderrFile -ErrorAction SilentlyContinue)
Remove-Item $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue

# 124 是 timeout 命令的超时退出码
if ($exitCode -eq 124) {
    Write-Host ("[FAIL] 超过 {0} 秒未完成，已强制中止（远端不可达或网络挂起）。" -f $TimeoutSec)
    exit 1
}

if ($exitCode -eq 0) {
    # 只从 stdout 里按 40 位十六进制匹配 SHA，避免把 stderr 警告误当结果
    $sha = $null
    foreach ($line in $stdout) {
        if ($line -match '^([0-9a-f]{40})\s') {
            $sha = $Matches[1]
            break
        }
    }
    Write-Host ("[OK] 连通正常，耗时 {0} 秒" -f [math]::Round($sw.Elapsed.TotalSeconds, 1))
    if ($sha) {
        Write-Host ("     HEAD = {0}" -f $sha)
    }
    else {
        Write-Host '     [WARN] 未从输出中解析出 SHA，请手工确认。'
    }
    exit 0
}

Write-Host ("[FAIL] git ls-remote 失败（退出码 {0}），耗时 {1} 秒" -f $exitCode, [math]::Round($sw.Elapsed.TotalSeconds, 1))
foreach ($line in ($stderr + $stdout)) {
    Write-Host ("       {0}" -f $line)
}
exit 1
