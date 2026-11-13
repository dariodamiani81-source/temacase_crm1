$ErrorActionPreference = 'Stop'
$radiceTC = $PSScriptRoot
$attesiTC = @{
 'supabase\functions\temacase-google-auth\index.ts' = 'C914C7DCE8B8A63855ABC009BE403FF0F97E71BBC345A6CD8082D557E1AE0C66'
 'supabase\functions\temacase-telegram\index.ts' = '60D1AE950888A2A7FAF283D6C4F7201981DBE1163E3F35EF49F92ED6CBBF72C6'
 'supabase\functions\temacase-telegram\ai-interprete.ts' = '94139E8E7BC97109DAB1223343E5AF9105D6E5D718422D7E1A24D686976C7AA1'
}
foreach ($relativoTC in $attesiTC.Keys) {
    $fileTC = Join-Path $radiceTC $relativoTC
    if (-not (Test-Path -LiteralPath $fileTC)) {
        throw 'File mancante. Attendi la sincronizzazione Google Drive.'
    }
    if ((Get-FileHash -LiteralPath $fileTC -Algorithm SHA256).Hash -ne $attesiTC[$relativoTC]) {
        throw 'Sorgenti diversi dalla versione v31. Attendi la sincronizzazione Google Drive; se persiste, riportami il messaggio.'
    }
}
Push-Location $radiceTC
try {
    Write-Host 'Prima di questo deploy deve essere stato eseguito 01_database_v31.sql in Supabase.'
    npx.cmd --yes supabase functions deploy temacase-google-auth '--remote=uuilnjjramxjvfoutmqu' --use-api --no-verify-jwt
    if ($LASTEXITCODE -ne 0) { throw 'Deploy Google non riuscito.' }
    npx.cmd --yes supabase functions deploy temacase-telegram '--remote=uuilnjjramxjvfoutmqu' --use-api --no-verify-jwt
    if ($LASTEXITCODE -ne 0) { throw 'Deploy Telegram non riuscito. Il deploy Google e gia completato.' }
    Write-Host 'Deploy v31 completati. In Telegram invia /annulla, poi detta la richiesta.' -ForegroundColor Green
}
finally { Pop-Location }
