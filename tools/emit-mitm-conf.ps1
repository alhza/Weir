#Requires -Version 7.0
<#
.SYNOPSIS
    把生成的 CA 证书嵌入配置模板，输出一份可直接导入的完整配置。

.DESCRIPTION
    仓库里的配置模板 ca-p12 是空的，因为 P12 含私钥，不可能公开提交。
    这个脚本把本机生成的证书填进去，产出一份只供自己用的配置。

    输出文件默认落在 ca-out/ 下，已被 .gitignore 排除。
    要放到手机上，把这个文件上传到自己的私有 Gist，或者用文件 App 打开。

.PARAMETER Base64File
    证书 base64 文件，由 gen-ca.ps1 生成。

.PARAMETER Template
    配置模板，默认 conf/loon.mitm.conf。

.PARAMETER Password
    P12 密码，必须与生成时一致，否则 Loon 解不开证书。

.PARAMETER Out
    输出路径。
#>
[CmdletBinding()]
param(
    [string]$Base64File = (Join-Path (Get-Location).Path 'ca-out/ca-p12.base64.txt'),
    [string]$Template   = (Join-Path (Get-Location).Path 'conf/loon.mitm.conf'),
    [string]$Password   = 'weir-mitm',
    [string]$Out        = (Join-Path (Get-Location).Path 'ca-out/loon-configured.conf')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Base64File)) {
    throw "找不到证书文件: $Base64File`n先跑 tools/gen-ca.ps1 生成证书。"
}
if (-not (Test-Path -LiteralPath $Template)) {
    throw "找不到配置模板: $Template"
}

$b64 = [System.IO.File]::ReadAllText($Base64File).Trim()
if ($b64.Length -lt 100) { throw "证书文件内容不像 Base64（长度 $($b64.Length)）" }

# 自检：解一次，确认是有效 P12 且带私钥
try {
    $raw   = [Convert]::FromBase64String($b64)
    $cert  = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($raw, $Password)
    if (-not $cert.HasPrivateKey) { throw 'P12 里没有私钥，Loon 无法用它签发证书' }
} catch {
    throw "证书自检失败：$($_.Exception.Message)`n密码多半和生成时不一致。"
}

$cfg = [System.IO.File]::ReadAllText($Template)

# 替换 ca-p12：整行换成单行 base64
$cfg = [regex]::Replace($cfg, '(?m)^ca-p12\s*=.*$', "ca-p12 = $b64")
# 替换 ca-passphrase
$cfg = [regex]::Replace($cfg, '(?m)^ca-passphrase\s*=.*$', "ca-passphrase = $Password")

$head = @(
    '# ============================================================',
    '#  已嵌入 CA 证书的配置，含私钥。',
    "#  CN: $($cert.Subject)   有效期至: $($cert.NotAfter.ToString('yyyy-MM-dd'))",
    '#  不要提交、不要分享、不要公开托管。',
    '# ============================================================',
    ''
) -join "`n"

$dir = Split-Path -Parent $Out
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllText($Out, $head + $cfg, [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host '嵌入完成' -ForegroundColor Green
Write-Host ('-' * 64)
Write-Host ("证书     : {0}" -f $cert.Subject)
Write-Host ("有效期至 : {0:yyyy-MM-dd}" -f $cert.NotAfter)
Write-Host ("带私钥   : {0}" -f $cert.HasPrivateKey)
Write-Host ("hostname : {0}" -f (($cfg | Select-String -Pattern '(?m)^hostname\s*=\s*(.*)$').Matches.Groups[1].Value))
Write-Host ("输出     : {0}" -f $Out)
Write-Host ('-' * 64)
Write-Host ''
Write-Host '下一步：把这个文件传到手机，用 Loon 打开导入。' -ForegroundColor Cyan
Write-Host '别忘了先在 iOS 上装 ca.crt 并在「证书信任设置」里打开开关。'
Write-Host ''
Write-Host '这个文件含私钥，不要提交到仓库，.gitignore 已排除 ca-out/。' -ForegroundColor Yellow
