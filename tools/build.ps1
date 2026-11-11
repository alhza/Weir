#Requires -Version 7.0
<#
.SYNOPSIS
    把 rules/*.list 单份源构建成 Loon 与 Quantumult X 两套订阅规则。

.DESCRIPTION
    源文件格式：
        #! policy: <policy.json 里的键>
        #! desc:   ...
        #! risk:   low|medium|high
        #! toggleable: true|false
        #
        # 注释行
        DOMAIN-SUFFIX,example.com
        IP-ASN,4134,no-resolve
        DOMAIN,cn.bing.com @direct        <- 单行覆盖策略

    规则行默认继承 #! policy，行尾加 " @<policy>" 可覆盖到另一个策略。
    构建时按策略分文件、补上各端真实策略名，这样换策略名不用重写规则。

.PARAMETER Root
    仓库根目录，默认脚本所在目录。

.PARAMETER Target
    要生成的端，默认两端都生成。
#>
[CmdletBinding()]
param(
    # 仓库根目录。脚本放在 _dev/ 下，所以默认取上一级。
    [string]   $Root   = (Split-Path -Parent $PSScriptRoot),
    [string[]] $Target = @('loon', 'qx')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rulesDir   = Join-Path $Root 'rules'
$outRoot    = Join-Path $Root 'out'
$policyFile = Join-Path $Root 'policy.json'

if (-not (Test-Path -LiteralPath $rulesDir))   { throw "找不到目录: $rulesDir" }
if (-not (Test-Path -LiteralPath $policyFile)) { throw "找不到文件: $policyFile" }

$cfg = Get-Content -LiteralPath $policyFile -Raw -Encoding utf8 | ConvertFrom-Json

# 策略键含连字符（proxy-media），点号访问会被当成减法，统一转成哈希表索引
$policyTable = @{}
foreach ($prop in $cfg.policies.PSObject.Properties) {
    $policyTable[$prop.Name] = $prop.Value
}
if ($policyTable.Count -eq 0) { throw 'policy.json 里没有任何策略定义' }

# 源类型 -> 各端类型。qx=$null 表示该端不支持，需降级或丢弃。
$typeMap = @{
    'DOMAIN'          = @{ loon = 'DOMAIN';          qx = 'HOST' }
    'DOMAIN-SUFFIX'   = @{ loon = 'DOMAIN-SUFFIX';   qx = 'HOST-SUFFIX' }
    'DOMAIN-KEYWORD'  = @{ loon = 'DOMAIN-KEYWORD';  qx = 'HOST-KEYWORD' }
    'DOMAIN-WILDCARD' = @{ loon = 'DOMAIN-WILDCARD'; qx = $null }
    'IP-CIDR'         = @{ loon = 'IP-CIDR';         qx = 'IP-CIDR' }
    'IP-CIDR6'        = @{ loon = 'IP-CIDR6';        qx = 'IP6-CIDR' }
    'IP-ASN'          = @{ loon = 'IP-ASN';          qx = 'IP-ASN' }
    'GEOIP'           = @{ loon = 'GEOIP';           qx = 'GEOIP' }
}

# 两端都支持「裸 IP 直通」语义，仅域名类规则需要 DNS 提示
$ipTypes = @('IP-CIDR', 'IP-CIDR6', 'IP-ASN', 'GEOIP')

$warnings = [System.Collections.Generic.List[string]]::new()
$rows     = [System.Collections.Generic.List[object]]::new()

# ---------- 解析源 ----------
foreach ($file in Get-ChildItem -LiteralPath $rulesDir -Filter '*.list' | Sort-Object Name) {
    $meta = @{ policy = $null; desc = ''; risk = ''; toggleable = '' }
    $lineNo = 0

    foreach ($raw in Get-Content -LiteralPath $file.FullName -Encoding utf8) {
        $lineNo++
        $line = $raw.Trim()
        if ($line.Length -eq 0) { continue }

        if ($line.StartsWith('#!')) {
            $body = $line.Substring(2).Trim()
            $sep  = $body.IndexOf(':')
            if ($sep -gt 0) {
                $meta[$body.Substring(0, $sep).Trim().ToLowerInvariant()] = $body.Substring($sep + 1).Trim()
            }
            continue
        }
        if ($line.StartsWith('#')) { continue }

        # 行尾策略覆盖： "... @direct"
        $rowPolicy = $meta.policy
        if ($line -match '^(?<rule>.+?)\s+@(?<pol>[A-Za-z][A-Za-z0-9_-]*)$') {
            $line      = $Matches['rule'].Trim()
            $rowPolicy = $Matches['pol']
        }

        if (-not $rowPolicy) {
            throw "$($file.Name):$lineNo 缺少 '#! policy: <name>' 头，且该行没有 @<policy> 覆盖"
        }

        $parts = @($line.Split(',') | ForEach-Object { $_.Trim() })
        if ($parts.Count -lt 2) {
            $warnings.Add("$($file.Name):$lineNo 字段不足，已跳过: $line")
            continue
        }

        $type = $parts[0].ToUpperInvariant()
        if (-not $typeMap.ContainsKey($type)) {
            $warnings.Add("$($file.Name):$lineNo 未知规则类型 '$type'，已跳过: $line")
            continue
        }

        $rest = @($parts[1..($parts.Count - 1)])

        # 剥离 no-resolve，最后统一放行尾
        $noResolve = $false
        if ($rest.Count -ge 2 -and $rest[-1] -eq 'no-resolve') {
            $noResolve = $true
            $rest = @($rest[0..($rest.Count - 2)])
        }

        # 源行里若误写了策略名，这里会多出一段；用白名单校验参数个数
        $maxArgs = switch ($type) {
            'GEOIP'           { 1 }
            'IP-ASN'          { 1 }
            'DOMAIN'          { 1 }
            'DOMAIN-SUFFIX'   { 1 }
            'DOMAIN-KEYWORD'  { 1 }
            'DOMAIN-WILDCARD' { 1 }
            'IP-CIDR'         { 1 }
            'IP-CIDR6'        { 1 }
            default           { 1 }
        }
        if ($rest.Count -gt $maxArgs) {
            $warnings.Add("$($file.Name):$lineNo 参数过多（源规则不应包含策略名），已按前 $maxArgs 段解析: $line")
            $rest = @($rest[0..($maxArgs - 1)])
        }

        # 域名规则的常见写法错误 —— 开源规则集里到处都是，这里直接拦
        if ($type -in 'DOMAIN', 'DOMAIN-SUFFIX', 'DOMAIN-KEYWORD') {
            $v = $rest[0]
            if ($v -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
                $warnings.Add("$($file.Name):$lineNo 域名带了协议前缀，永不会命中: $v")
            }
            if ($v.Contains('/')) {
                $warnings.Add("$($file.Name):$lineNo 域名含路径，应为纯主机名: $v")
            }
            if ($v.Contains(' ') -or $v.Contains("`t")) {
                $warnings.Add("$($file.Name):$lineNo 域名含空白字符: $v")
            }
            if ($type -ne 'DOMAIN-KEYWORD' -and $v.Contains('*')) {
                $warnings.Add("$($file.Name):$lineNo $type 不支持星号，需要通配请用 DOMAIN-WILDCARD: $v")
            }
            if ($type -eq 'DOMAIN-SUFFIX' -and $v.StartsWith('.')) {
                $warnings.Add("$($file.Name):$lineNo DOMAIN-SUFFIX 不需要前导点: $v")
            }
        }

        $rows.Add([pscustomobject]@{
            File       = $file.Name
            LineNo     = $lineNo
            Type       = $type
            Args       = $rest
            NoResolve  = $noResolve
            Policy     = $rowPolicy
        })
    }
}

# ---------- 按端 / 按策略分桶 ----------
$buckets = @{}   # $buckets[$target][$policy] = List[string]
foreach ($t in $Target) { $buckets[$t] = @{} }

$dropped = [System.Collections.Generic.List[string]]::new()

foreach ($row in $rows) {
    foreach ($t in $Target) {
        $map = $typeMap[$row.Type]
        $tType = $map[$t]

        # --- 降级 ---
        if ($null -eq $tType) {
            if ($t -eq 'qx' -and $row.Type -eq 'DOMAIN-WILDCARD') {
                $pattern = $row.Args[0]
                if ($pattern -match '^\*\.(?<base>[A-Za-z0-9._-]+)$') {
                    $tType = 'HOST-SUFFIX'
                    $row.Args = @($Matches['base'])
                    $warnings.Add("$($row.File):$($row.LineNo) DOMAIN-WILDCARD '$pattern' 在 QX 降级为 HOST-SUFFIX '$($Matches['base'])'")
                } else {
                    $dropped.Add("qx  $($row.File):$($row.LineNo)  $pattern  (QX 不支持通配符，且无法安全降级)")
                    continue
                }
            } else {
                $dropped.Add("$t  $($row.File):$($row.LineNo)  $($row.Args[0])  (该端不支持 $($row.Type))")
                continue
            }
        }

        # --- 策略名 ---
        $polDef = $policyTable[$row.Policy]
        if (-not $polDef) {
            throw "policy.json 里没有定义策略 '$($row.Policy)'（出现在 $($row.File)）"
        }
        $polName = $polDef.$t

        # --- 组装 ---
        $segments = @($tType) + $row.Args + @($polName)
        if ($row.NoResolve) { $segments += 'no-resolve' }
        $out = $segments -join ','

        if (-not $buckets[$t].ContainsKey($row.Policy)) {
            $buckets[$t][$row.Policy] = [System.Collections.Generic.List[string]]::new()
        }
        $buckets[$t][$row.Policy].Add($out)
    }
}

# ---------- 冲突与遮蔽检测 ----------
# 1) 硬冲突：同一 (类型,值) 出现在两个不同策略里 —— 谁赢取决于文件顺序，必须修掉。
# 2) 跨策略遮蔽：精确 DOMAIN 落在另一个策略的 DOMAIN-SUFFIX 下面 ——
#    常见且常是有意的（如 cn.bing.com 直连而 bing.com 代理），但每一处都要人工确认。
$conflicts = [System.Collections.Generic.List[string]]::new()
$shadows   = [System.Collections.Generic.List[string]]::new()
$dupes     = [System.Collections.Generic.List[string]]::new()

foreach ($t in $Target) {
    $keyPolicies = @{}
    $keyCount    = @{}
    $domainRows  = [System.Collections.Generic.List[object]]::new()
    $suffixRows  = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $buckets[$t].Keys) {
        foreach ($line in $buckets[$t][$p]) {
            $f   = $line.Split(',')
            $key = "$($f[0]),$($f[1])"

            if (-not $keyPolicies.ContainsKey($key)) { $keyPolicies[$key] = [System.Collections.Generic.List[string]]::new() }
            $keyPolicies[$key].Add($p)

            if (-not $keyCount.ContainsKey($key)) { $keyCount[$key] = 0 }
            $keyCount[$key]++

            if ($f[0] -eq 'DOMAIN') {
                $domainRows.Add([pscustomobject]@{ Value = $f[1]; Policy = $p })
            }
            elseif ($f[0] -in 'DOMAIN-SUFFIX', 'HOST-SUFFIX') {
                $suffixRows.Add([pscustomobject]@{ Value = $f[1]; Policy = $p })
            }
        }
    }

    foreach ($k in ($keyPolicies.Keys | Sort-Object)) {
        $pols = @($keyPolicies[$k] | Select-Object -Unique)
        if ($pols.Count -gt 1) {
            $conflicts.Add("[$t] $k  同时属于多个策略: $($pols -join ' / ')")
        }
        if ($keyCount[$k] -gt 1) {
            $dupes.Add("[$t] $k  重复 $($keyCount[$k]) 次")
        }
    }

    foreach ($d in $domainRows) {
        foreach ($s in $suffixRows) {
            if ($d.Policy -eq $s.Policy) { continue }
            if ($d.Value -eq $s.Value -or $d.Value.EndsWith('.' + $s.Value)) {
                $shadows.Add("[$t] $($d.Value) -> $($d.Policy)  覆盖在  *.$($s.Value) -> $($s.Policy)  之上")
            }
        }
    }
}

# ---------- 写文件 ----------
# 强制 LF + 无 BOM。CRLF 会让规则行的域名尾部带上 \r，
# 而 Loon / QX 的解析器是闭源的，不能赌它会 strip。
function Write-Utf8([string]$Path, [string[]]$Lines) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $text = (($Lines -join "`n") -replace "`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
}

$summary = [System.Collections.Generic.List[string]]::new()

foreach ($t in $Target) {
    $pols = @($cfg.order | Where-Object { $buckets[$t].ContainsKey($_) })
    # 未在 order 里声明的策略，按名称追加到末尾
    $pols += @($buckets[$t].Keys | Where-Object { $cfg.order -notcontains $_ } | Sort-Object)

    $includeLines = [System.Collections.Generic.List[string]]::new()
    if ($t -eq 'loon') {
        $includeLines.Add('# 由 build.ps1 生成，勿手改。顺序 = 优先级，越靠前越优先。')
    } else {
        $includeLines.Add('[filter_remote]')
        $includeLines.Add('# 由 build.ps1 生成，勿手改。')
    }

    foreach ($p in $pols) {
        $items  = $buckets[$t][$p]
        $polObj = $policyTable[$p]
        $polName = $polObj.($t)
        # 策略键可能带连字符（proxy-media），必须用括号索引，点号会被当成减号
        $tagName = if ($polObj.PSObject.Properties.Name -contains 'tag') { $polObj.tag } else { $p }
        $fileName = "$p.list"

        $header = @(
            "# $fileName  —  policy=$p  端=$t  规则数=$($items.Count)"
            "# 由 build.ps1 从 rules/ 生成，勿手改。"
            "# 策略名：$polName"
        )
        Write-Utf8 (Join-Path $outRoot "$t/$fileName") (@($header) + $items.ToArray())

        $url = "$($cfg.host)/$t/$fileName"
        if ($t -eq 'loon') {
            # Loon 的 [Remote Rule] 语法：URL, policy=策略, tag=显示名, enabled=开关
            # tag 让人能在界面里单独关掉某一组，排障时最有用
            $includeLines.Add("$url, policy=$polName, tag=$tagName, enabled=true")
        } else {
            $includeLines.Add("$url, tag=$tagName, force-policy=$polName, update-interval=86400, enabled=true")
        }

        $summary.Add(('{0,-6} {1,-14} {2,4} 条  ->  {3}' -f $t, $p, $items.Count, "out/$t/$fileName"))
    }

    $incName = if ($t -eq 'loon') { '_include.conf' } else { '_filter_remote.inc' }
    Write-Utf8 (Join-Path $outRoot "$t/$incName") $includeLines.ToArray()
    $summary.Add(('{0,-6} {1,-8} {2,4} 行  ->  {3}' -f $t, '(片段)', $includeLines.Count, "out/$t/$incName"))
}

# ---------- 报告 ----------
Write-Host ''
Write-Host '构建完成' -ForegroundColor Green
Write-Host ('-' * 72)
$summary | ForEach-Object { Write-Host $_ }

if ($dropped.Count -gt 0) {
    Write-Host ''
    Write-Host "被丢弃的规则（$($dropped.Count)）：" -ForegroundColor Yellow
    $dropped | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
}

if ($dupes.Count -gt 0) {
    Write-Host ''
    Write-Host "重复规则（$($dupes.Count)）：" -ForegroundColor Yellow
    $dupes | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
}

if ($conflicts.Count -gt 0) {
    Write-Host ''
    Write-Host "硬冲突（$($conflicts.Count)）—— 必须修，否则命中结果取决于文件顺序：" -ForegroundColor Red
    $conflicts | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

if ($shadows.Count -gt 0) {
    Write-Host ''
    Write-Host "跨策略遮蔽（$($shadows.Count)）—— 通常是故意的，逐条确认：" -ForegroundColor Cyan
    $shadows | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
}

if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host "警告（$($warnings.Count)）：" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
}

Write-Host ('-' * 72)
Write-Host "源规则 $($rows.Count) 条，策略 $($cfg.policies.PSObject.Properties.Name.Count) 个，端 $($Target -join '/')"
Write-Host '下一步：把 out/ 上传到静态托管，替换 policy.json 里的 host，再把 _include 片段贴进 conf。'
Write-Host ''
