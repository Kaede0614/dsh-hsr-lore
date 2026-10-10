# parse-worldview.ps1 - 把 raw/worldview/*.wikitext 解析成「按章节（== 标题 ==）」的结构化条目
# 输出：distill/out/worldview-sections.json
# 必须以 UTF-8 with BOM 保存。

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'clean-wikitext.ps1')

$Root   = $PSScriptRoot
$RawDir = Join-Path $Root 'raw\worldview'
$OutDir = Join-Path $Root 'out'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 页面 -> 分片归属（按需求文档 6 节结构）
# 说明：wiki 上「令使」「无名客」「忆域」等没有独立页面，其释义包含在
#       「专有名词」/「派系」/「星神」页内，故不单独登记。
$PageMap = @{
  '星神'      = @{ frag = 'worldview-aeons';     kind = 'concept' }
  '派系'      = @{ frag = 'worldview-factions';  kind = 'faction' }
  '专有名词'  = @{ frag = 'glossary';            kind = 'term'    }
  '星穹列车'  = @{ frag = 'worldview-factions';  kind = 'faction' }
  '雅利洛-Ⅵ'  = @{ frag = 'worldview-locations'; kind = 'place'   }
  '贝洛伯格'  = @{ frag = 'worldview-locations'; kind = 'place'   }
  '匹诺康尼'  = @{ frag = 'worldview-locations'; kind = 'place'   }
  '翁法罗斯'  = @{ frag = 'worldview-locations'; kind = 'place'   }
}

$all = New-Object System.Collections.ArrayList
$report = New-Object System.Collections.ArrayList

function Normalize-Title([string]$t) {
  $x = Strip-Inline $t
  $x = [regex]::Replace($x, '^\s*[\[\]]*\s*', '')
  $x = $x -replace '^[=\s]+', ''      # 更深层级标题残留的 =
  $x = $x -replace '[=\s]+$', ''
  $x = $x -replace '^[「『“"''\s]+', ''
  $x = $x -replace '[」』”"''\s]+$', ''
  $x = $x -replace '\s+', ' '
  return $x.Trim()
}

foreach ($f in (Get-ChildItem $RawDir -Filter *.wikitext -File | Sort-Object Name)) {
  $base = $f.BaseName
  if (-not $PageMap.ContainsKey($base)) {
    [void]$report.Add("SKIP（未登记页面）：$base")
    continue
  }
  $map  = $PageMap[$base]
  $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)

  # 先在原始 wikitext 上按 == 标题 == 切段，再逐段清洗（顺序很关键）
  $sections = Get-Sections $text
  $secCount = 0
  if ($sections.Count -eq 0) { [void]$report.Add("NO-SECTION：$base"); continue }

  foreach ($sec in $sections) {
    $title = Normalize-Title $sec.title
    $body  = Strip-Block $sec.body
    if (-not $title) { continue }
    if ($title -match '^(目录|导航|注释|参考|参考资料|引用说明|待补充|来源|考据|相关条目|相关视频|相关链接|图集|画廊)$') { continue }
    # 标题里的引号包裹的才是条目名（形如 毁灭」，纳努克 -> 毁灭·纳努克）
    $m2 = [regex]::Match($title, '([^「」『』]{1,20})[」』]\s*[，,、]\s*(.+)$')
    if ($m2.Success) { $title = ($m2.Groups[1].Value.Trim() + '·' + $m2.Groups[2].Value.Trim()) }
    # 成对括号不完整时修补：天空之泰坦」晨昏之眼 -> 「天空之泰坦」晨昏之眼
    $m3 = [regex]::Match($title, '^([^「」『』]{1,20})[」』](\S.*)$')
    if ($m3.Success) { $title = ('「' + $m3.Groups[1].Value.Trim() + '」' + $m3.Groups[2].Value.Trim()) }
    # 去掉「来源出身/行为特征/相关派系」这类空小节标签行
    $body = [regex]::Replace($body, '(?m)^\s*(来源出身|行为特征|相关派系|形象与标志考据|关联条目|开发日志\d*|考据|杂谈)\s*$', '')
    $body = [regex]::Replace($body, '(\r?\n){2,}', "`n").Trim()
    if ($body.Length -lt 50) { continue }
    if ($body.Length -gt 2600) { $body = $body.Substring(0, 2600) + '…' }
    $secCount++
    [void]$all.Add([pscustomobject][ordered]@{
      page      = $base
      fragment  = $map.frag
      kind      = $map.kind
      title     = $title
      text      = $body
      source_url = ("https://wiki.biligame.com/sr/" + [uri]::EscapeDataString($base))
    })
  }
  [void]$report.Add(("OK {0}：{1} 段（{2} 字符）" -f $base, $secCount, $text.Length))
}

[System.IO.File]::WriteAllText((Join-Path $OutDir 'worldview-report.txt'), ($report -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))

# 后处理：丢掉目录型/过短的无释义段落，但保留真正的释义段（篇幅可短）
$filtered = New-Object System.Collections.ArrayList
foreach ($s in $all) {
  $t = $s.text
  $flat = $t -replace '\s', ''
  $prose = ([regex]::Matches($flat, '[，。；！？]')).Count
  $isIndexTitle = ($s.title -match '总览|一览|列表|导航|索引')
  # 目录型段落：标题像目录、几乎无标点、且以换行罗列为主
  if ($isIndexTitle -and $prose -lt 5) { continue }
  # 纯罗列：多行且几乎无标点
  if ($prose -lt 2 -and (($t -split "`n").Count -gt 4)) { continue }
  # 正文太短且不含成句内容
  if ($flat.Length -lt 25 -and $prose -lt 1) { continue }
  [void]$filtered.Add($s)
}

# 注意：PowerShell 的 ConvertTo-Json 对 ArrayList 只会序列化第一个元素，
# 必须先 ToArray()，否则整份数据会退化成畸形结构（数组里套数组）。
[System.IO.File]::WriteAllText((Join-Path $OutDir 'worldview-sections.json'), ($filtered.ToArray() | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $OutDir 'worldview-report.txt'), ($report -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))

Write-Host ("世界观条目：{0} 条（过滤前 {1}）" -f $filtered.Count, $all.Count)
foreach ($g in ($filtered | Group-Object fragment)) { Write-Host ("  {0,-22} {1}" -f $g.Name, $g.Count) }
Write-Host ''
Write-Host ($report -join "`n")
