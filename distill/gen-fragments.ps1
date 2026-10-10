# gen-fragments.ps1 - 由 raw + mission-index 生成 Skill 的 data/*.json 与 references/*.md
# 逻辑层不计入：本脚本只做确定性渲染（wiki 原文 → 结构化条目 → 可读摘要），不做主观改写。
# 必须以 UTF-8 with BOM 保存。

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

. (Join-Path $PSScriptRoot 'story-extract.ps1')

$Root      = $PSScriptRoot
$RawMissions = Join-Path $Root 'raw\missions'
$OutDir    = Join-Path $Root 'out'
$SkillDir  = (Join-Path (Split-Path $PSScriptRoot -Parent) 'skill')
$DataDir   = Join-Path $SkillDir 'data'
$RefDir    = Join-Path $SkillDir 'references'
New-Item -ItemType Directory -Force -Path $DataDir, $RefDir | Out-Null

$TODAY = Get-Date -Format 'yyyy-MM-dd'
# 知识库版本：每次内容变更必须递增，并同步往 CHANGELOG.md 追加一条（见 UPDATE.md 第 5、6 节）。
# 首版构建过程中改过内容也照样要留痕，不要因为「还没交付」就不记。
# 改这里之前，先在 CHANGELOG.md 追加对应条目。
$KBV   = '0.1.4'

# 章节规则：按任务地区收敛到章节（数据驱动，见 parse-report.txt 的地区统计）
$Chapters = @(
  [pscustomobject]@{ id='chapter-00-herta';    order=0; title='序幕·空间站「黑塔」'; regions=@('空间站「黑塔」'); slug='herta' }
  [pscustomobject]@{ id='chapter-01-jarilo';   order=1; title='第一幕·雅利洛-Ⅵ';    regions=@('雅利洛-Ⅵ','雅利洛-VI'); slug='jarilo' }
  [pscustomobject]@{ id='chapter-02-luofu';    order=2; title='第二幕·仙舟「罗浮」'; regions=@('仙舟「罗浮」'); slug='luofu' }
  [pscustomobject]@{ id='chapter-03-penacony'; order=3; title='第三幕·匹诺康尼';     regions=@('匹诺康尼'); slug='penacony' }
  [pscustomobject]@{ id='chapter-04-amphoreus';order=4; title='第四幕·翁法罗斯';     regions=@('翁法罗斯'); slug='amphoreus' }
  [pscustomobject]@{ id='chapter-05-paradise'; order=5; title='第五幕·二相乐园/千星城'; regions=@('二相乐园','千星城'); slug='paradise' }
)

function Clean-GistLine([string]$s) {
  $t = $s.Trim()
  $t = $t -replace '^#+\s*', ''
  $t = $t -replace '^\*+\s*', ''
  return $t.Trim()
}

function Split-Gist([string]$gist) {
  if (-not $gist) { return @() }
  $out = @()
  foreach ($ln in ($gist -split "`r?`n")) {
    $c = Clean-GistLine $ln
    if ($c) { $out += $c }
  }
  return $out
}

function Strip-Anchor([string]$s) {
  $i = $s.IndexOf('#')
  if ($i -ge 0) { return $s.Substring(0, $i) }
  return $s
}

