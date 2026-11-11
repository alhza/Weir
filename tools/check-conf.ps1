#Requires -Version 7.0
<#
.SYNOPSIS
    静态检查 Loon 配置文件。三层：结构、契约、语义。

.DESCRIPTION
    结构层：段是否完整、FINAL 是否在最后、占位符是否残留。
    契约层：policy.json 里的策略名与 [Proxy Group] 是否对齐、规则引用的策略是否存在。
    语义层：[General] 参数之间的因果链是否自相矛盾（FakeIP/real-ip、ipv6/ip-mode、block-quic/udp、两条路径覆盖）。

.PARAMETER Conf
    要检查的配置文件，默认 conf/loon.conf。

.PARAMETER Policy
    策略映射文件，默认 policy.json。
#>
[CmdletBinding()]
param(
    # 脚本放在 _dev/ 下，仓库根取上一级。
    [string]$Conf   = (Join-Path (Split-Path -Parent $PSScriptRoot) 'conf/loon.conf'),
    [string]$Policy = (Join-Path (Split-Path -Parent $PSScriptRoot) 'policy.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
$warns  = [System.Collections.Generic.List[string]]::new()
$notes  = [System.Collections.Generic.List[string]]::new()

function Add-Err([string]$m)  { $script:errors.Add($m) }
function Add-Warn([string]$m) { $script:warns.Add($m) }
function Add-Note([string]$m) { $script:notes.Add($m) }

if (-not (Test-Path -LiteralPath $Conf))   { throw "找不到配置文件: $Conf" }
if (-not (Test-Path -LiteralPath $Policy)) { throw "找不到策略文件: $Policy" }

# ---------- 解析 ----------
$raw = @(Get-Content -LiteralPath $Conf -Encoding utf8)

$sections = [ordered]@{}
$current  = '(root)'
$sections[$current] = [System.Collections.Generic.List[string]]::new()
$lineOf   = @{}   # 行内容 -> 行号，用于报错定位

for ($i = 0; $i -lt $raw.Count; $i++) {
    $text = $raw[$i]
    if ($text -match '^\s*\[(?<n>[^\]]+)\]\s*$') {
        $current = $Matches['n'].Trim()
        if (-not $sections.Contains($current)) {
            $sections[$current] = [System.Collections.Generic.List[string]]::new()
        }
        continue
    }
    $sections[$current].Add($text)
    $lineOf[$text] = $i + 1
}

$general = @(); if ($sections.Contains('General'))       { $general = $sections['General'] }
$proxies = @(); if ($sections.Contains('Proxy'))         { $proxies = $sections['Proxy'] }
$remote  = @(); if ($sections.Contains('Remote Proxy'))  { $remote  = $sections['Remote Proxy'] }
$groups  = @(); if ($sections.Contains('Proxy Group'))   { $groups  = $sections['Proxy Group'] }
$rules   = @(); if ($sections.Contains('Rule'))          { $rules   = $sections['Rule'] }
$rRules  = @(); if ($sections.Contains('Remote Rule'))   { $rRules  = $sections['Remote Rule'] }
$filters = @(); if ($sections.Contains('Remote Filter')) { $filters = $sections['Remote Filter'] }
$plugins = @(); if ($sections.Contains('Plugin'))        { $plugins = $sections['Plugin'] }
$mitm    = @(); if ($sections.Contains('Mitm'))          { $mitm    = $sections['Mitm'] }

# 组名 / 节点名
$groupByName = @{}      # 忽略大小写
$nodeByName  = @{}
foreach ($l in $groups) {
    $t = $l.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t -notmatch '^(?<name>[^=]+?)\s*=\s*(?<rest>.+)$') {
        Add-Err "[Proxy Group] 无法解析的行: $t"
        continue
    }
    $gname = $Matches['name'].Trim()
    $groupByName[$gname.ToLowerInvariant()] = $gname
    $gtype = @($Matches['rest'].Split(',') | ForEach-Object { $_.Trim() })[0]
    if ($gtype -notin @('select', 'url-test', 'fallback', 'load-balance', 'ssid')) {
        Add-Warn "策略组 '$gname' 的类型 '$gtype' 未识别（已知 select / url-test / fallback / load-balance / ssid）"
    }
}

foreach ($l in $proxies) {
    $t = $l.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t -match '^(?<name>[^=]+?)\s*=\s*[A-Za-z][A-Za-z0-9]*,') {
        $nodeByName[$Matches['name'].Trim().ToLowerInvariant()] = $Matches['name'].Trim()
    }
}

