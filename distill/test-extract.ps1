# test-extract.ps1 - 抽取器试运行（诊断用）
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

. (Join-Path $PSScriptRoot 'story-extract.ps1')

$name = $args[0]
if (-not $name) { $name = '大墓啊，深藏轮回的秘密' }
$f = Join-Path (Join-Path $PSScriptRoot 'raw\missions') "$name.wikitext"
if (-not (Test-Path $f)) { Write-Host "缺少文件：$f"; exit 1 }

$text = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
$st = Extract-Story $text
Write-Host ("=== $name ===")
Write-Host ("counts: dialogue={0} narration={1} scene={2} option={3}" -f $st.counts.dialogue, $st.counts.narration, $st.counts.scene, $st.counts.option)
Write-Host ("storySteps={0}  transitions={1}  segments={2}" -f $st.storySteps.Count, $st.transitions.Count, $st.segments.Count)

Write-Host '--- storySteps ---'
foreach ($s in $st.storySteps) { Write-Host ("  * {0}  (segs={1})" -f $s.title, $s.segmentCount) }

Write-Host '--- transitions ---'
foreach ($t in $st.transitions) { Write-Host ("  * {0}  (segs={1})" -f $t.title, $t.segments.Count) }

Write-Host '--- first 12 segments ---'
$st.segments | Select-Object -First 12 | ForEach-Object {
  $c = $_.content; if ($c.Length -gt 90) { $c = $c.Substring(0, 90) + '…' }
  Write-Host ("  [{0}] {1}: {2}" -f $_.type, $_.speaker, $c)
}

Write-Host '--- picked key segments (first 12) ---'
$key = Pick-KeySegments $st
Write-Host ("keyTotal=" + $key.Count)
$key | Select-Object -First 12 | ForEach-Object {
  $c = $_.content; if ($c.Length -gt 80) { $c = $c.Substring(0, 80) + '…' }
  Write-Host ("  [{0}] {1}: {2}" -f $_.type, $_.speaker, $c)
}
