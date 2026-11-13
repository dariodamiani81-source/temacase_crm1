$ErrorActionPreference = 'Stop'
$radiceTC = $PSScriptRoot
$attesiTC = @{
 'supabase\functions\temacase-google-auth\index.ts' = 'CA93670CA31298F1956E09340668E85E57D508DFC2F8527CB91702B5718C8913'
 'supabase\functions\temacase-telegram\index.ts' = 'EF61360EF522015E4E30BAAAECAD808E91A449C7ECC5826D8F0FDA4664991A00'
}
foreach ($relativoTC in $attesiTC.Keys) {
    $fileTC = Join-Path $radiceTC $relativoTC
    if (-not (Test-Path -LiteralPath $fileTC)) {
        throw 'File mancante. Attendi la sincronizzazione Google Drive.'
    }
    if ((Get-FileHash -LiteralPath $fileTC -Algorithm SHA256).Hash -ne $attesiTC[$relativoTC]) {
        throw 'Sorgenti diversi dalla versione v30. Attendi la sincronizzazione Google Drive; se persiste, riportami il messaggio.'
    }
}
Push-Location $radiceTC
try {
    Write-Host 'Prima di questo deploy deve essere stato eseguito 01_database_v30.sql in Supabase.'
    npx.cmd --yes supabase functions deploy temacase-google-auth '--remote=uuilnjjramxjvfoutmqu' --use-api --no-verify-jwt
    if ($LASTEXITCODE -ne 0) { throw 'Deploy Google non riuscito.' }
    npx.cmd --yes supabase functions deploy temacase-telegram '--remote=uuilnjjramxjvfoutmqu' --use-api --no-verify-jwt
    if ($LASTEXITCODE -ne 0) { throw 'Deploy Telegram non riuscito. Il deploy Google e gia completato.' }
    Write-Host 'Deploy v30 completati. In Telegram invia /annulla e poi /google.' -ForegroundColor Green
}
finally { Pop-Location }
