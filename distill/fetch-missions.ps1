# fetch-missions.ps1 - 从 biligame 星穹铁道 wiki 抓取「开拓任务」分类下全部页面 wikitext
# 特性：断点续抓（已存在的 .wikitext 跳过）、随机节流、失败重试退避、进度日志
# 注意：本文件必须以 UTF-8 with BOM 保存，否则 Windows PowerShell 5.1 会按 GBK 解析中文导致语法错误。

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root     = 'C:\Users\masha\Desktop\hsr-skill\distill'
$RawDir   = Join-Path $Root 'raw\missions'
$ListFile = Join-Path $Root 'raw\cat-开拓任务.json'
$LogFile  = Join-Path $Root 'fetch-log.txt'
$Base     = 'https://wiki.biligame.com/sr/api.php'

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

# --- 1. 读取任务清单（复用已缓存文件，避免额外请求） ---
if (-not (Test-Path $ListFile)) { throw "缺少任务清单：$ListFile" }
$catJson = Get-Content $ListFile -Raw -Encoding UTF8 | ConvertFrom-Json
$titles = @($catJson.query.categorymembers | Where-Object { $_.ns -eq 0 } | ForEach-Object { $_.title })
Write-Log ("任务页总数：{0}" -f $titles.Count)

# --- 2. 逐页抓取 ---
$ok = 0; $skip = 0; $fail = @()
$i = 0
foreach ($title in $titles) {
  $i++
  $safe = $title -replace '[\\/:*?"<>|]', '_'
  $out  = Join-Path $RawDir "$safe.wikitext"
  if ((Test-Path $out) -and ((Get-Item $out).Length -gt 0)) { $skip++; continue }

  $u = "$Base" + '?action=parse&page=' + [uri]::EscapeDataString($title) + '&prop=wikitext&format=json&formatversion=2'
  $done = $false
  for ($attempt = 1; $attempt -le 4 -and -not $done; $attempt++) {
    try {
      $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 60 -Headers $Hdr
      $j = $r.Content | ConvertFrom-Json
      $txt = $j.parse.wikitext
      if ($null -eq $txt) { $txt = '' }
      [System.IO.File]::WriteAllText($out, $txt, (New-Object System.Text.UTF8Encoding($false)))
      $ok++
      $done = $true
      if ($i % 10 -eq 0) { Write-Log ("进度 {0}/{1}  已抓 {2} 跳过 {3} 失败 {4}" -f $i, $titles.Count, $ok, $skip, $fail.Count) }
    } catch {
      $wait = 5 * $attempt
      Write-Log ("[重试 {0}/4] {1} -> {2}，等待 {3}s" -f $attempt, $title, $_.Exception.Message.Split("`n")[0], $wait)
      Start-Sleep -Seconds $wait
      if ($attempt -eq 4) { $fail += $title }
    }
  }
  Start-Sleep -Milliseconds (Get-Random -Minimum 1400 -Maximum 3200)
}

Write-Log ("完成：成功 {0}，跳过（已缓存）{1}，失败 {2}" -f $ok, $skip, $fail.Count)
if ($fail.Count -gt 0) {
  Write-Log ("失败清单：" + ($fail -join ' | '))
  $fail | Set-Content -Path (Join-Path $Root 'fetch-failed.txt') -Encoding UTF8
}
