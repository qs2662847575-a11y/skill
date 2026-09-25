#Requires -Version 5.1
<#
.SYNOPSIS
    检查 git 访问 GitHub 的 TLS 配置是否正常。

.DESCRIPTION
    本机 git 默认使用 schannel 后端时报
    "schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS"，
    切换为 openssl 后可正常访问。本脚本读取当前配置并做一次实际连通性测试。

.PARAMETER Remote
    要测试的远端名或 URL，默认 origin。

.PARAMETER TimeoutSec
    连通性测试超时秒数，默认 30。

.EXAMPLE
    .\check-git-tls.ps1
    .\check-git-tls.ps1 -Remote origin -TimeoutSec 60
#>
[CmdletBinding()]
param(
    [string]$Remote = 'origin',
    [int]$TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host '[ERROR] 未找到 git，请确认已安装并已加入 PATH。'
    exit 2
}

# --- 当前 TLS 配置 ------------------------------------------------------
$globalBackend = (git config --global http.sslBackend) -join ''
$localBackend = (git config --local http.sslBackend) -join ''
$effective = if ($localBackend) { $localBackend } else { $globalBackend }

Write-Host '=== 当前 git TLS 配置 ==='
Write-Host ("全局 sslBackend : {0}" -f $(if ($globalBackend) { $globalBackend } else { '(未设置，默认 schannel)' }))
Write-Host ("本仓库 sslBackend: {0}" -f $(if ($localBackend) { $localBackend } else { '(未设置)' }))
Write-Host ("生效值           : {0}" -f $(if ($effective) { $effective } else { 'schannel' }))

if ($effective -ne 'openssl') {
    Write-Host ''
    Write-Host '[WARN] 生效的不是 openssl。若访问 GitHub 报 SEC_E_NO_CREDENTIALS，执行：'
    Write-Host '       git config --global http.sslBackend openssl'
}

# --- 远端配置 ----------------------------------------------------------
Write-Host ''
Write-Host '=== 远端 ==='
$remoteUrl = (git remote get-url $Remote 2>$null) -join ''
if (-not $remoteUrl) {
    Write-Host ("[WARN] 远端 {0} 不存在。" -f $Remote)
    exit 1
}
Write-Host ("{0} -> {1}" -f $Remote, $remoteUrl)

# --- 实际连通性测试 ----------------------------------------------------
Write-Host ''
Write-Host '=== 连通性测试 ==='
$env:GIT_HTTP_LOW_SPEED_LIMIT = '1000'
$env:GIT_HTTP_LOW_SPEED_TIME = "$TimeoutSec"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$output = git ls-remote $Remote HEAD 2>&1
$exitCode = $LASTEXITCODE
$sw.Stop()

if ($exitCode -eq 0) {
    $sha = ($output | Select-Object -First 1) -split '\s+' | Select-Object -First 1
    Write-Host ("[OK] 连通正常，耗时 {0} 秒" -f [math]::Round($sw.Elapsed.TotalSeconds, 1))
    Write-Host ("     HEAD = {0}" -f $sha)
    exit 0
}

Write-Host ("[FAIL] git ls-remote 失败（退出码 {0}），耗时 {1} 秒" -f $exitCode, [math]::Round($sw.Elapsed.TotalSeconds, 1))
foreach ($line in $output) {
    Write-Host ("       {0}" -f $line)
}
exit 1
