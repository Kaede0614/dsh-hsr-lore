# story-extract.ps1 - 从单个任务页 wikitext 抽取「剧情内容」正文，切分为结构片段
# 供 gen-fragments.ps1 调用。必须以 UTF-8 with BOM 保存。
#
# 输出对象字段：
#   storySteps  : 任务流程分节（剧情内容里 === 标题 === 的层级结构）
#   transitions : 折叠的过场动画/开场动画，内部按 dialogue/narration 切好
#   segments    : 该任务正文里按顺序排列的对话/旁白/场景/选项片段
#   counts      : 各类片段计数
#
# 依赖 clean-wikitext.ps1（Strip-Inline / Expand-Annotation / Get-TopLevelTemplates）

. (Join-Path $PSScriptRoot 'clean-wikitext.ps1')

function Split-Segments([string]$block) {
  # 把一段正文按行切成片段
  $segs = New-Object System.Collections.ArrayList
  foreach ($raw in ($block -split "`r?`n")) {
    $line = $raw.TrimEnd().TrimStart(' ', "`t")
    if (-not $line) { continue }

    # 剧情选项标记（由 Extract-Story 预扫描替换而来）
    if ($line -match '^\x01OPT(\d+)\x01$') {
      [void]$segs.Add([pscustomobject]@{ type = 'optionMarker'; speaker = $null; content = $Matches[1] })
      continue
    }

    # 折叠块 -> 场景标题 + 递归内部
    if ($line -match '^\{\{折叠') {
      $t = [regex]::Match($line, '标题\s*=\s*([^|}]*)')
      if ($t.Success) {
        $title = Strip-Inline $t.Groups[1].Value
        if ($title -and $title -notmatch '^(展开|收起)$') {
          [void]$segs.Add([pscustomobject]@{ type = 'scene'; speaker = $null; content = $title })
        }
      }
      $inner = $line -replace '^\{\{折叠[^|]*\|', ''
      $inner = $inner -replace '\|?\s*折叠\s*=\s*[^|}]*', ''
      $inner = $inner -replace '\|?\s*标题\s*=\s*[^|]*', ''
      $inner = $inner -replace '^\|', ''
      $inner = $inner -replace '\}\}\s*$', ''
      foreach ($s in (Split-Segments $inner)) { [void]$segs.Add($s) }
      continue
    }
    # 任务描述模板 -> 场景
    if ($line -match '^\{\{任务描述\|') {
      $parts = ($line -replace '^\{\{任务描述\|', '') -replace '\}\}\s*$', ''
      $bits = $parts -split '\|'
      $txt = Strip-Inline $bits[0]
      if ($txt) { [void]$segs.Add([pscustomobject]@{ type = 'scene'; speaker = $null; content = $txt }) }
      if ($bits.Count -gt 1) {
        $loc = Strip-Inline $bits[1]
        if ($loc) { [void]$segs.Add([pscustomobject]@{ type = 'scene'; speaker = $null; content = "地点：$loc" }) }
      }
      continue
    }
    # 行首 : 过场旁白
    if ($line -match '^:\s*(.+)$') {
      $txt = Strip-Inline $Matches[1]
      if ($txt) { [void]$segs.Add([pscustomobject]@{ type = 'narration'; speaker = $null; content = $txt }) }
      continue
    }
    # 对话：*角色：台词
    if ($line -match '^\*+\s*([^：:]{1,20})[：:]\s*(.+)$') {
      $spk = Strip-Inline $Matches[1]
      $txt = Strip-Inline $Matches[2]
      if ($txt) { [void]$segs.Add([pscustomobject]@{ type = 'dialogue'; speaker = $spk; content = $txt }) }
      continue
    }
    # 选项：**文本
    if ($line -match '^\*\*+\s*(.+)$') {
      $txt = Strip-Inline $Matches[1]
      if ($txt) { [void]$segs.Add([pscustomobject]@{ type = 'option'; speaker = $null; content = $txt }) }
      continue
    }
    # 其余 bullet -> 旁白
    if ($line -match '^\*\s*(.+)$') {
      $txt = Strip-Inline $Matches[1]
      if ($txt) { [void]$segs.Add([pscustomobject]@{ type = 'narration'; speaker = $null; content = $txt }) }
      continue
    }
    # 普通整行文本 -> 旁白
    $txt = Strip-Inline $line
    if ($txt) { [void]$segs.Add([pscustomobject]@{ type = 'narration'; speaker = $null; content = $txt }) }
  }
  return $segs
}