# --- 读取索引，按地区归入章节 ---
$idx = Get-Content (Join-Path $OutDir 'mission-index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ("索引条目：" + $idx.Count)

$byChapter = @{}
foreach ($ch in $Chapters) { $byChapter[$ch.id] = New-Object System.Collections.ArrayList }

$unassigned = New-Object System.Collections.ArrayList
$mainQuests = New-Object System.Collections.ArrayList
$gistlessCount = 0      # 收录但 wiki 未填「剧情梗概」的任务数（摘要改由正文推导）
$nonTaskCount = 0       # 任务类型不是「开拓任务」而被跳过的条目数

# 章节别名表：任务地区字段的写法变体 -> 章节（写在数据里，避免猜）
$RegionAliases = @{
  '空间站「黑塔」'   = 'chapter-00-herta'
  '「黑塔」空间站'   = 'chapter-00-herta'
  '黑塔空间站'       = 'chapter-00-herta'
  '星穹列车'         = 'chapter-00-herta'
  '雅利洛-VI'        = 'chapter-01-jarilo'   # 半角 VI
  '雅利洛-Ⅵ'         = 'chapter-01-jarilo'
  '仙舟罗浮'         = 'chapter-02-luofu'
  '仙舟「罗浮」'     = 'chapter-02-luofu'
  '二相乐园'         = 'chapter-05-paradise'
  '千星城'           = 'chapter-05-paradise'
}

# 任务地区 -> 章节，优先级：精确 > 别名 > 带子地点前缀 > 整串包含（多地区并列兜底）
function Get-ChapterOf([string]$region) {
  if (-not $region) { return $null }
  $first = ($region -split '[、,，]')[0].Trim()
  if (-not $first) { return $null }

  foreach ($c in $Chapters) {
    foreach ($r in $c.regions) { if ($first -eq $r) { return $c } }
  }
  if ($RegionAliases.ContainsKey($first)) {
    $aid = $RegionAliases[$first]
    return ($Chapters | Where-Object { $_.id -eq $aid })
  }
  foreach ($c in $Chapters) {
    foreach ($r in $c.regions) { if ($first -like "$r-*") { return $c } }
  }
  foreach ($c in $Chapters) {
    foreach ($r in $c.regions) { if ($region -like "*$r*") { return $c } }
  }
  return $null
}

# ── 主线准入规则（2026-10-10 修正）────────────────────────────────────────────
# 曾经写成：$isMain = ($hasGist -or ($description.Length -gt 20 -and -not $series))
#   → `-not $series` 让后半段对任何属于系列的任务失效，整个表达式退化成「有梗概才收」，
#     于是把「wiki 尚未填写剧情梗概」误判成「非主线」。
#     后果：4.6 的「月升之前，与兽共舞」系列 4 个任务、4.0 的 2 个、以及「均衡」的试炼 6 个
#     共 13 个真正的开拓任务被静默丢弃（其中 5 个属于最新版本，用户一眼就看出漏了）。
# 正确做法：**用 wiki 的权威字段 `任务类型=开拓任务` 判定**（实测 217/217 全部为该值），
#           再要求「地区能归入已知章节」。不再用「梗概是否已填」这类编辑进度信号做准入。
foreach ($m in $idx) {
  if ($m.type -ne '开拓任务') { $nonTaskCount = $nonTaskCount + 1; continue }
  $ch = Get-ChapterOf $m.region
  if (-not $ch) { [void]$unassigned.Add($m); continue }
  $rec = [pscustomobject]@{ m = $m; chapter = $ch }
  [void]$mainQuests.Add($rec)
  [void]$byChapter[$ch.id].Add($rec)
  if (-not $m.hasGist) { $gistlessCount = $gistlessCount + 1 }
}

Write-Host ("主线任务数（依据 wiki 任务类型=开拓任务 全量收录）：" + $mainQuests.Count)
if ($gistlessCount -gt 0) { Write-Host ("  其中 wiki 未填「剧情梗概」、摘要改由正文推导：{0} 个" -f $gistlessCount) }
Write-Host ("未归章：" + $unassigned.Count)
foreach ($c in $Chapters) { Write-Host ("  {0,-22} {1}" -f $c.id, $byChapter[$c.id].Count) }

# --- 章内排序：主链位置（前置出现顺序） ---
function Sort-ChapterChain($list) {
  $names = @($list | ForEach-Object { $_.m.name })
  $nodes = @{}
  foreach ($rec in $list) {
    $pre = @($rec.m.prerequisite | ForEach-Object { Strip-Anchor $_ } | Where-Object { $names -contains $_ })
    $nodes[$rec.m.name] = [pscustomobject]@{ rec = $rec; pre = $pre; depth = -1 }
  }
  # 迭代求最长链深度，环则保底按原顺序
  for ($pass = 0; $pass -lt 60; $pass++) {
    $changed = $false
    foreach ($k in $nodes.Keys) {
      $d = 0
      foreach ($p in $nodes[$k].pre) { if ($nodes.ContainsKey($p)) { $d = [Math]::Max($d, $nodes[$p].depth + 1) } }
      if ($nodes[$k].depth -ne $d) { $nodes[$k].depth = $d; $changed = $true }
    }
    if (-not $changed) { break }
  }
  $ordered = @($list | Sort-Object @{ Expression = { if ($nodes[$_.m.name]) { $nodes[$_.m.name].depth } else { 0 } } }, @{ Expression = { $_.m.version } }, @{ Expression = { $_.m.name } })
  return $ordered
}

# 摘要压缩：梗概原文有质量，但一个任务上万字会撑爆上下文，按字数裁并标注省略
function Trim-Summary([string[]]$points, [int]$cap = 900) {
  if ($points.Count -eq 0) { return '' }
  $sb = New-Object System.Text.StringBuilder
  $used = 0; $i = 0; $omitted = 0
  foreach ($p in $points) {
    if ($used + $p.Length -gt $cap -and $i -ge 3) { $omitted++; continue }
    [void]$sb.AppendLine($p)
    $used += $p.Length
    $i++
  }
  $txt = $sb.ToString().Trim()
  if ($omitted -gt 0) { $txt += "`n（梗概另有 $omitted 条未展开，完整内容见 data 分片）" }
  return $txt
}

$manifestShards = New-Object System.Collections.ArrayList

# 系列总览页 -> 章节导语
$seriesPages = @()
$spFile = Join-Path $OutDir 'series-index.json'
if (Test-Path $spFile) {
  # 坑（实测，同类问题重复踩过）：PS 5.1 里 @( … | ConvertFrom-Json ) 会把顶层 JSON 数组
  # 压成「1 个元素、而该元素是 N 元素数组」的嵌套结构。
  # 这里曾表现为 $seriesPages.Count = 1，于是「章节导语」把 22 个系列页当成一个对象，
  # 一条导语渲染成几十行。
  # 正确写法：先用不带 @() 的语句取出数组，再 @() 包（此时会正常展开为 N 个元素）。
  $spRaw = Get-Content $spFile -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($null -ne $spRaw) { $seriesPages = @($spRaw) }
  # 双保险：万一仍是嵌套结构就摊平一层
  if ($seriesPages.Count -eq 1 -and $seriesPages[0] -is [array]) { $seriesPages = @($seriesPages[0]) }
  Write-Host ("系列总览页载入：{0} 条" -f $seriesPages.Count)
}

# 系列总览页 -> 章节：用「该系列的所属任务落在哪一章」投票决定。
# 不能只按地区字段匹配：总览页的地区字段常是分类页的全局值，会导致每个章节都吃进
# 全部 22 个总览页（曾因此让 chapter-02/03/04/05 的「章节导语」块逐字节完全相同）。
$seriesChapter = @{}
foreach ($ch in $Chapters) {
  foreach ($rec in @($byChapter[$ch.id])) {
    $sn = $rec.m.series
    if (-not $sn) { continue }
    if (-not $seriesChapter.ContainsKey($sn)) { $seriesChapter[$sn] = @{} }
    if (-not $seriesChapter[$sn].ContainsKey($ch.id)) { $seriesChapter[$sn][$ch.id] = 0 }
    $seriesChapter[$sn][$ch.id]++
  }
}
function Get-SeriesChapter([string]$seriesName) {
  if (-not $seriesChapter.ContainsKey($seriesName)) { return $null }
  $votes = $seriesChapter[$seriesName]
  $best = $null; $bestN = 0
  foreach ($k in $votes.Keys) { if ($votes[$k] -gt $bestN) { $best = $k; $bestN = $votes[$k] } }
  return $best
}

# 当 wiki 没有「剧情梗概」时，用正文推导一份摘要（方案 A）。
# 原则：只陈述能从正文直接读出的内容，不补写情节；并在条目里明确标注来源为「由正文推导」。
# 取料顺序：① 剧情分节标题串成流程链 ② 各分节首条旁白/场景 ③ 再不够则用各分节的代表台词。
function New-StorySummary($story, [string[]]$objectives, [int]$cap = 700) {
  if ($null -eq $story) { return '' }
  $parts = New-Object System.Collections.ArrayList

  if ($objectives -and $objectives.Count -gt 0) {
    $flow = ($objectives | Select-Object -First 6) -join ' → '
    [void]$parts.Add("（wiki 未填梗概，以下由任务正文推导）流程：$flow")
  } else {
    [void]$parts.Add('（wiki 未填梗概，以下由任务正文推导）')
  }

  $segs = @($story.segments)
  $used = 0
  foreach ($s in $segs) { if ($s.type -eq 'narration' -or $s.type -eq 'scene') { $used++ } }
  $want = 8
  $taken = 0
  if ($used -gt 0) {
    $step = [Math]::Max(1, [int][Math]::Floor($segs.Count / $want))
    for ($i = 0; $i -lt $segs.Count -and $taken -lt $want; $i += $step) {
      $s = $segs[$i]
      if ($s.type -ne 'narration' -and $s.type -ne 'scene') { continue }
      $t = $s.content
      if ($t.Length -lt 12) { continue }
      if ($t.Length -gt 140) { $t = $t.Substring(0, 140) + '…' }
      [void]$parts.Add("- $t")
      $taken++
    }
  }
  # 旁白不足时用台词补（保留说话者，便于判读）
  if ($taken -lt 4) {
    $step = [Math]::Max(1, [int][Math]::Floor($segs.Count / 6))
    $n = 0
    for ($i = 0; $i -lt $segs.Count -and $n -lt 6; $i += $step) {
      $s = $segs[$i]
      if ($s.type -ne 'dialogue') { continue }
      $t = $s.content
      if ($t.Length -lt 8) { continue }
      if ($t.Length -gt 120) { $t = $t.Substring(0, 120) + '…' }
      [void]$parts.Add("- [$($s.speaker)] $t")
      $n++
    }
  }

  $sb = New-Object System.Text.StringBuilder
  $len = 0
  foreach ($p in $parts) {
    if ($len + $p.Length -gt $cap) { break }
    [void]$sb.AppendLine($p)
    $len += $p.Length
  }
  return $sb.ToString().Trim()
}

foreach ($ch in $Chapters) {
  $list = @($byChapter[$ch.id])
  if ($list.Count -eq 0) { continue }
  $ordered = Sort-ChapterChain $list

  # 该章节的系列导语：只收「投票归属本章」的总览页，且必须有描述文字
  $intros = @()
  $seenIntro = @{}
  $snList = @($list | ForEach-Object { $_.m.series } | Where-Object { $_ } | Select-Object -Unique)
  foreach ($sn in $snList) {
    $owner = Get-SeriesChapter $sn
    if ($owner -ne $ch.id) { continue }
    if ($seenIntro.ContainsKey($sn)) { continue }
    $seenIntro[$sn] = $true
    $sp = $seriesPages | Where-Object { $_.name -eq $sn -and $_.description } | Select-Object -First 1
    if ($sp) { $intros += $sp }
  }
  Write-Host ("  {0}：章内系列 {1} 个 -> 导语 {2} 条" -f $ch.id, $snList.Count, $intros.Count)

  $entries = New-Object System.Collections.ArrayList
  $segLinks = New-Object System.Collections.ArrayList
  $pos = 0
  $charSet = New-Object 'System.Collections.Generic.HashSet[string]'

  foreach ($rec in $ordered) {
    $pos++
    $m = $rec.m
    $file = Join-Path $RawMissions ($m.file)
    if (-not (Test-Path $file)) { $file = Join-Path $RawMissions "$($m.name).wikitext" }
    $story = $null
    if (Test-Path $file) {
      $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
      $story = Extract-Story $text
    }

    # 关键片段：收紧预算，保持 refs 体量可控
    $keySegs = @()
    if ($story) { $keySegs = @(Pick-KeySegments $story -maxDialogue 12 -maxNarration 4) }

    # 出场人物：wiki 未填时，用正文里的说话者回填
    $chars = @($m.characters)
    if ($chars.Count -eq 0 -and $story) {
      $spk = New-Object System.Collections.ArrayList
      $seen = @{}
      foreach ($s in @($story.segments)) {
        if ($s.type -eq 'dialogue' -and $s.speaker -and $s.speaker -notmatch '^[？?]{1,}$') {
          if (-not $seen.ContainsKey($s.speaker)) { $seen[$s.speaker] = $true; [void]$spk.Add($s.speaker) }
        }
      }
      $chars = @($spk | Select-Object -First 20)
    }
    foreach ($c in $chars) { [void]$charSet.Add($c) }

    $gistPoints = @(Split-Gist $m.gist)
    $summary = Trim-Summary $gistPoints
    $summarySource = 'wiki-gist'
    $provisional = $false
    if (-not $summary) {
      # 方案 A：wiki 未填梗概 → 由任务正文推导摘要，并明确标注
      $summary = New-StorySummary $story $m.objectives
      if ($summary) { $summarySource = 'story-derived'; $provisional = $true }
      else { $summary = $m.description; $summarySource = 'wiki-description' }
    }

    $pre = @($m.prerequisite | ForEach-Object { Strip-Anchor $_ } | Where-Object { $_ })
    $trans = @()
    if ($pre.Count -gt 0) { $trans += ("承接：" + ($pre -join '、')) }
    $post = @($m.followup | ForEach-Object { Strip-Anchor $_ } | Where-Object { $_ })
    if ($post.Count -gt 0) { $trans += ("引出：" + ($post -join '、')) }

    $segObjs = @()
    foreach ($s in $keySegs) {
      $segObjs += [pscustomobject][ordered]@{
        type    = $s.type
        speaker = $s.speaker
        content = $s.content
      }
    }

    $entry = [pscustomobject][ordered]@{
      id           = ("quest:{0}-{1:d2}" -f $ch.slug, $pos)
      kind         = 'quest'
      name         = $m.name
      chapter      = $ch.title
      position     = $pos
      prerequisite = $(if ($pre.Count -gt 0) { $pre[0] } else { $null })
      followups    = @($post)
      region       = $m.region
      version      = $m.version
      summary      = $summary
      summary_source = $summarySource
      provisional  = $provisional
      key_points   = @($gistPoints)
      characters   = @($chars)
      objectives   = @($m.objectives)
      transitions  = $trans
      foreshadowing = @()
      segments     = $segObjs
      source_url   = ("https://wiki.biligame.com/sr/" + [uri]::EscapeDataString($m.name))
      history      = @()
    }
    [void]$entries.Add($entry)
    [void]$segLinks.Add([pscustomobject]@{ name = $m.name; dialogue = $(if ($story) { $story.counts.dialogue } else { 0 }); total = $(if ($story) { $story.segments.Count } else { 0 }); kept = $segObjs.Count })
  }

  # --- data JSON ---
  $provCount = @($entries | Where-Object { $_.provisional }).Count
  $covText = ("主线任务 {0} 个（依据 wiki `任务类型=开拓任务` 全量收录）；含任务流程、出场人物与关键片段（节选）" -f $entries.Count)
  if ($provCount -gt 0) {
    $covText += ("；其中 {0} 个任务的摘要在 wiki 上尚无「剧情梗概」，改由任务正文推导（summary_source=story-derived，provisional=true）" -f $provCount)
  }
  $frag = [pscustomobject][ordered]@{
    id               = $ch.id
    type             = 'chapter'
    title            = $ch.title
    chapter          = $ch.title
    chapter_order    = $ch.order
    source_urls      = @($entries | ForEach-Object { $_.source_url })
    license          = 'CC BY-NC-SA 4.0 (biligame wiki)'
    retrieved_at     = $TODAY
    last_updated     = $TODAY
    knowledge_version = $KBV
    coverage         = $covText
    confidence       = $(if ($provCount -gt 0) { 'high（{0} 个任务的摘要由正文推导，wiki 未填梗概）' -f $provCount } else { 'high' })
    supersedes       = @()
    tags             = @($ch.title, ($ch.regions -join '/')) + @($entries | ForEach-Object { $_.name })
    entities         = @($charSet) + @($ch.regions)
    entries          = @($entries)
  }
  $dataPath = Join-Path $DataDir ($ch.id + '.json')
  [System.IO.File]::WriteAllText($dataPath, ($frag | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("写入 data：{0}（{1} 条目，{2} KB）" -f ($ch.id + '.json'), $entries.Count, [int]((Get-Item $dataPath).Length / 1KB))

  # --- references markdown ---
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('---')
  [void]$sb.AppendLine("id: $($ch.id)")
  [void]$sb.AppendLine('type: chapter')
  [void]$sb.AppendLine("chapter: $($ch.title)")
  [void]$sb.AppendLine("title: $($ch.title) 主线剧情")
  [void]$sb.AppendLine('source_urls:')
  foreach ($u in ($entries | Select-Object -First 40 | ForEach-Object { $_.source_url })) { [void]$sb.AppendLine("  - $u") }
  [void]$sb.AppendLine("last_updated: $TODAY")
  [void]$sb.AppendLine("knowledge_version: $KBV")
  [void]$sb.AppendLine(("coverage: {0}" -f $covText))
  [void]$sb.AppendLine($(if ($provCount -gt 0) { "confidence: high（{0} 个任务摘要由正文推导）" -f $provCount } else { 'confidence: high' }))
  [void]$sb.AppendLine('supersedes: []')
  [void]$sb.AppendLine(("tags: [{0}]" -f (@($ch.title, ($ch.regions -join '/')) -join ', ')))
  [void]$sb.AppendLine('---')
  [void]$sb.AppendLine()
  [void]$sb.AppendLine("# $($ch.title) 主线剧情")
  [void]$sb.AppendLine()
  [void]$sb.AppendLine(("> 来源：biligame 星穹铁道 wiki（CC BY-NC-SA 4.0）。本分片收录 {0} 个主线任务（依据 wiki「任务类型=开拓任务」全量收录），按主线发生顺序排列；「关键片段」为节选（非逐字全文），完整字段见 data 分片。" -f $entries.Count))
  if ($provCount -gt 0) {
    [void]$sb.AppendLine(("> ⚠️ 其中 **{0} 个任务**在 wiki 上**尚无「剧情梗概」**，其摘要由任务正文推导（条目标注〔摘要由正文推导〕）。引用这些任务时须说明摘要非 wiki 原文。" -f $provCount))
  }
  [void]$sb.AppendLine()

  if ($intros.Count -gt 0) {
    [void]$sb.AppendLine('## 章节导语（wiki 原文）')
    [void]$sb.AppendLine()
    foreach ($sp in $intros) {
      # 关键：总览页的「描述」字段本身可能是多行（把全目录塞进来了），直接输出会让
      # 一条 bullet 变成几十行、看着像几十条导语。只取首个非空行并压平空白。
      $desc = ''
      foreach ($ln in ($sp.description -split '\r?\n')) {
        $t = ($ln -replace '\s+', ' ').Trim()
        if ($t) { $desc = $t; break }
      }
      if ($desc.Length -gt 200) { $desc = $desc.Substring(0, 200) + '…' }
      [void]$sb.AppendLine(("- **{0}**（{1}）：{2}" -f $sp.name, $sp.version, $desc))
    }
    [void]$sb.AppendLine()
  }

  foreach ($e in $entries) {
    [void]$sb.AppendLine("## $($e.id)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("- 任务名：$($e.name)")
    [void]$sb.AppendLine("- 地区：$($e.region) ｜ 版本：$($e.version)")
    [void]$sb.AppendLine("- 前置：$(if ($e.prerequisite) { $e.prerequisite } else { '（无，本章起点）' })")
    if ($e.followups.Count -gt 0) { [void]$sb.AppendLine("- 后续：$($e.followups -join '、')") }
    if ($e.characters.Count -gt 0) { [void]$sb.AppendLine("- 出场人物：$($e.characters -join '、')") }
    [void]$sb.AppendLine("- 来源：$($e.source_url)")
    [void]$sb.AppendLine()
    if ($e.provisional) {
      [void]$sb.AppendLine('**概要〔摘要由正文推导，wiki 未填梗概〕**')
    } else {
      [void]$sb.AppendLine('**概要**')
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($e.summary)
    [void]$sb.AppendLine()
    if ($e.objectives.Count -gt 0) {
      [void]$sb.AppendLine('**任务流程**')
      [void]$sb.AppendLine()
      $cap = [Math]::Min(8, $e.objectives.Count)
      for ($i = 0; $i -lt $cap; $i++) { [void]$sb.AppendLine("- $($e.objectives[$i])") }
      if ($e.objectives.Count -gt $cap) { [void]$sb.AppendLine(("- ……另 {0} 步见 data 分片" -f ($e.objectives.Count - $cap))) }
      [void]$sb.AppendLine()
    }
    if ($e.segments.Count -gt 0) {
      [void]$sb.AppendLine('**关键片段（节选）**')
      [void]$sb.AppendLine()
      foreach ($s in $e.segments) {
        switch ($s.type) {
          'dialogue'  { [void]$sb.AppendLine("- [$($s.speaker)] $($s.content)") }
          'narration' { [void]$sb.AppendLine("- （旁白）$($s.content)") }
          'scene'     { [void]$sb.AppendLine("- 〔场景〕$($s.content)") }
          'option'    { [void]$sb.AppendLine("- 〔选项〕$($s.content)") }
          default     { [void]$sb.AppendLine("- $($s.content)") }
        }
      }
      [void]$sb.AppendLine()
    }
  }

  $refPath = Join-Path $RefDir ($ch.id + '.md')
  [System.IO.File]::WriteAllText($refPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("写入 references：{0}（{1} KB）" -f ($ch.id + '.md'), [int]((Get-Item $refPath).Length / 1KB))

  [void]$manifestShards.Add([pscustomobject][ordered]@{
    id          = $ch.id
    type        = 'chapter'
    file        = ($ch.id + '.md')
    data        = ($ch.id + '.json')
    chapter     = $ch.title
    chapter_order = $ch.order
    entries     = $entries.Count
    source_urls = @("https://wiki.biligame.com/sr/开拓任务")
    retrieved_at = $TODAY
    last_updated = $TODAY
    version     = $KBV
    coverage    = $covText
    tags        = @($ch.title, ($ch.regions -join '/'), '主线', '开拓任务')
    entities    = @($charSet)
  })
}

# --- 章节总览索引（含未收录章节，供如实回答「尚未收录」） ---
$indexSb = New-Object System.Text.StringBuilder
[void]$indexSb.AppendLine('# 主线章节总览与查询路由')
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine('> 本表由构建流水线（`distill/parse-missions.ps1`，位于本 Skill 目录**之外**的开发工具目录）从 biligame wiki「开拓任务」分类（245 页）统计生成。')
[void]$indexSb.AppendLine('> **已收录**=本 Skill 内有详细分片；**未收录**=manifest 中无分片，回答时应如实说明并提示可按 UPDATE.md 补充。')
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine('| 章节 | 主线任务数 | 已收录 | 分片 |')
[void]$indexSb.AppendLine('| --- | --- | --- | --- |')
foreach ($ch in $Chapters) {
  $c = $byChapter[$ch.id].Count
  if ($c -eq 0) { continue }
  $shard = $manifestShards | Where-Object { $_.id -eq $ch.id }
  $mark = if ($shard) { '✅' } else { '—' }
  [void]$indexSb.AppendLine(("| {0} | {1} | {2} | {3} |" -f $ch.title, $c, $mark, $(if ($shard) { $shard.id } else { '未收录' })))
}
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine('## 全书目统计')
[void]$indexSb.AppendLine()
$nonMain = $idx.Count - $mainQuests.Count
# 分类总页数取自抓取阶段的任务清单（cat-*.json），比「任务页+系列页」更权威
$catTotalPages = 0
$catFile = Join-Path $Root 'raw\cat-开拓任务.json'
if (Test-Path $catFile) {
  $catJson = Get-Content $catFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $catTotalPages = @($catJson.query.categorymembers).Count
}
if ($catTotalPages -le 0) { $catTotalPages = $idx.Count + $seriesPages.Count }
$unparsed = $catTotalPages - $idx.Count - $seriesPages.Count
[void]$indexSb.AppendLine(("- 开拓任务分类总页数：{0}" -f $catTotalPages))
[void]$indexSb.AppendLine(("  - 任务页（`{{{{任务}}}}` 模板）：{0}" -f $idx.Count))
[void]$indexSb.AppendLine(("    - 已入库（判定依据：wiki 字段 `任务类型=开拓任务`，且任务地区可归入已知章节）：{0}" -f $mainQuests.Count))
if ($nonMain -gt 0) {
  [void]$indexSb.AppendLine(("    - 未入库：{0}（原因见下方「未归入章节」或字段缺失）" -f $nonMain))
}
[void]$indexSb.AppendLine(("  - 系列总览页（`{{{{系列任务}}}}` 模板，非任务，仅用作章节导语）：{0}" -f $seriesPages.Count))
if ($unparsed -gt 0) {
  [void]$indexSb.AppendLine(("  - 模板形态异常、未能识别的页面：{0}（已抓取但排除）" -f $unparsed))
}
[void]$indexSb.AppendLine(("- 未能归入已知章节：{0}" -f $unassigned.Count))
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine(("> 账目核对：{0}（任务页）+ {1}（系列总览页）{2} = {3}（分类总页数）；其中 {0} = {4}（已入库）+ {5}（未入库）。" -f `
    $idx.Count, $seriesPages.Count, $(if ($unparsed -gt 0) { " + $unparsed（模板异常）" } else { '' }), $catTotalPages, $mainQuests.Count, $nonMain))
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine(("> ⚠️ 收录判定**不再使用「wiki 是否已填剧情梗概」**作标准（0.1.3 起修正）。" +
  "旧版本据此漏掉了 13 个真正的开拓任务（含 4.6「月升之前，与兽共舞」整条 4 个），" +
  "因为它们的 `剧情梗概` 字段为空、被误判成非主线。"))
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine(("> 摘要来源：其中 {0} 个任务在 wiki 上**尚无「剧情梗概」**，其摘要由任务正文推导，" +
  "在条目里以 `summary_source: story-derived` / `provisional: true` 标注，回答时须说明摘要非 wiki 原文。" -f $gistlessCount))
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine('## 未收录章节怎么答')
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine('用户问到上表中「未收录」的章节时：')
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine('1. 明确说明本 Skill 目前只蒸馏了已收录章节，**该章节剧情不在知识库内**；')
[void]$indexSb.AppendLine('2. 不要凭模型记忆补写该章节剧情（会与 wiki 冲突，且无法标注来源）；')
[void]$indexSb.AppendLine('3. 提示用户可按 `UPDATE.md` 补充（素材放入 `inbox/`）。')
$indexPath = Join-Path $RefDir 'chapter-index.md'
[System.IO.File]::WriteAllText($indexPath, $indexSb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("写入 references：chapter-index.md")

# --- 世界观分片（星神 / 派系 / 术语 / 地点） ---
$wvFile = Join-Path $OutDir 'worldview-sections.json'
$FragmentMeta = @{
  'worldview-aeons'     = @{ title = '星神与令使';       file = 'worldview-aeons.md';     slug = 'aeon' }
  'worldview-paths'     = @{ title = '命途（世界观义）';  file = 'worldview-paths.md';     slug = 'path' }
  'worldview-factions'  = @{ title = '派系与组织';       file = 'worldview-factions.md';  slug = 'faction' }
  'worldview-locations' = @{ title = '主线舞台地点';     file = 'worldview-locations.md'; slug = 'place' }
  'glossary'            = @{ title = '专有名词表';       file = 'glossary.md';            slug = 'term' }
}

if (Test-Path $wvFile) {
  # 坑（实测）：Windows PowerShell 5.1 里 @( … | ConvertFrom-Json ) 会把顶层 JSON 数组
  # 再包一层 → 得到「1 个元素，而该元素是 245 元素数组」的畸形结构，
  # 于是后续 Where-Object 全部失效、每个分片都吞下全部条目（表现为「1 条目 / 281KB」）。
  # 正确做法：直接取 ConvertFrom-Json 的结果，不要用 @() 包。
  $wv = Get-Content $wvFile -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($null -eq $wv) { $wv = @() }
  Write-Host ("世界观段落：{0}" -f $wv.Count)
  foreach ($fragId in ($FragmentMeta.Keys | Sort-Object)) {
    $meta = $FragmentMeta[$fragId]
    $sections = @($wv | Where-Object { $_.fragment -eq $fragId })
    if ($sections.Count -eq 0) { continue }

    $wEntries = New-Object System.Collections.ArrayList
    $seen = @{}
    $n = 0
    foreach ($s in $sections) {
      $n++
      $slug = ("{0}-{1:d2}" -f $meta.slug, $n)
      $wEntries += [pscustomobject][ordered]@{
        id         = ("{0}:{1}" -f $s.kind, $slug)
        kind       = $s.kind
        name       = $s.title
        chapter    = $null
        position   = $n
        summary    = $s.text
        key_points = @()
        source_url = $s.source_url
        history    = @()
      }
    }

    $wfrag = [pscustomobject][ordered]@{
      id                = $fragId
      type              = 'worldview'
      title             = $meta.title
      chapter           = $null
      chapter_order     = $null
      source_urls       = @($sections | ForEach-Object { $_.source_url } | Select-Object -Unique)
      license           = 'CC BY-NC-SA 4.0 (biligame wiki)'
      retrieved_at      = $TODAY
      last_updated      = $TODAY
      knowledge_version = $KBV
      coverage          = ("{0} 个条目，逐条为 wiki 原文释义（已去表格/模板噪声）" -f $wEntries.Count)
      confidence        = 'high'
      supersedes        = @()
      tags              = @($meta.title) + @($sections | ForEach-Object { $_.page } | Select-Object -Unique)
      entities          = @($wEntries | ForEach-Object { $_.name })
      entries           = @($wEntries)
    }
    $wDataPath = Join-Path $DataDir ($fragId + '.json')
    [System.IO.File]::WriteAllText($wDataPath, ($wfrag | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

    $wsb = New-Object System.Text.StringBuilder
    [void]$wsb.AppendLine('---')
    [void]$wsb.AppendLine("id: $fragId")
    [void]$wsb.AppendLine('type: worldview')
    [void]$wsb.AppendLine("title: $($meta.title)")
    [void]$wsb.AppendLine('source_urls:')
    foreach ($u in ($wfrag.source_urls | Select-Object -First 20)) { [void]$wsb.AppendLine("  - $u") }
    [void]$wsb.AppendLine("last_updated: $TODAY")
    [void]$wsb.AppendLine("knowledge_version: $KBV")
    [void]$wsb.AppendLine(("coverage: {0} 个条目释义" -f $wEntries.Count))
    [void]$wsb.AppendLine('confidence: high')
    [void]$wsb.AppendLine('supersedes: []')
    [void]$wsb.AppendLine(("tags: [{0}]" -f ($wfrag.tags -join ', ')))
    [void]$wsb.AppendLine('---')
    [void]$wsb.AppendLine()
    [void]$wsb.AppendLine("# $($meta.title)")
    [void]$wsb.AppendLine()
    [void]$wsb.AppendLine('> 来源：biligame 星穹铁道 wiki（CC BY-NC-SA 4.0）。以下为 wiki 释义原文的清洗版，未做主观改写。')
    [void]$wsb.AppendLine()
    foreach ($e in $wEntries) {
      [void]$wsb.AppendLine("## $($e.id)")
      [void]$wsb.AppendLine()
      [void]$wsb.AppendLine("- 名称：$($e.name)")
      [void]$wsb.AppendLine("- 来源：$($e.source_url)")
      [void]$wsb.AppendLine()
      [void]$wsb.AppendLine($e.summary)
      [void]$wsb.AppendLine()
    }
    $wRefPath = Join-Path $RefDir $meta.file
    [System.IO.File]::WriteAllText($wRefPath, $wsb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("写入世界观分片：{0}（{1} 条目，{2} KB）" -f $meta.file, $wEntries.Count, [int]((Get-Item $wRefPath).Length / 1KB))

    [void]$manifestShards.Add([pscustomobject][ordered]@{
      id           = $fragId
      type         = 'worldview'
      file         = $meta.file
      data         = ($fragId + '.json')
      chapter      = $null
      chapter_order = $null
      entries      = $wEntries.Count
      source_urls  = @($wfrag.source_urls)
      retrieved_at = $TODAY
      last_updated = $TODAY
      version      = $KBV
      coverage     = $wfrag.coverage
      tags         = @($wfrag.tags)
      entities     = @($wfrag.entities)
    })
  }
} else {
  Write-Host '未找到 worldview-sections.json，跳过世界观分片'
}

# --- 人工策展术语：并入 glossary 分片 ---
# wiki 上「谐乐大典」「十二泰坦」这类事件/概念没有独立页面，释义散落在章节正文与地点页里，
# 只能靠全文检索拼出来。curated-terms.json 把这些归纳固化成独立词条，便于按 ID 直接命中。
# 这些条目标 derived=true：回答时必须说明是「对 wiki 原文的归纳」，不能说成 wiki 有该独立条目。
$curatedFile = Join-Path $Root 'curated-terms.json'
if (Test-Path $curatedFile) {
  $curated = Get-Content $curatedFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $glossaryPath = Join-Path $DataDir 'glossary.json'
  if (Test-Path $glossaryPath) {
    $gfrag = Get-Content $glossaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    # 用 ArrayList 承载：`$existing += ...` 在循环里会重建数组，
    # 导致后面的刷新循环读不到刚追加的条目（曾因此让「刷新」分支永不命中）。
    $existing = New-Object System.Collections.ArrayList
    foreach ($x in @($gfrag.entries)) { [void]$existing.Add($x) }
    $added = 0
    foreach ($c in $curated.entries) {
      $hit = $false
      foreach ($x in $existing) { if ($x.id -eq $c.id) { $hit = $true; break } }
      if ($hit) { continue }
      [void]$existing.Add([pscustomobject][ordered]@{
        id         = $c.id
        kind       = $c.kind
        name       = $c.name
        chapter    = $null
        position   = ($existing.Count + 1)
        summary    = $c.summary
        summary_source = 'curated'
        provisional = $false
        key_points = @($c.key_points)
        derived    = $true
        # 来源冲突：归纳时若不同来源互相矛盾，必须并列保留、不择一作为定论（见 UPDATE.md「冲突不覆盖」）
        conflicts  = @($c.conflicts)
        source_refs = @($c.source_refs)
        source_url = @($c.source_refs)[0]
        last_updated = $TODAY
        history    = @()
      })
      $added++
    }
    # 策展条目的 history 台账：**存放在 curated-terms.json 里**，这里只负责带过去。
    #
    # ⚠️ 为什么不能靠比对推导（踩了很久的坑）：
    #    data/glossary.json 是派生产物 —— 世界观分片渲染会先把它重置成「只含 wiki 抓来的条目」，
    #    策展条目每轮都被重新并入。既然生成器每轮都会把 curated 内容写进 data，
    #    那么下一轮读到的 data 必然等于 curated 内容，**任何比对都恒为"无差异"**，
    #    history 永远推导不出来（实测确认）。
    #    因此修订台账只能放在源文件里，逐轮原样带过；修订时由维护者把旧内容追加进去。
    $prevById = @{}
    foreach ($x in @($gfrag.entries)) { $prevById[$x.id] = $x }
    $updated = 0
    foreach ($c in $curated.entries) {
      $idx = -1
      for ($k = 0; $k -lt $existing.Count; $k++) { if ($existing[$k].id -eq $c.id) { $idx = $k; break } }
      if ($idx -lt 0) { continue }
      $cur = $existing[$idx]

      # 台账来自源文件
      $hist = @()
      if ($c.PSObject.Properties.Name -contains 'history') { $hist = @($c.history) }

      # 内容是否与上一轮磁盘状态不同（仅用于提示，不是留痕依据）
      $prev = if ($prevById.ContainsKey($c.id)) { $prevById[$c.id] } else { $null }
      $contentChanged = $false
      if ($null -ne $prev) {
        $oldC = @($prev.conflicts | Where-Object { $_ -and $_.field })
        $newC = @($c.conflicts)
        $contentChanged = ($prev.summary -ne $c.summary) -or
          ((@($prev.key_points) -join "`n") -ne (@($c.key_points) -join "`n")) -or
          ((@($oldC | ForEach-Object { "$($_.field)|$($_.account_a)|$($_.status)" }) -join "`n") -ne
           (@($newC | ForEach-Object { "$($_.field)|$($_.account_a)|$($_.status)" }) -join "`n"))
      }

      $newObj = [pscustomobject][ordered]@{
        id             = $cur.id
        kind           = $cur.kind
        name           = $cur.name
        chapter        = $cur.chapter
        position       = $cur.position
        summary        = $c.summary
        summary_source = 'curated'
        provisional    = $false
        key_points     = @($c.key_points)
        derived        = $true
        conflicts      = @($c.conflicts)
        source_refs    = @($c.source_refs)
        source_url     = @($c.source_refs)[0]
        last_updated   = $TODAY
        history        = $hist
      }
      $existing[$idx] = $newObj
      if ($contentChanged) { $updated++ }
    }
    if ($added -gt 0 -or $updated -gt 0) {
      $gfrag.entries = $existing.ToArray()
      # 同样要按「元素有 field」判定：没有 conflicts 键的条目 @($_.conflicts) 是 @($null)
      $conflictCount = @($existing.ToArray() | Where-Object { @($_.conflicts | Where-Object { $_ -and $_.field }).Count -gt 0 }).Count
      $gfrag.coverage = ("{0} 个条目，逐条为 wiki 原文释义（已去表格/模板噪声）；其中 {1} 条为人工策展归纳（derived=true）{2}" -f $existing.Count, (@($existing.ToArray() | Where-Object { $_.derived }).Count), $(if ($conflictCount -gt 0) { "，$conflictCount 条含未裁定的来源冲突（conflicts）" } else { '' }))
      $gfrag.entities = @($existing.ToArray() | ForEach-Object { $_.name })
      [System.IO.File]::WriteAllText($glossaryPath, ($gfrag | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

      # 同步重建 glossary.md（按 ID 顺序排列，标注 derived 条目）
      $gsb = New-Object System.Text.StringBuilder
      [void]$gsb.AppendLine('---')
      [void]$gsb.AppendLine('id: glossary')
      [void]$gsb.AppendLine('type: worldview')
      [void]$gsb.AppendLine('title: 专有名词表')
      [void]$gsb.AppendLine('source_urls:')
      foreach ($u in (@($gfrag.source_urls) | Select-Object -First 20)) { [void]$gsb.AppendLine("  - $u") }
      [void]$gsb.AppendLine("last_updated: $TODAY")
      [void]$gsb.AppendLine("knowledge_version: $KBV")
      [void]$gsb.AppendLine(("coverage: {0}" -f $gfrag.coverage))
      [void]$gsb.AppendLine('confidence: high')
      [void]$gsb.AppendLine('supersedes: []')
      [void]$gsb.AppendLine(("tags: [{0}]" -f (@($gfrag.tags) -join ', ')))
      [void]$gsb.AppendLine('---')
      [void]$gsb.AppendLine()
      [void]$gsb.AppendLine('# 专有名词表')
      [void]$gsb.AppendLine()
      [void]$gsb.AppendLine('> 来源：biligame 星穹铁道 wiki（CC BY-NC-SA 4.0）。')
      [void]$gsb.AppendLine('> 标 **〔归纳〕** 的条目是对 wiki 多页原文的人工归纳（wiki 上无该独立页面），回答时须说明这一点。')
      [void]$gsb.AppendLine('> 标 **⚠️ 来源冲突** 的条目，其来源互相矛盾且**尚未裁定**：回答时两种说法都要讲，不得只挑一种当定论。')
      [void]$gsb.AppendLine()
      foreach ($e in $existing) {
        # 注意：条目 JSON 里可能根本没有 conflicts 键，此时 @($e.conflicts) == @($null)、
        # Count 为 1（PS 的坑）。必须按「元素是否有 field」判定，否则会给所有普通词条
        # 吐一个空的「⚠️ 来源冲突」块（曾把 39/41 条都污染成空壳）。
        $cfList = @($e.conflicts | Where-Object { $_ -and $_.field })
        [void]$gsb.AppendLine("## $($e.id)")
        [void]$gsb.AppendLine()
        [void]$gsb.AppendLine(("- 名称：$($e.name){0}{1}" -f $(if ($e.derived) { '  **〔归纳〕**' } else { '' }), $(if ($cfList.Count -gt 0) { '  **⚠️ 来源冲突**' } else { '' })))
        if ($e.derived) {
          foreach ($u in @($e.source_refs)) { [void]$gsb.AppendLine("- 归纳自：$u") }
        } else {
          [void]$gsb.AppendLine("- 来源：$($e.source_url)")
        }
        [void]$gsb.AppendLine()
        [void]$gsb.AppendLine($e.summary)
        [void]$gsb.AppendLine()
        # 来源冲突：并列两说、不裁定，回答时必须转述给用户
        if ($cfList.Count -gt 0) {
          [void]$gsb.AppendLine('**⚠️ 来源冲突（未裁定，回答时必须两说并列告知用户）**')
          [void]$gsb.AppendLine()
          foreach ($c in $cfList) {
            [void]$gsb.AppendLine(("- 争议点：$($c.field)　状态：$($c.status)"))
            [void]$gsb.AppendLine(("  - 说法 A：$($c.account_a)"))
            [void]$gsb.AppendLine(("  - 说法 B：$($c.account_b)"))
            if ($c.note) { [void]$gsb.AppendLine(("  - 处理：$($c.note)")) }
          }
          [void]$gsb.AppendLine()
        }
        if (@($e.key_points).Count -gt 0) {
          [void]$gsb.AppendLine('**要点**')
          [void]$gsb.AppendLine()
          foreach ($k in @($e.key_points)) { [void]$gsb.AppendLine("- $k") }
          [void]$gsb.AppendLine()
        }
      }
      [System.IO.File]::WriteAllText((Join-Path $RefDir 'glossary.md'), $gsb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

      # 更新 manifest 记录
      $gshard = $manifestShards | Where-Object { $_.id -eq 'glossary' }
      if ($gshard) {
        $gshard.entries = $existing.Count
        $gshard.coverage = $gfrag.coverage
        $gshard.entities = @($gfrag.entities)
      }
      Write-Host ("策展术语并入 glossary：新增 {0} 条、刷新 {1} 条（共 {2} 条，{3} KB）" -f $added, $updated, $existing.Count, [int]((Get-Item (Join-Path $RefDir 'glossary.md')).Length / 1KB))
    }
  } else {
    Write-Host '未找到 data/glossary.json，跳过策展术语并入'
  }
} else {
  Write-Host '未找到 curated-terms.json，跳过策展术语并入'
}

# --- manifest.yaml：查询路由与版本信息的唯一依据 ---
$sortedShards = @($manifestShards | Sort-Object @{ Expression = { if ($null -ne $_.chapter_order) { [int]$_.chapter_order } else { 99 } } }, id)
$msb = New-Object System.Text.StringBuilder
[void]$msb.AppendLine('# dsh-hsr-lore 知识分片清单')
[void]$msb.AppendLine('# 由 distill/gen-fragments.ps1 生成；查询路由与更新管理都以此文件为准，不要在 SKILL.md 里硬编码章节列表。')
[void]$msb.AppendLine()
[void]$msb.AppendLine("knowledge_version: $KBV")
[void]$msb.AppendLine("last_updated: $TODAY")
[void]$msb.AppendLine('license: CC BY-NC-SA 4.0 (biligame wiki)')
[void]$msb.AppendLine('source: https://wiki.biligame.com/sr/')
[void]$msb.AppendLine('entry_count: ' + (@($sortedShards | Measure-Object -Property entries -Sum).Sum))
[void]$msb.AppendLine()
[void]$msb.AppendLine('# 辅助索引（不是知识分片、没有 entries；查询路由的第一步先读它）')
[void]$msb.AppendLine('indexes:')
[void]$msb.AppendLine('  - id: chapter-index')
[void]$msb.AppendLine('    file: references/chapter-index.md')
[void]$msb.AppendLine('    title: 主线章节总览与查询路由（含已收录/未收录判定与账目核对）')
[void]$msb.AppendLine(("    last_updated: {0}" -f $TODAY))
[void]$msb.AppendLine()
[void]$msb.AppendLine('shards:')
foreach ($s in $sortedShards) {
  [void]$msb.AppendLine(("  - id: {0}" -f $s.id))
  [void]$msb.AppendLine(("    type: {0}" -f $s.type))
  [void]$msb.AppendLine(("    file: references/{0}" -f $s.file))
  [void]$msb.AppendLine(("    data: data/{0}" -f $s.data))
  [void]$msb.AppendLine(("    title: {0}" -f $s.chapter))
  [void]$msb.AppendLine(("    chapter_order: {0}" -f $(if ($null -ne $s.chapter_order) { $s.chapter_order } else { 'null' })))
  [void]$msb.AppendLine(("    entries: {0}" -f $s.entries))
  [void]$msb.AppendLine(("    coverage: {0}" -f $s.coverage))
  [void]$msb.AppendLine(("    retrieved_at: {0}" -f $s.retrieved_at))
  [void]$msb.AppendLine(("    last_updated: {0}" -f $s.last_updated))
  [void]$msb.AppendLine(("    version: {0}" -f $s.version))
  $tags = @($s.tags) | Where-Object { $_ } | Select-Object -Unique -First 30
  [void]$msb.AppendLine(("    tags: [{0}]" -f ($tags -join ', ')))
  $ents = @($s.entities) | Where-Object { $_ } | Select-Object -First 60
  [void]$msb.AppendLine(("    entities: [{0}]" -f ($ents -join ', ')))
  [void]$msb.AppendLine('    source_urls:')
  foreach ($u in (@($s.source_urls) | Select-Object -First 8)) { [void]$msb.AppendLine("      - $u") }
}
[void]$msb.AppendLine()
[void]$msb.AppendLine('# 未收录章节：回答时须说明「知识库尚未收录」，不得凭记忆补写')
[void]$msb.AppendLine('not_covered:')
$ncCount = 0
foreach ($ch in $Chapters) {
  if ($byChapter[$ch.id].Count -eq 0) { continue }
  $has = $manifestShards | Where-Object { $_.id -eq $ch.id }
  if (-not $has) { [void]$msb.AppendLine(("  - {0}（约 {1} 个主线任务）" -f $ch.title, $byChapter[$ch.id].Count)); $ncCount++ }
}
# YAML 里空列表必须写成 []，否则解析结果为 null，「未收录」判断会失效
if ($ncCount -eq 0) { [void]$msb.AppendLine('  []   # 当前所有已识别章节均已收录') }
$manifestPath = Join-Path $SkillDir 'manifest.yaml'
[System.IO.File]::WriteAllText($manifestPath, $msb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("写入 manifest.yaml（{0} 个分片）" -f $sortedShards.Count)

# --- 同步 SKILL.md 里的分片速查表数字 ---
# 只改表里的「条目数」一列，不碰 SKILL.md 的其余正文（它是手写的逻辑层）。
# 否则每次更新都会让速查表与 manifest 漂移（0.1.1 就漏掉了 glossary 39->41）。
$skillMd = Join-Path $SkillDir 'SKILL.md'
if (Test-Path $skillMd) {
  $md = [System.IO.File]::ReadAllText($skillMd, [System.Text.Encoding]::UTF8)
  $patched = 0
  foreach ($s in $sortedShards) {
    if ($s.type -eq 'chapter') {
      # 章节行形如： | `chapter-01-jarilo` | 第一幕·雅利洛-Ⅵ | 24 个任务 |
      $pat = '(\|\s*`' + [regex]::Escape($s.id) + '`\s*\|[^|]*\|\s*)\d+(\s*个任务\s*\|)'
      $new = $md -replace $pat, ('${1}' + $s.entries + '${2}')
    } else {
      # 世界观行形如： | `glossary` | 专有名词表 | 39 条 |
      $pat = '(\|\s*`' + [regex]::Escape($s.id) + '`\s*\|[^|]*\|\s*)\d+(\s*条\s*\|)'
      $new = $md -replace $pat, ('${1}' + $s.entries + '${2}')
    }
    if ($new -ne $md) { $patched++; $md = $new }
  }
  # 同步「大分片要选择性读」那段里写的体积（曾漂移：chapter-05 从 179KB 长到 194KB）
  foreach ($s in $sortedShards) {
    $rf = Join-Path $RefDir $s.file
    if (-not (Test-Path $rf)) { continue }
    $kb = [int][Math]::Round((Get-Item $rf).Length / 1KB)
    $pat = '(`' + [regex]::Escape($s.file) + '`（约 )\d+(KB）)'
    $new = $md -replace $pat, ('${1}' + $kb + '${2}')
    if ($new -ne $md) { $patched++; $md = $new }
  }
  if ($patched -gt 0) {
    [System.IO.File]::WriteAllText($skillMd, $md, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("同步 SKILL.md 速查表/体积：{0} 处已更新" -f $patched)
  } else {
    Write-Host 'SKILL.md 速查表与体积无需更新（已一致）'
  }
}

# 供后续 manifest/dashboard 使用（ArrayList 必须先 ToArray，否则只序列化首个元素）
$manifestShards.ToArray() | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $OutDir 'shards.json') -Encoding UTF8
Write-Host '完成。'
