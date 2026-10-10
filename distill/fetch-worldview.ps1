# fetch-worldview.ps1 - 抓取 P1 世界观页面（星神/命途/派系/专有名词/开拓/令使 等）
# 独立于任务抓取，自带退避；必须在任务抓取结束后运行，避免触发站点风控。
# 必须以 UTF-8 with BOM 保存。

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root   = 'C:\Users\masha\Desktop\hsr-skill\distill'
$RawDir = Join-Path $Root 'raw\worldview'
$LogFile = Join-Path $Root 'fetch-worldview-log.txt'
$Base   = 'https://wiki.biligame.com/sr/api.php'
New-Item -ItemType Directory -Force -Path $RawDir | Out-Null

$Hdr = @{
  'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
  'Accept'          = 'application/json, text/plain, */*'
  'Accept-Language' = 'zh-CN,zh;q=0.9,en;q=0.8'
  'Referer'         = 'https://wiki.biligame.com/sr/'
}

function Write-Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
  Write-Host $line
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

$pages = @(
  '星神',
  '命途',
  '派系',
  '专有名词',
  '无名客',
  '令使',
  '忆域',
  '星核',
  '雅利洛-Ⅵ',
  '贝洛伯格',
  '星穹列车',
  '反物质军团',
  '星核猎手',
  '天才俱乐部',
  '星际和平公司',
  '仙舟',
  '匹诺康尼',
  '翁法罗斯'
)

# 等任务抓取结束
$ready = Join-Path $Root 'fetch-log.txt'
Write-Log '等待任务抓取完成…'
for ($w = 0; $w -lt 240; $w++) {
  if (Test-Path $ready) {
    $tail = (Get-Content $ready -Encoding UTF8 -Tail 1)
    if ($tail -match '^\[[0-9:]+\] 完成：') { break }
  }
  Start-Sleep -Seconds 15
}
Write-Log '开始抓取世界观页面'

$ok = 0; $fail = @()
foreach ($t in $pages) {
  $safe = $t -replace '[\\/:*?"<>|]', '_'
  $out = Join-Path $RawDir "$safe.wikitext"
  if ((Test-Path $out) -and ((Get-Item $out).Length -gt 0)) { Write-Log "跳过（已缓存）：$t"; continue }

  $u = "$Base" + '?action=parse&page=' + [uri]::EscapeDataString($t) + '&prop=wikitext&format=json&formatversion=2'
  $done = $false
  for ($attempt = 1; $attempt -le 5 -and -not $done; $attempt++) {
    try {
      $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 60 -Headers $Hdr
      $j = $r.Content | ConvertFrom-Json
      $txt = $j.parse.wikitext
      if ($null -eq $txt) { $txt = '' }
      [System.IO.File]::WriteAllText($out, $txt, (New-Object System.Text.UTF8Encoding($false)))
      Write-Log ("OK {0} ({1} chars)" -f $t, $txt.Length)
      $ok++; $done = $true
    } catch {
      $wait = 10 * $attempt
      Write-Log ("重试 {0}/5 {1} -> {2}，等待 {3}s" -f $attempt, $t, $_.Exception.Message.Split("`n")[0], $wait)
      Start-Sleep -Seconds $wait
      if ($attempt -eq 5) { $fail += $t }
    }
  }
  Start-Sleep -Seconds (Get-Random -Minimum 4000 -Maximum 8000)
}

Write-Log ("世界观页面完成：成功 {0}，失败 {1}" -f $ok, $fail.Count)
if ($fail.Count -gt 0) { Write-Log ("失败：" + ($fail -join ' | ')) }
