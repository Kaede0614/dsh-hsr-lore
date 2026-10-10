# check-bom-and-syntax.ps1 - 交付前门禁：确认每个 .ps1 都是 UTF-8 with BOM 且语法可解析
# 背景：Windows PowerShell 5.1 会把「无 BOM 的 UTF-8」按 GBK 解析，中文字面量被拆坏 →
#       报一堆 "Unexpected token '}'" 之类的假语法错误，而且脚本可能「跑一半就停」而不报错退出。
#       这个门禁用 Parser::ParseFile 静态检查，比看退出码可靠。
# 用法：powershell.exe -NoProfile -ExecutionPolicy Bypass -File check-bom-and-syntax.ps1

$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$fail = 0
$checked = 0

foreach ($f in (Get-ChildItem $dir -Filter *.ps1 -File | Sort-Object Name)) {
  $checked++
  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)

  $bomMark = if ($hasBom) { 'BOM-OK  ' } else { 'BOM-MISS' }
  $synMark = if ($errs -and $errs.Count -gt 0) { "SYNTAX-ERR($($errs.Count))" } else { 'SYNTAX-OK' }
  if (-not $hasBom -or ($errs -and $errs.Count -gt 0)) { $fail++ }
  Write-Host ("{0}  {1}  {2}" -f $bomMark, $synMark, $f.Name)

  if ($errs -and $errs.Count -gt 0) {
    foreach ($e in ($errs | Select-Object -First 4)) {
      Write-Host ("      L{0}: {1}" -f $e.Extent.StartLineNumber, $e.Message)
    }
  }
}

Write-Host ''
if ($fail -eq 0) {
  Write-Host ("门禁通过：{0} 个脚本，全部 BOM-OK + SYNTAX-OK" -f $checked)
  exit 0
} else {
  Write-Host ("门禁失败：{0}/{1} 个脚本不合格 —— 先修好再跑流水线" -f $fail, $checked)
  Write-Host '修法：把文件重新写成 UTF-8 with BOM。'
  exit 1
}
