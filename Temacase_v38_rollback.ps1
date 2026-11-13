# Temacase CRM v38 - rollback automatico dei sorgenti (non del database).
# Windows PowerShell 5.1. Non esegue alcun deploy.
$ErrorActionPreference='Stop'
$radice='G:\Il mio Drive\TEMACASE\temacase-crm-mcp'
$puntatore=Join-Path $radice 'V38_ULTIMO_BACKUP.txt'
if (-not (Test-Path -LiteralPath $puntatore -PathType Leaf)) { throw 'Non trovo il riferimento al backup v38.' }
$dir=(Get-Content -LiteralPath $puntatore -Raw).Trim()
$manifesto=Join-Path $dir 'manifest.json'
if (-not (Test-Path -LiteralPath $manifesto -PathType Leaf)) { throw 'Manifest del backup non trovato.' }
$m=Get-Content -LiteralPath $manifesto -Raw | ConvertFrom-Json
if($m.versione -ne 'v38') { throw 'Versione del backup non valida.' }
$relativi=@(
  'supabase\functions\temacase-telegram\index.ts',
  'supabase\functions\temacase-telegram\ai-interprete.ts',
  'supabase\functions\temacase-google-auth\index.ts'
)
# Se ci sono state modifiche successive al progetto, non sovrascriverle.
foreach($p in $relativi) {
  $src=Join-Path $dir $p; $dst=Join-Path $radice $p
  if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Backup incompleto: $p" }
  if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) { throw "File corrente mancante: $p" }
  $atteso=($m.sorgenti.$p).dopo
  $attuale=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
  if ($attuale -ne $atteso) { throw "Il file $p e stato modificato dopo la v38. Rollback bloccato per proteggere le modifiche successive." }
}
foreach($p in $relativi) {
  Copy-Item -LiteralPath (Join-Path $dir $p) -Destination (Join-Path $radice $p) -Force
  $hash=(Get-FileHash -LiteralPath (Join-Path $radice $p) -Algorithm SHA256).Hash
  if($hash -ne ($m.sorgenti.$p).prima) { throw "Verifica di ripristino non riuscita: $p" }
}
Write-Host 'Sorgenti v37 ripristinati correttamente.' -ForegroundColor Green
Write-Host 'ATTENZIONE: il rollback del database (03_database_v38_rollback.sql) e il redeploy Telegram sono operazioni separate.' -ForegroundColor Yellow