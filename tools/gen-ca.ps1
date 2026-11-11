#Requires -Version 7.0
<#
.SYNOPSIS
    生成 Loon MitM 用的 CA 证书，输出 P12 base64 和 iOS 安装用的 .crt。

.DESCRIPTION
    生成一个自签名 CA（带 CA:TRUE 基本约束），导出为 PKCS#12，
    同时输出：
      - ca-p12 字段需要的单行 Base64
      - 供 iOS 安装的 .crt 文件

    ca-p12 含私钥。填进配置后不要提交到任何公开仓库。

.PARAMETER OutDir
    输出目录，默认当前目录下的 ca-out。

.PARAMETER Password
    P12 密码，会写进配置的 ca-passphrase 字段。

.PARAMETER CommonName
    证书 CN，装到 iOS 后「证书信任设置」里显示的就是这个名字。
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path (Get-Location).Path 'ca-out'),
    [string]$Password = 'weir-mitm',
    [string]$CommonName = 'Weir MitM CA',
    [int]$ValidYears = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

Write-Host "生成 CA：$CommonName" -ForegroundColor Cyan

# --- 密钥与证书请求 ---
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
$req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    "CN=$CommonName",
    $rsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

# 基本约束：这是 CA，可以签发下级证书
$req.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $false, 0, $true)
)

# 用途：签证书、签 CRL、数字签名
$req.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign -bor
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::CrlSign -bor
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,
        $true)
)

# 增强型密钥用法：TLS 服务端认证（MitM 用它假冒目标站）
$oids = [System.Security.Cryptography.OidCollection]::new()
[void]$oids.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'))
$req.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $false)
)

$cert = $req.CreateSelfSigned(
    [DateTimeOffset]::Now.AddDays(-1),
    [DateTimeOffset]::Now.AddYears($ValidYears)
)

# --- 导出 ---
$p12Path = Join-Path $OutDir 'ca.p12'
$crtPath = Join-Path $OutDir 'ca.crt'
$b64Path = Join-Path $OutDir 'ca-p12.base64.txt'

$p12Bytes = $cert.Export(
    [System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12,
    $Password
)
[System.IO.File]::WriteAllBytes($p12Path, $p12Bytes)

$crtBytes = $cert.Export(
    [System.Security.Cryptography.X509Certificates.X509ContentType]::Cert
)
[System.IO.File]::WriteAllBytes($crtPath, $crtBytes)

$b64 = [Convert]::ToBase64String($p12Bytes)
[System.IO.File]::WriteAllText($b64Path, $b64, [System.Text.UTF8Encoding]::new($false))

# --- 报告 ---
Write-Host ''
Write-Host '生成完成' -ForegroundColor Green
Write-Host ('-' * 64)
Write-Host ("证书 CN      : {0}" -f $CommonName)
Write-Host ("有效期       : {0} 年" -f $ValidYears)
Write-Host ("P12 文件     : {0}" -f $p12Path)
Write-Host ("安装用 crt   : {0}" -f $crtPath)
Write-Host ("base64 文件  : {0}" -f $b64Path)
Write-Host ("base64 长度  : {0} 字符" -f $b64.Length)
Write-Host ("P12 密码     : {0}" -f $Password)
Write-Host ('-' * 64)
Write-Host ''
Write-Host '接下来三件事：' -ForegroundColor Cyan
Write-Host '1. 把 ca.crt 传到 iPhone（AirDrop 或邮件），在「设置 → 通用 → VPN 与设备管理」安装'
Write-Host '2. 在「设置 → 通用 → 关于本机 → 证书信任设置」里打开这个证书的开关'
Write-Host '3. 把 ca-p12.base64.txt 的内容整行填进配置的 ca-p12，密码填 ca-passphrase'
Write-Host ''
Write-Host '注意：ca.p12 和 base64 文件都含私钥，不要提交到公开仓库。' -ForegroundColor Yellow
