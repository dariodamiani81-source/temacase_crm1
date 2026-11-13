$ErrorActionPreference = 'Stop'
$radiceTC = $PSScriptRoot
$attesiTC = @{
 'supabase\functions\temacase-google-auth\index.ts' = 'DACD390A64CC3E77B00F3BEF8B5FA0ED2AB8D9F22A63615D938F922BFD232A1B'
 'supabase\functions\temacase-telegram\index.ts' = '6B7D598ABF333752B8F174196C28E6F2DC7855FA2A0E8615E9C174B2A0C12AF6'
 'supabase\functions\temacase-telegram\ai-interprete.ts' = '309CC0482EC15D98BAEAB34AAC9DE0A8E0D145C3EA12C3D24E0CB1F26B61A70F'
}
foreach ($relativoTC in $attesiTC.Keys) {
    $fileTC = Join-Path $radiceTC $relativoTC
    if (-not (Test-Path -LiteralPath $fileTC)) {
        throw 'File mancante. Attendi la sincronizzazione Google Drive.'
    }
    if ((Get-FileHash -LiteralPath $fileTC -Algorithm SHA256).Hash -ne $attesiTC[$relativoTC]) {
        throw 'Sorgenti diversi dalla versione v32. Attendi la sincronizzazione Google Drive; se persiste, riportami il messaggio.'
    }
}
Push-Location $radiceTC
try {
    Write-Host 'Prima di questo deploy deve essere stato eseguito 01_database_v32.sql in Supabase.'
    npx.cmd --yes supabase functions deploy temacase-google-auth '--remote=uuilnjjramxjvfoutmqu' --use-api --no-verify-jwt
    if ($LASTEXITCODE -ne 0) { throw 'Deploy Google non riuscito.' }
    npx.cmd --yes supabase functions deploy temacase-telegram '--remote=uuilnjjramxjvfoutmqu' --use-api --no-verify-jwt
    if ($LASTEXITCODE -ne 0) { throw 'Deploy Telegram non riuscito. Il deploy Google e gia completato.' }
    Write-Host 'Deploy v32 completati. In Telegram invia /annulla, poi detta la richiesta.' -ForegroundColor Green
}
finally { Pop-Location }