$subNames = [System.Collections.Generic.List[string]]::new()
foreach ($l in $remote) {
    $t = $l.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t -match '^(?<name>[^=]+?)\s*=\s*https?://') {
        $subNames.Add($Matches['name'].Trim())
    }
}

$builtin = @('direct', 'reject', 'reject-drop', 'reject-tinygif')
$hasSub  = $subNames.Count -gt 0

# [Remote Filter] 定义的是「节点集合」，可以被策略组引用
$filterByName = @{}
foreach ($l in $filters) {
    $t = $l.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t -match '^(?<name>[^=]+?)\s*=\s*NameRegex') {
        $filterByName[$Matches['name'].Trim().ToLowerInvariant()] = $Matches['name'].Trim()
    } else {
        Add-Warn "[Remote Filter] 无法解析的行（应形如 名字=NameRegex, FilterKey=`"...`"）: $t"
    }
}

function Test-Policy([string]$n) {
    $k = $n.Trim().ToLowerInvariant()
    if ($builtin -contains $k)          { return $true }
    if ($groupByName.ContainsKey($k))   { return $true }
    if ($filterByName.ContainsKey($k))  { return $true }
    if ($nodeByName.ContainsKey($k))    { return $true }
    if ($hasSub) { return $true }   # 订阅展开的节点名无法静态验证
    return $false
}

# ---------- 结构层 ----------
foreach ($need in @('General', 'Proxy Group', 'Rule')) {
    if (-not $sections.Contains($need)) { Add-Err "缺少 [$need] 段" }
}
if (-not $sections.Contains('Proxy') -and -not $sections.Contains('Remote Proxy')) {
    Add-Err "既没有 [Proxy] 也没有 [Remote Proxy]，没有任何节点来源"
}

$proxyHasNode = @($proxies | Where-Object { $t = $_.Trim(); $t -ne '' -and -not $t.StartsWith('#') }).Count -gt 0
$remoteHasSub = $subNames.Count -gt 0
if (-not $proxyHasNode -and -not $remoteHasSub -and $sections.Contains('Proxy') -and $sections.Contains('Remote Proxy')) {
    Add-Warn "[Proxy] 和 [Remote Proxy] 都是空的 —— 骨架状态下正常，实际使用前必须填入节点或订阅"
}
if ($proxyHasNode -and -not $remoteHasSub) {
    Add-Note "只用了本地单节点，没有订阅；节点失效时无备用"
}
if (-not $proxyHasNode -and $remoteHasSub) {
    Add-Note "只用了 [Remote Proxy]，没有本地单节点兜底；订阅全挂时无节点可用"
}

# FINAL
$ruleBody = @($rules | Where-Object { $t = $_.Trim(); $t -ne '' -and -not $t.StartsWith('#') })
if ($ruleBody.Count -eq 0) {
    Add-Err "[Rule] 段为空"
} else {
    $finals = @($ruleBody | Where-Object { $_.Trim() -ieq 'FINAL' -or $_.Trim() -match '^FINAL,' })
    if ($finals.Count -eq 0) {
        Add-Err "[Rule] 里没有 FINAL —— 规则全部未命中时行为未定义"
    } elseif ($finals.Count -gt 1) {
        Add-Err "[Rule] 里有 $($finals.Count) 条 FINAL，只有最后一条会生效"
    } elseif ($ruleBody[-1].Trim() -notmatch '^FINAL,') {
        Add-Err "FINAL 不是 [Rule] 的最后一条，实际最后一条是: $($ruleBody[-1].Trim())"
    }
}

# 占位符
$phHits = @()
for ($i = 0; $i -lt $raw.Count; $i++) {
    if ($raw[$i] -match 'EXAMPLE_HOST') { $phHits += ($i + 1) }
}
if ($phHits.Count -gt 0) {
    Add-Warn "第 $($phHits -join ', ') 行仍有占位符 EXAMPLE_HOST，上传前记得替换成你的托管地址"
}

# ---------- 契约层 ----------
$cfg = Get-Content -LiteralPath $Policy -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($p in $cfg.policies.PSObject.Properties) {
    $loonName = $p.Value.loon
    if ($builtin -contains $loonName.ToLowerInvariant()) { continue }
    if (-not $groupByName.ContainsKey($loonName.ToLowerInvariant())) {
        Add-Err "policy.json 的策略 '$($p.Name)' 映射到 Loon 名 '$loonName'，但 [Proxy Group] 里没有这个组 —— 订阅规则会加载失败"
    }
}

foreach ($l in $rules) {
    $t = $l.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $parts = @($t.Split(',') | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt 2) {
        Add-Err "[Rule] 字段不足: $t"
        continue
    }
    $pol = $parts[-1]
    if ($pol -ieq 'no-resolve' -and $parts.Count -ge 3) { $pol = $parts[-2] }
    if (-not (Test-Policy $pol)) {
        Add-Err "[Rule] 引用了不存在的策略 '$pol'（第 $($lineOf[$l]) 行）: $t"
    }
    if ($parts[0] -match '^https?://') {
        Add-Warn "[Rule] 里出现了订阅 URL，建议移到 [Remote Rule] 并加 policy= / tag= ，这样能在界面里单独开关: $($parts[0])"
    }
}

# [Remote Rule] —— URL, policy=X, tag=Y, enabled=Z
$tagSeen = @{}
foreach ($l in $rRules) {
    $t = $l.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $parts = @($t.Split(',') | ForEach-Object { $_.Trim() })
    $url = $parts[0]
    $kv = @{}
    for ($j = 1; $j -lt $parts.Count; $j++) {
        if ($parts[$j] -match '^(?<k>[^=]+?)\s*=\s*(?<v>.*)$') {
            $kv[$Matches['k'].Trim().ToLowerInvariant()] = $Matches['v'].Trim()
        }
    }
    if ($url -notmatch '^https://') {
        Add-Warn "[Remote Rule] 未使用 https（规则内容可被中间人篡改）: $url"
    }
    if (-not $kv.ContainsKey('policy')) {
        Add-Err "[Remote Rule] 缺少 policy=，整组规则不知道该走哪个策略: $url"
    } elseif (-not (Test-Policy $kv['policy'])) {
        Add-Err "[Remote Rule] policy='$($kv['policy'])' 既不是已定义策略组，也不是筛选集合: $url"
    }
    if ($kv.ContainsKey('tag')) {
        $tag = $kv['tag']
        if ($tagSeen.ContainsKey($tag)) {
            Add-Warn "[Remote Rule] tag '$tag' 重复，界面里会分不清是哪一组: $url"
        }
        $tagSeen[$tag] = $true
    } else {
        Add-Warn "[Remote Rule] 没有 tag=，排障时无法按组开关: $url"
    }
}

# ---------- 语义层 ----------
function Get-GeneralValue([string]$key) {
    foreach ($l in $script:general) {
        if ($l -match "^\s*$([regex]::Escape($key))\s*=\s*(?<v>.+)$") { return $Matches['v'].Trim() }
    }
    return $null
}

# 0. [General] 里是否有未经官方文档确认的键
# Loon 遇到不认识的键可能整份拒收，症状是「导入后配置空白」，
# 而且客户端通常不报错，只留一份空配置。
$knownGeneral = @(
    'ipv6', 'dns-server', 'doh-server', 'doq-server', 'doh3-server',
    'allow-wifi-access', 'wifi-access-http-port', 'wifi-access-socks5-port',
    'proxy-test-url', 'internet-test-url', 'test-timeout',
    'switch-node-after-failure-times', 'resource-parser', 'ssid-trigger',
    'real-ip', 'interface-mode', 'force-http-engine-hosts', 'disable-udp-ports',
    'disable-stun', 'geoip-url', 'bypass-tun', 'skip-proxy'
)
foreach ($l in $general) {
    if ($l -match '^\s*(?<k>[\w-]+)\s*=') {
        $k = $Matches['k'].ToLowerInvariant()
        if ($knownGeneral -notcontains $k) {
            Add-Warn "[General] 的键 '$k' 不在官方文档确认的列表内 —— Loon 可能因此整份拒收（症状是导入后空白）。未经验证的键先注释掉，逐个加回验证"
        }
    }
}

# 1. FakeIP / real-ip
$realIp = Get-GeneralValue 'real-ip'
if (-not $realIp) {
    Add-Warn "没配 real-ip。FakeIP 会让系统缓存假地址，关掉 Loon 后 Apple 推送 / iCloud / App Store 会失联。最小集合：*.apple.com, *.icloud.com, *.mzstatic.com, *.push.apple.com"
}

# 2. 两条路径
if (-not (Get-GeneralValue 'skip-proxy')) {
    Add-Warn "没配 skip-proxy。HTTP Proxy 路径仍会把局域网流量塞进来，表现为打印机 / NAS / 投屏失败"
}
if (-not (Get-GeneralValue 'bypass-tun')) {
    Add-Warn "没配 bypass-tun。TUN 路径会接管全部 IP 流量，内网段需要在这里排除"
}

# 3. dns-server 顺序
$dns = Get-GeneralValue 'dns-server'
if ($dns) {
    $first = @($dns.Split(',') | ForEach-Object { $_.Trim() })[0]
    if ($first -ieq 'system') {
        Add-Warn "dns-server 首位是 system（运营商下发，可能被劫持）。建议国内公共 DNS 优先，system 放最后兜底"
    }
}
if (-not $dns -and -not (Get-GeneralValue 'doh-server') -and -not (Get-GeneralValue 'doh3-server')) {
    Add-Warn "没配任何 DNS（dns-server / doh-server / doh3-server）"
}

# 4. ipv6 与 ip-mode
$ipv6 = Get-GeneralValue 'ipv6'
$ipv6Off = ($ipv6 -and $ipv6 -match '^(false|0|no)$')
$nodeLines = @($proxies | Where-Object { $t = $_.Trim(); $t -ne '' -and -not $t.StartsWith('#') })
if ($ipv6Off) {
    foreach ($n in $nodeLines) {
        if ($n -match 'ip-mode\s*=\s*(prefer-v6|v6-only)') {
            Add-Warn "ipv6=false 但节点用了 $(if ($n -match 'ip-mode\s*=\s*(prefer-v6|v6-only)') { $Matches[1] })：不查 AAAA 时这个设置会退化"
        }
    }
}

# 5. block-quic 与 udp
$bk = Get-GeneralValue 'block-quic'
$bkOn = ($bk -and $bk -match '^(true|1|yes)$')
if ($bkOn) {
    foreach ($n in $nodeLines) {
        if ($n -match '\budp\s*=\s*(true|1|yes)' -and $n -notmatch 'block-quic\s*=\s*(false|0|no)') {
            $nm = if ($n -match '^(?<x>[^=]+?)\s*=') { $Matches['x'].Trim() } else { '(未命名)' }
            Add-Warn "全局 block-quic=true 但节点 '$nm' 开了 udp=true，QUIC 会被全局阻断，视频与游戏体验下降"
        }
    }
}

# 6. FakeIP 下 IP 层规则的实效
$ipRules = @($ruleBody | Where-Object { $_.Trim() -match '^(IP-CIDR|IP-CIDR6|IP-ASN|GEOIP),' -and $_.Trim() -notmatch 'no-resolve$' })
if ($ipRules.Count -gt 0 -and -not $realIp) {
    Add-Note "有 $($ipRules.Count) 条不带 no-resolve 的 IP 规则，但没配 real-ip：FakeIP 下域名流量在 IP 层拿到假地址，这些规则只对裸 IP 请求生效"
}

# 7. 订阅段错位
foreach ($l in $proxies) {
    if ($l -match '^\s*[^#=]+=\s*https?://') {
        Add-Err "[Proxy] 里出现订阅 URL，订阅必须写在 [Remote Proxy]，否则节点一个都加载不出来"
    }
}
foreach ($l in $remote) {
    if ($l -match '^\s*[^#=]+=\s*[A-Za-z][A-Za-z0-9]*,\s*\S+,\s*\d+') {
        Add-Warn "[Remote Proxy] 里出现单节点定义，单节点应写在 [Proxy]"
    }
}

# 8. MitM 自洽
$mitmHost = $null
$mitmP12 = $null
foreach ($l in $mitm) {
    if ($l -match '^\s*hostname\s*=\s*(?<v>.*)$') { $mitmHost = $Matches['v'].Trim() }
    if ($l -match '^\s*ca-p12\s*=\s*(?<v>.*)$')    { $mitmP12  = $Matches['v'].Trim() }
}
if ($mitmHost) {
    if (-not $mitmP12) {
        Add-Warn "[MitM] hostname 有值但 ca-p12 为空 —— 官方要求填 P12 的完整 Base64，留空 MitM 不会工作。用 tools/gen-ca.ps1 生成，再用 tools/emit-mitm-conf.ps1 嵌入"
    } elseif ($mitmP12.Length -lt 500) {
        Add-Warn "[MitM] ca-p12 只有 $($mitmP12.Length) 个字符，不像完整的 P12 Base64（一般在 3000 字符左右）。可能是占位符没替换"
    }
    if ($mitmHost -match '^\s*\*\s*$') {
        Add-Err "[MitM] hostname 写成 * 等于解密全部流量，性能和故障面都不划算"
    }
    if (-not (Get-GeneralValue 'real-ip')) {
        Add-Note "[MitM] 已启用，但没配 real-ip。FakeIP 下部分域名的证书校验可能异常"
    }
}
if ($mitmP12 -and -not $mitmHost) {
    Add-Warn "[Mitm] 配了 ca-p12 但 hostname 为空：没有任何域名会被解密"
}

# 9. 策略组之间的引用
foreach ($l in $groups) {
    $t = $l.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t -notmatch '^(?<name>[^=]+?)\s*=\s*(?<rest>.+)$') { continue }
    $gname = $Matches['name'].Trim()
    $parts = @($Matches['rest'].Split(',') | ForEach-Object { $_.Trim() })
    for ($j = 1; $j -lt $parts.Count; $j++) {
        $ref = $parts[$j]
        if ($ref -match '=') { continue }          # 参数，不是引用
        if ($ref -eq '') { continue }
        if (-not (Test-Policy $ref)) {
            Add-Warn "策略组 '$gname' 引用了未知成员 '$ref'"
        }
    }
    if ($parts[0] -eq 'ssid') {
        $hasDefault = @($parts | Where-Object { $_ -match '^default\s*=' }).Count -gt 0
        if (-not $hasDefault) {
            Add-Err "ssid 策略组 '$gname' 缺少 default=，在未匹配的 Wi-Fi 下没有可用策略"
        }
        foreach ($p in $parts) {
            if ($p -match '^(?:default|cellular)\s*=\s*(?<v>.+)$') {
                $ref = $Matches['v'].Trim()
                if (-not (Test-Policy $ref)) { Add-Warn "ssid 组 '$gname' 引用了未知策略 '$ref'（第 $($lineOf[$l]) 行）" }
            }
            elseif ($p -match '^"[^"]*"\s*=\s*(?<v>.+)$') {
                $ref = $Matches['v'].Trim()
                if (-not (Test-Policy $ref)) { Add-Warn "ssid 组 '$gname' 的 SSID 分支引用了未知策略 '$ref'（第 $($lineOf[$l]) 行）" }
            }
        }
    }
}

# ---------- 输出 ----------
Write-Host ''
Write-Host "检查 $Conf" -ForegroundColor White
Write-Host ('-' * 72)

if ($errors.Count -eq 0 -and $warns.Count -eq 0 -and $notes.Count -eq 0) {
    Write-Host '没有发现问题。' -ForegroundColor Green
}

foreach ($m in $errors) { Write-Host "[错误] $m" -ForegroundColor Red }
foreach ($m in $warns)  { Write-Host "[警告] $m" -ForegroundColor Yellow }
foreach ($m in $notes)  { Write-Host "[提示] $m" -ForegroundColor Cyan }

Write-Host ('-' * 72)
Write-Host ("错误 {0}  警告 {1}  提示 {2}" -f $errors.Count, $warns.Count, $notes.Count)
Write-Host ("段: {0}" -f (($sections.Keys | Where-Object { $_ -ne '(root)' }) -join ' / '))
Write-Host ("策略组 {0} 个，筛选集合 {1} 个，本地节点 {2} 个，订阅 {3} 个" -f $groupByName.Count, $filterByName.Count, $nodeByName.Count, $subNames.Count)
Write-Host ("本地规则 {0} 条，远程规则 {1} 组，插件 {2} 个" -f $ruleBody.Count, $tagSeen.Count, @($plugins | Where-Object { $t = $_.Trim(); $t -ne '' -and -not $t.StartsWith('#') }).Count)
Write-Host ''

if ($errors.Count -gt 0) { exit 1 }
exit 0