# 解析 {{剧情选项|选项1=…|剧情1=…}} 块（可跨行）
function Parse-OptionTemplate([string]$tpl, [hashtable]$acc, [int]$marker) {
  $body = ($tpl -replace '^\{\{剧情选项\s*\|?', '') -replace '\}\}\s*$', ''
  $body = $body -replace "`r?`n", '|'
  $opts = @{}
  $linesTxt = ''
  foreach ($piece in ($body -split '\|')) {
    if (-not $piece.Trim()) { continue }
    $m = [regex]::Match($piece, '^(选项|剧情)(\d+)\s*=\s*(.*)$')
    if (-not $m.Success) { continue }
    $kind = $m.Groups[1].Value; $n = [int]$m.Groups[2].Value; $val = $m.Groups[3].Value
    if ($kind -eq '选项') { $opts[$n] = (Strip-Inline $val) }
    else {
      # 剧情N：形如 *说话者：台词（可多行，已合并为 |）
      $seg = Strip-Inline ($val -replace '^\*+\s*', '')
      if ($seg) { $linesTxt += $seg + "`n" }
    }
  }
  $optionTexts = @()
  foreach ($k in (($opts.Keys | Sort-Object { [int]$_ }))) { if ($opts[$k]) { $optionTexts += $opts[$k] } }
  $acc[$marker] = [pscustomobject]@{ options = $optionTexts; story = ($linesTxt.Trim()) }
}

# 把正文里的剧情选项块换成标记，并收集其内容
function Convert-OptionBlocks([string]$body, [hashtable]$acc) {
  $out = $body
  $matches = [regex]::Matches($body, '(?s)\{\{剧情选项.*?\}\}')
  $marker = 0
  # 从后往前替换，避免偏移失效
  for ($i = $matches.Count - 1; $i -ge 0; $i--) {
    $marker++
    $m = $matches[$i]
    Parse-OptionTemplate $m.Value $acc $marker
    $repl = "`n" + [char]1 + "OPT$marker" + [char]1 + "`n"
    $out = $out.Substring(0, $m.Index) + $repl + $out.Substring($m.Index + $m.Length)
  }
  return $out
}

# 把 optionMarker 展开为 option 段落 + 剧情台词
function Expand-OptionMarkers($segs, [hashtable]$acc) {
  $out = New-Object System.Collections.ArrayList
  foreach ($s in $segs) {
    if ($s.type -ne 'optionMarker') { [void]$out.Add($s); continue }
    $idx = [int]$s.content
    if (-not $acc.ContainsKey($idx)) { continue }
    $info = $acc[$idx]
    if ($info.options.Count -gt 0) {
      $joined = ($info.options | ForEach-Object { $_ }) -join ' ／ '
      [void]$out.Add([pscustomobject]@{ type = 'option'; speaker = $null; content = $joined })
    }
    foreach ($ln in ($info.story -split "`n")) {
      $ln = $ln.Trim()
      if (-not $ln) { continue }
      if ($ln -match '^([^：:]{1,20})[：:]\s*(.+)$') {
        [void]$out.Add([pscustomobject]@{ type = 'dialogue'; speaker = (Strip-Inline $Matches[1]); content = (Strip-Inline $Matches[2]) })
      } else {
        [void]$out.Add([pscustomobject]@{ type = 'narration'; speaker = $null; content = $ln })
      }
    }
  }
  return $out
}

