$ErrorActionPreference = 'Stop'
$radiceTC = $PSScriptRoot
$attesiTC = @{
 'supabase\functions\temacase-google-auth\index.ts' = 'A3711C561DFB2CA41500DE660E9E984C7A92BAE67BA45934DF550894C6DE721D'
 'supabase\functions\temacase-telegram\index.ts' = 'E9AC9CCF3B24D7B154B556F01698CF86C1BC7E38FB5BC9245BF885C9C9F2C545'
}
foreach ($relativoTC in $attesiTC.Keys) {
    $fileTC = Join-Path $radiceTC $relativoTC
    if (-not (Test-Path -LiteralPath $fileTC)) {
        throw 'File mancante. Attendi la sincronizzazione Google Drive.'
    }
    if ((Get-FileHash -LiteralPath $fileTC -Algorithm SHA256).Hash -ne $attesiTC[$relativoTC]) {
        throw 'Sorgenti diversi dalla versione v29. Attendi la sincronizzazione Google Drive; se persiste, riportami il messaggio.'
    }
}
Push-Location $radiceTC
try {
    Write-Host 'Prima di questo deploy deve essere stato eseguito 01_database_v29.sql in Supabase.'
    npx.cmd --yes supabase functions deploy temacase-google-auth '--remote=uuilnjjramxjvfoutmqu' --use-api --no-verify-jwt
    if ($LASTEXITCODE -ne 0) { throw 'Deploy Google non riuscito.' }
    npx.cmd --yes supabase functions deploy temacase-telegram '--remote=uuilnjjramxjvfoutmqu' --use-api --no-verify-jwt
    if ($LASTEXITCODE -ne 0) { throw 'Deploy Telegram non riuscito. Il deploy Google e gia completato.' }
    Write-Host 'Deploy v29 completati. In Telegram invia /annulla e poi /google.' -ForegroundColor Green
}
finally { Pop-Location }
