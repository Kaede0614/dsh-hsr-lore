# parse-missions.ps1 - 把 raw/missions/*.wikitext 解析成结构化索引
# 输出：
#   distill/out/mission-index.json   全部任务的紧凑元数据（供筛选/排序/路由）
#   distill/out/parse-report.txt     解析质量报告
# 注意：必须以 UTF-8 with BOM 保存。

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root    = $PSScriptRoot
$RawDir  = Join-Path $Root 'raw\missions'
$OutDir  = Join-Path $Root 'out'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# --- 工具函数 ---

# 取 {{任务 ... }} 顶层模板的原始文本（第一个 {{任务 到与之匹配的 }}）
function Get-TaskTemplate([string]$text) {
  $m = [regex]::Match($text, '(?s)\{\{任务\b')
  if (-not $m.Success) { return $null }
  $start = $m.Index
  $i = $start; $depth = 0; $n = $text.Length
  while ($i -lt $n - 1) {
    if ($text[$i] -eq '{' -and $text[$i+1] -eq '{') { $depth++; $i += 2; continue }
    if ($text[$i] -eq '}' -and $text[$i+1] -eq '}') { $depth--; $i += 2; if ($depth -eq 0) { return $text.Substring($start, $i - $start) }; continue }
    $i++
  }
  return $text.Substring($start)
}

# 按顶层 | 切分模板参数（忽略 {{}} 与 [[]] 内部的 |）
function Split-Params([string]$tpl) {
  $body = $tpl.Substring(2, $tpl.Length - 4)   # 去掉 {{ }}
  $parts = @(); $cur = New-Object System.Text.StringBuilder
  $depthTpl = 0; $depthLink = 0; $i = 0; $n = $body.Length
  while ($i -lt $n) {
    $c = $body[$i]
    if ($c -eq '{' -and $i + 1 -lt $n -and $body[$i+1] -eq '{') { $depthTpl++; [void]$cur.Append('{{'); $i += 2; continue }
    if ($c -eq '}' -and $i + 1 -lt $n -and $body[$i+1] -eq '}') { $depthTpl--; [void]$cur.Append('}}'); $i += 2; continue }
    if ($c -eq '[' -and $i + 1 -lt $n -and $body[$i+1] -eq '[') { $depthLink++; [void]$cur.Append('[['); $i += 2; continue }
    if ($c -eq ']' -and $i + 1 -lt $n -and $body[$i+1] -eq ']') { $depthLink--; [void]$cur.Append(']]'); $i += 2; continue }
    if ($c -eq '|' -and $depthTpl -eq 0 -and $depthLink -eq 0) { $parts += $cur.ToString(); [void]$cur.Clear(); $i++; continue }
    [void]$cur.Append($c); $i++
  }
  $parts += $cur.ToString()
  return $parts
}

# 清洗 wikitext 标记为纯文本（保留可读内容）
function Clean-Text([string]$s) {
  if ($null -eq $s) { return '' }
  $s = [regex]::Replace($s, '(?s)<!--.*?-->', '')
  $s = $s -replace '<br\s*/?>', "`n"
  $s = [regex]::Replace($s, '(?s)\{\{注音\|([^|{}]*)\|([^|{}]*)\}\}', '$1')      # {{注音|显示|注}}
  $s = [regex]::Replace($s, '(?s)\{\{颜色\|[^|{}]*\|([^{}]*)\}\}', '$1')          # {{颜色|样式|文本}}
  $s = [regex]::Replace($s, '(?s)\{\{图标\|([^|{}]*)(\|[^|{}]*)?\}\}', '$1')      # {{图标|名|量}}
  $s = [regex]::Replace($s, '(?s)\{\{PAGENAME\}\}', '')
  $s = [regex]::Replace($s, '(?s)\{\{[^{}]*\}\}', '')                              # 剩余简单模板
  $s = [regex]::Replace($s, '(?s)\[\[[^\[\]|]*\|([^\[\]]*)\]\]', '$1')            # [[A|B]] -> B
  $s = [regex]::Replace($s, '(?s)\[\[([^\[\]]*)\]\]', '$1')                       # [[A]] -> A
  $s = $s -replace "'''?", ''                                                     # 粗斜体
  $s = [regex]::Replace($s, '[ \t]+', ' ')
  $s = [regex]::Replace($s, '(\r?\n){2,}', "`n")
  return $s.Trim()
}

# 从 *[[链接]] 列表里取条目名
function Get-LinkList([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return @() }
  $out = @()
  foreach ($m in [regex]::Matches($s, '(?m)^\*+\s*\[\[([^\[\]|]*)(\|[^\[\]]*)?\]\]')) {
    $t = Clean-Text $m.Groups[1].Value
    if ($t) { $out += $t }
  }
  return $out
}