function Extract-Story([string]$text) {
  $si = $text.IndexOf('==剧情内容==')
  $result = [ordered]@{
    storySteps  = (New-Object System.Collections.ArrayList)
    transitions = (New-Object System.Collections.ArrayList)
    segments    = @()
    counts      = $null
  }
  if ($si -lt 0) {
    $result.counts = [ordered]@{ dialogue = 0; narration = 0; scene = 0; option = 0 }
    return $result
  }
  $body = $text.Substring($si)

  # 先把 {{剧情选项|…}} 块换成标记并收集内容（必须早于分节与切分）
  $optAcc = @{}
  $body = Convert-OptionBlocks $body $optAcc

  # 过场/开场动画：正文里所有折叠模板中标题含「动画」者
  foreach ($tpl in (Get-TopLevelTemplates $body)) {
    if ($tpl.text -notmatch '^\{\{折叠') { continue }
    $t = [regex]::Match($tpl.text, '标题\s*=\s*([^|}]*)')
    if (-not $t.Success) { continue }
    $title = Strip-Inline $t.Groups[1].Value
    if ($title -notmatch '动画') { continue }
    $inner = $tpl.text -replace '^\{\{折叠[^|]*\|', ''
    $inner = $inner -replace '\|?\s*折叠\s*=\s*[^|}]*', ''
    $inner = $inner -replace '\|?\s*标题\s*=\s*[^|]*', ''
    $inner = $inner -replace '^\|', ''
    $inner = $inner -replace '\}\}\s*$', ''
    $segs = @(Split-Segments $inner)
    if ($segs.Count -gt 0) {
      [void]$result.transitions.Add([pscustomobject]@{ title = $title; segments = $segs })
    }
  }

  # 按 === 标题 === 切任务流程分节
  $parts = [regex]::Split($body, '(?m)^===\s*(.+?)\s*===\s*$')
  $all = New-Object System.Collections.ArrayList
  if ($parts.Count -eq 1) {
    foreach ($s in (Expand-OptionMarkers (Split-Segments ($body -replace '^==剧情内容==', '')) $optAcc)) { [void]$all.Add($s) }
  } else {
    $idx = 1
    while ($idx + 1 -lt $parts.Count) {
      $stepTitle = Strip-Inline $parts[$idx]
      $segs = @(Expand-OptionMarkers (Split-Segments $parts[$idx + 1]) $optAcc)
      if ($stepTitle) {
        [void]$result.storySteps.Add([pscustomobject]@{ title = $stepTitle; segmentCount = $segs.Count })
      }
      foreach ($s in $segs) { [void]$all.Add($s) }
      $idx += 2
    }
  }

  # 兜底过滤：残留的模板参数行（|选项N= / 内容= / {{… 等碎片）
  $clean = New-Object System.Collections.ArrayList
  foreach ($s in $all) {
    if ($s.type -eq 'narration') {
      if ($s.content -match '^\|?\s*(选项|剧情|折叠|标题)\d*\s*=') { continue }
      if ($s.content -match '^\s*\|') { continue }
      if ($s.content -match '^\{\{') { continue }
      if ($s.content -match '^\s*(内容|折叠|标题|选项\d*|剧情\d*)\s*=\s*\S{0,2}$') { continue }
      if ($s.content -match '^[-—=~·\s]+$') { continue }
    }
    [void]$clean.Add($s)
  }

  $result.segments = @($clean)
  $result.counts = [ordered]@{
    dialogue  = @($clean | Where-Object { $_.type -eq 'dialogue' }).Count
    narration = @($clean | Where-Object { $_.type -eq 'narration' }).Count
    scene     = @($clean | Where-Object { $_.type -eq 'scene' }).Count
    option    = @($clean | Where-Object { $_.type -eq 'option' }).Count
  }
  return $result
}

function Pick-KeySegments($story, [int]$maxDialogue = 24, [int]$maxNarration = 10) {
  # 挑「关键片段」：全文按顺序扫、分块抽样，保持剧情顺序
  $segs = @($story.segments)
  if ($segs.Count -eq 0) { return @() }
  $di = New-Object System.Collections.ArrayList
  $ni = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $segs.Count; $i++) {
    if ($segs[$i].type -eq 'dialogue') { [void]$di.Add($i) }
    elseif ($segs[$i].type -eq 'narration') { [void]$ni.Add($i) }
  }
  $keep = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($cfg in @(@($di, $maxDialogue), @($ni, $maxNarration))) {
    $list = $cfg[0]; $cap = [int]$cfg[1]
    if ($list.Count -eq 0) { continue }
    if ($list.Count -le $cap) { foreach ($i in $list) { [void]$keep.Add([int]$i) }; continue }
    $stepSize = $list.Count / $cap
    for ($k = 0; $k -lt $cap; $k++) {
      $pick = [int][Math]::Floor($k * $stepSize)
      if ($pick -ge $list.Count) { $pick = $list.Count - 1 }
      [void]$keep.Add([int]$list[$pick])
    }
  }
  $out = @()
  foreach ($i in ($keep | Sort-Object)) {
    $s = $segs[$i]
    $c = $s.content
    if ($c.Length -gt 180) { $c = $c.Substring(0, 180) + '…' }
    $out += [pscustomobject]@{ type = $s.type; speaker = $s.speaker; content = $c }
  }
  return $out
}
