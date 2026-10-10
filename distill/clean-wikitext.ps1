# clean-wikitext.ps1 - 共享的 wikitext 清洗工具（被 story-extract.ps1 / parse-worldview.ps1 复用）
# 必须以 UTF-8 with BOM 保存。

function Expand-Annotation([string]$s) {
  # {{注音|显示|注}} -> 显示（注）
  return [regex]::Replace($s, '(?s)\{\{注音\|([^|{}]*)\|([^|{}]*)\}\}', { param($m) "$($m.Groups[1].Value)（$($m.Groups[2].Value)）" })
}

function Strip-Inline([string]$s) {
  if ($null -eq $s) { return '' }
  $s = Expand-Annotation $s
  $s = [regex]::Replace($s, '(?s)<!--.*?-->', '')
  $s = [regex]::Replace($s, '(?s)\[\[\s*(?:file|File|FILE|文件)\s*:[^\[\]]*\]\]', '')   # 图片链接
  $s = [regex]::Replace($s, '(?s)\{\{颜色\|[^|{}]*\|([^{}]*)\}\}', '$1')
  $s = [regex]::Replace($s, '(?s)\{\{图标\|([^|{}]*)(\|[^|{}]*)?\}\}', '$1')
  $s = [regex]::Replace($s, '(?s)\{\{PAGENAME\}\}', '')
  $s = [regex]::Replace($s, '(?s)\{\{[^{}]*\}\}', '')
  $s = [regex]::Replace($s, '(?s)\[\[[^\[\]|]*\|([^\[\]]*)\]\]', '$1')
  $s = [regex]::Replace($s, '(?s)\[\[([^\[\]]*)\]\]', '$1')
  $s = $s -replace "'''?", ''
  $s = $s -replace '<br\s*/?>', ' '
  $s = [regex]::Replace($s, '[ \t]+', ' ')
  return $s.Trim()
}

# 清洗大段正文：保留表格里的文字（只去表格语法），去引用/图片/HTML 标签
function Strip-Block([string]$s) {
  if ($null -eq $s) { return '' }
  $s = [regex]::Replace($s, '(?s)<!--.*?-->', '')
  $s = [regex]::Replace($s, '(?s)<ref[^>]*>.*?</ref>', '')
  $s = [regex]::Replace($s, '<ref[^>]*/>', '')
  $s = [regex]::Replace($s, '(?s)\[\[\s*(?:file|File|FILE|文件)\s*:[^\[\]]*\]\]', '')  # 图片链接
  # 表格：去掉 {| / |} / |- / ! 行与行首单元格分隔符，保留单元格文字
  $s = [regex]::Replace($s, '(?m)^\s*\{\|.*$', '')
  $s = [regex]::Replace($s, '(?m)^\s*\|\}.*$', '')
  $s = [regex]::Replace($s, '(?m)^\s*\|-+.*$', '')
  $s = [regex]::Replace($s, '(?m)^\s*[|!]\s*', '')
  $s = [regex]::Replace($s, '(?m)^\s*[|!]\s*', '')
  # 残留的表格属性（style= / colspan= / class= / width= 等）
  $s = [regex]::Replace($s, '(?i)\b(?:style|colspan|rowspan|class|width|align|valign|scope)\s*=\s*("[^"]*"|''[^'']*''|[^\s|]*)', '')
  $s = [regex]::Replace($s, '(?m)^\s*[|!]\s*', '')
  # HTML 标签：只去标签本身，不跨行贪吃
  $s = [regex]::Replace($s, '</?(?:span|div|big|small|font|center|b|i|u|p|ruby|rt|sup|sub|table|tr|td|th|tbody|h[1-6])\b[^>]*/?>', '')
  $s = [regex]::Replace($s, '(?s)\{\{面包屑[^{}]*\}\}', '')
  $s = [regex]::Replace($s, '(?s)\{\{[^{}]*\}\}', '')
  $s = [regex]::Replace($s, '(?s)\[\[[^\[\]|]*\|([^\[\]]*)\]\]', '$1')
  $s = [regex]::Replace($s, '(?s)\[\[([^\[\]]*)\]\]', '$1')
  $s = $s -replace "'''?", ''
  $s = $s -replace '<br\s*/?>', "`n"
  $s = [regex]::Replace($s, '[ \t]+', ' ')
  $s = [regex]::Replace($s, '(\r?\n){2,}', "`n")
  return $s.Trim()
}

# 扫描顶层 {{...}} 块，返回 @{ start; end; text }
function Get-TopLevelTemplates([string]$text) {
  $res = New-Object System.Collections.ArrayList
  $n = $text.Length; $i = 0
  while ($i -lt $n - 1) {
    if ($text[$i] -eq '{' -and $text[$i + 1] -eq '{') {
      $start = $i; $depth = 0
      while ($i -lt $n - 1) {
        if ($text[$i] -eq '{' -and $text[$i + 1] -eq '{') { $depth++; $i += 2; continue }
        if ($text[$i] -eq '}' -and $text[$i + 1] -eq '}') { $depth--; $i += 2; if ($depth -eq 0) { break }; continue }
        $i++
      }
      if ($depth -eq 0) {
        [void]$res.Add([pscustomobject]@{ start = $start; end = $i; text = $text.Substring($start, $i - $start) })
      }
      continue
    }
    $i++
  }
  return $res
}

# 按 == 标题 == 把页面切成有序小节（在「清洗之前」执行，避免表格/模板把标题吞掉）
# 返回 @() 或 [pscustomobject]@{ title; body } 数组（按原文顺序）
function Get-Sections([string]$text) {
  $sections = New-Object System.Collections.ArrayList
  $ms = [regex]::Matches($text, '(?m)^==\s*(.+?)\s*==\s*$')
  if ($ms.Count -eq 0) { return $sections }
  for ($k = 0; $k -lt $ms.Count; $k++) {
    $m = $ms[$k]
    $bodyStart = $m.Index + $m.Length
    $bodyEnd = if ($k + 1 -lt $ms.Count) { $ms[$k + 1].Index } else { $text.Length }
    [void]$sections.Add([pscustomobject]@{
      title = $m.Groups[1].Value
      body  = $text.Substring($bodyStart, $bodyEnd - $bodyStart)
    })
  }
  return $sections
}