# 从 *文本 列表里取纯文本行
function Get-BulletList([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return @() }
  $out = @()
  foreach ($m in [regex]::Matches($s, '(?m)^\*+\s*(.+)$')) {
    $t = Clean-Text $m.Groups[1].Value
    if ($t) { $out += $t }
  }
  return $out
}

# --- 主循环 ---
$files = Get-ChildItem $RawDir -Filter *.wikitext -File | Sort-Object Name
$items = New-Object System.Collections.ArrayList
$seriesPages = New-Object System.Collections.ArrayList
$problems = New-Object System.Collections.ArrayList
$noTpl = 0

foreach ($f in $files) {
  $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  $tpl = Get-TaskTemplate $text
  if (-not $tpl) {
    # 可能是 {{系列任务}} 总览页（该系列所有任务的共同描述），单独收集
    $st = [regex]::Match($text, '(?s)\{\{系列任务.*?\n\}\}')
    if ($st.Success) {
      $sp = @{}
      foreach ($p in (Split-Params $st.Value)) {
        $eq = $p.IndexOf('='); if ($eq -lt 1) { continue }
        $k = $p.Substring(0, $eq).Trim(); $v = $p.Substring($eq + 1)
        if (-not $sp.ContainsKey($k)) { $sp[$k] = $v }
      }
      # 系列名：模板里常写 {{PAGENAME}}，Clean-Text 会把它清成空串，此时回退到文件名
      $seriesName = Clean-Text ($(if ($sp.ContainsKey('系列任务名')) { $sp['系列任务名'] } else { '' }))
      if (-not $seriesName) { $seriesName = $f.BaseName }
      [void]$seriesPages.Add([pscustomobject][ordered]@{
        kind        = 'series'
        name        = $seriesName
        region      = (Clean-Text ($(if ($sp.ContainsKey('任务地区')) { $sp['任务地区'] } else { '' })))
        version     = (Clean-Text ($(if ($sp.ContainsKey('所属版本')) { $sp['所属版本'] } else { '' })))
        type        = (Clean-Text ($(if ($sp.ContainsKey('任务类型')) { $sp['任务类型'] } else { '' })))
        description = (Clean-Text ($(if ($sp.ContainsKey('描述')) { $sp['描述'] } else { '' })))
        file        = $f.Name
      })
      continue
    }
    $noTpl++
    [void]$problems.Add("NO-TEMPLATE`t$($f.Name)")
    continue
  }

  $params = @{}
  foreach ($p in (Split-Params $tpl)) {
    $eq = $p.IndexOf('=')
    if ($eq -lt 1) { continue }
    $k = $p.Substring(0, $eq).Trim()
    $v = $p.Substring($eq + 1)
    if (-not $params.ContainsKey($k)) { $params[$k] = $v }
  }

  $name = Clean-Text ($(if ($params.ContainsKey('任务名称')) { $params['任务名称'] } else { '' }))
  if (-not $name) { $name = ($f.BaseName) }

  $region  = Clean-Text ($(if ($params.ContainsKey('任务地区')) { $params['任务地区'] } else { '' }))
  $version = Clean-Text ($(if ($params.ContainsKey('所属版本')) { $params['所属版本'] } else { '' }))
  $series  = Clean-Text ($(if ($params.ContainsKey('系列任务')) { $params['系列任务'] } else { '' }))
  $num     = Clean-Text ($(if ($params.ContainsKey('任务编号')) { $params['任务编号'] } else { '' }))
  $type    = Clean-Text ($(if ($params.ContainsKey('任务类型')) { $params['任务类型'] } else { '' }))
  $desc    = Clean-Text ($(if ($params.ContainsKey('任务描述')) { $params['任务描述'] } else { '' }))
  $gist    = Clean-Text ($(if ($params.ContainsKey('剧情梗概')) { $params['剧情梗概'] } else { '' }))
  $chars   = Clean-Text ($(if ($params.ContainsKey('出场人物')) { $params['出场人物'] } else { '' }))
  $pre     = Get-LinkList ($(if ($params.ContainsKey('前置任务')) { $params['前置任务'] } else { '' }))
  $post    = Get-LinkList ($(if ($params.ContainsKey('后续任务')) { $params['后续任务'] } else { '' }))
  $flow    = Get-BulletList ($(if ($params.ContainsKey('任务流程')) { $params['任务流程'] } else { '' }))

  # 剧情内容规模（用于评估正文体量，不落正文）
  $storyLen = 0
  $si = $text.IndexOf('==剧情内容==')
  if ($si -ge 0) { $storyLen = $text.Length - $si }

  # 梗概的关键节点：按句号/换行拆
  $points = @()
  if ($gist) {
    $points = @($gist -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } )
  }

  # 章节归属（与 gen-fragments.ps1 的 Get-ChapterOf 同规则），暴露出来供生成器校验，
  # 避免「地区存在但没归入任何章节」的任务被静默丢掉。
  $chapterId = $null
  $first = ($region -split '[、,，]')[0].Trim()
  if ($first) {
    if ($first -eq '空间站「黑塔」' -or $first -eq '「黑塔」空间站' -or $first -eq '黑塔空间站' -or $first -eq '星穹列车') { $chapterId = 'chapter-00-herta' }
    elseif ($first -eq '雅利洛-Ⅵ' -or $first -eq '雅利洛-VI' -or $first -like '雅利洛-Ⅵ-*') { $chapterId = 'chapter-01-jarilo' }
    elseif ($first -eq '仙舟「罗浮」') { $chapterId = 'chapter-02-luofu' }
    elseif ($first -eq '匹诺康尼') { $chapterId = 'chapter-03-penacony' }
    elseif ($first -eq '翁法罗斯') { $chapterId = 'chapter-04-amphoreus' }
    elseif ($first -eq '二相乐园' -or $first -eq '千星城') { $chapterId = 'chapter-05-paradise' }
  }

  $obj = [ordered]@{
    name         = $name
    file         = $f.Name
    region       = $region
    chapter      = $chapterId
    version      = $version
    type         = $type
    series       = $series
    number       = $num
    prerequisite = $pre
    followup     = $post
    objectives   = $flow
    characters   = @($chars -split '[、,，]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    description  = $desc
    gist         = $gist
    gistPoints   = $points.Count
    storyChars   = $storyLen
    hasGist      = [bool]$gist
  }
  [void]$items.Add([pscustomobject]$obj)

  if (-not $gist) { [void]$problems.Add("NO-GIST`t$name") }
  if (-not $region) { [void]$problems.Add("NO-REGION`t$name") }
}

# 注意：PowerShell 的 ConvertTo-Json 对 ArrayList 只会序列化第一个元素，必须先 ToArray()
$json = $items.ToArray() | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText((Join-Path $OutDir 'mission-index.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $OutDir 'series-index.json'), ($seriesPages.ToArray() | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

$rep = New-Object System.Collections.ArrayList
[void]$rep.Add("文件总数：$($files.Count)")
[void]$rep.Add("任务页解析成功：$($items.Count)")
[void]$rep.Add("系列总览页：$($seriesPages.Count)")
[void]$rep.Add("真正无模板：$noTpl")
[void]$rep.Add("有剧情梗概：$(($items | Where-Object { $_.hasGist }).Count)")
[void]$rep.Add("")
[void]$rep.Add("--- 按任务地区统计（任务页） ---")
foreach ($g in ($items | Group-Object region | Sort-Object Count -Descending)) {
  [void]$rep.Add(("{0,-20} {1}" -f $g.Name, $g.Count))
}
[void]$rep.Add("")
[void]$rep.Add("--- 主线条目（有梗概且无系列外传标记）的地区统计 ---")
foreach ($g in ($items | Where-Object { $_.hasGist } | Group-Object region | Sort-Object Count -Descending)) {
  [void]$rep.Add(("{0,-20} {1}" -f $g.Name, $g.Count))
}
[void]$rep.Add("")
[void]$rep.Add("--- 按所属版本统计 ---")
foreach ($g in ($items | Group-Object version | Sort-Object Name)) {
  [void]$rep.Add(("{0,-10} {1}" -f $g.Name, $g.Count))
}
[void]$rep.Add("")
[void]$rep.Add("--- 按系列任务统计（前 30） ---")
foreach ($g in ($items | Group-Object series | Sort-Object Count -Descending | Select-Object -First 30)) {
  [void]$rep.Add(("{0,-28} {1}" -f $g.Name, $g.Count))
}
[void]$rep.Add("")
[void]$rep.Add("--- 系列总览页 ---")
foreach ($s in $seriesPages) { [void]$rep.Add(("{0,-28} {1}  {2}" -f $s.name, $s.region, $s.version)) }
[void]$rep.Add("")
[void]$rep.Add("--- 解析问题 ---")
foreach ($p in $problems) { [void]$rep.Add($p) }
[System.IO.File]::WriteAllText((Join-Path $OutDir 'parse-report.txt'), ($rep -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))

Write-Host ("解析完成：{0} 个文件 -> mission-index.json" -f $items.Count)
Write-Host ($rep -join "`n")
