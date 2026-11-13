# Temacase CRM v38 - modifica automatica dei sorgenti locali, senza deploy.
# Compatibile con Windows PowerShell 5.1.
# Legge il codice esistente, controlla gli ancoraggi e prepara rollback completo.
$ErrorActionPreference = 'Stop'
$radice = 'G:\Il mio Drive\TEMACASE\temacase-crm-mcp'
$relativo = 'supabase\functions\temacase-telegram\index.ts'
$file = Join-Path $radice $relativo
$altri = @('supabase\functions\temacase-telegram\ai-interprete.ts','supabase\functions\temacase-google-auth\index.ts')
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Sorgente mancante: $file" }
foreach ($p in $altri) { if (-not (Test-Path -LiteralPath (Join-Path $radice $p) -PathType Leaf)) { throw "Sorgente mancante: $p" } }
$script:codice = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8).Replace("`r`n", "`n")
if (-not $script:codice.Contains('async function leggiSchedaNotiziaBase32(') -or -not $script:codice.Contains('// TEMACASE_NOTIZIE_IMMOBILI_V32')) { throw 'Il sorgente non corrisponde alla struttura letta su Drive. Nessuna modifica eseguita.' }
if ($script:codice.Contains('// TEMACASE_NOTIZIE_V38')) { throw 'La v38 risulta gia preparata: nessuna modifica effettuata.' }
function Cambia([string]$nome, [string]$prima, [string]$dopo) {
  $n = ([regex]::Matches($script:codice, [regex]::Escape($prima))).Count
  if ($n -ne 1) { throw "Controllo $nome fallito: trovati $n ancoraggi, atteso 1. Nessun sorgente modificato." }
  $script:codice = $script:codice.Replace($prima, $dopo)
  Write-Host "OK: $nome"
}

# Nuove notizie: data automatica di creazione e niente dati anagrafici nel record notizia.
$prima = @'
      data_segnalazione: dataValida(dati.data_segnalazione),
'@
$dopo = @'
      data_segnalazione: oggiARoma(),
'@
Cambia 'data di creazione nell anteprima' $prima $dopo
$prima = @'
      venditore_nome: campo(dati.venditore_nome),
      venditore_cognome: campo(dati.venditore_cognome),
      venditore_telefono: campo(dati.venditore_telefono, 60),
'@
Cambia 'rimozione venditore dai dettagli AI' $prima ''
$prima = @'
    venditore_nome: "Nome venditore",
    venditore_cognome: "Cognome venditore",
    venditore_telefono: "Telefono venditore",
'@
Cambia 'rimozione venditore dalle etichette' $prima ''
$prima = @'
            'In dettagli.dati usa data_segnalazione, fonte, venditore_nome, venditore_cognome, venditore_telefono, scala, piano, tipologia_immobile, numero_locali. Il numero dei locali è un intero.',
'@
$dopo = @'
             'In dettagli.dati usa solo fonte, scala, piano, tipologia_immobile, numero_locali. Il numero dei locali è un intero. La data segnalazione coincide con la creazione. Non generare venditore_nome, venditore_cognome o venditore_telefono: tutti i referenti si gestiscono nella rubrica CRM e tramite collegamenti alla notizia.',
'@
Cambia 'istruzioni AI notizie' $prima $dopo
$prima = @'
      venditore_telefono:
        dati.ruolo_telefono === "proprietario"
          ? dati.telefono
          : null,
'@
Cambia 'foto cartello senza campo venditore legacy' $prima ''
$prima = @'
        data_segnalazione, fonte, venditore_nome, venditore_cognome,
        venditore_telefono, scala, piano, tipologia_immobile, numero_locali
'@
$dopo = @'
        data_segnalazione, fonte, scala, piano, tipologia_immobile, numero_locali
'@
Cambia 'INSERT notizia senza venditore' $prima $dopo
$prima = @'
        ${dati.data_segnalazione}::date, ${dati.fonte},
        ${dati.venditore_nome}, ${dati.venditore_cognome}, ${dati.venditore_telefono},
        ${dati.scala}, ${dati.piano}, ${dati.tipologia_immobile}, ${dati.numero_locali}
'@
$dopo = @'
        (now() AT TIME ZONE 'Europe/Rome')::date, ${dati.fonte},
        ${dati.scala}, ${dati.piano}, ${dati.tipologia_immobile}, ${dati.numero_locali}
'@
Cambia 'VALUES notizia data automatica' $prima $dopo

# Scheda: restituisce solo i campi previsti; tutti gli altri contatti sono collegamenti CRM.
$prima = @'
      venditore: string;
      venditore_telefono: string | null;
'@
Cambia 'tipi vecchi campi scheda' $prima ''
$prima = @'
      proprietario_contattato: boolean | null;
'@
Cambia 'tipo proprietario contattato' $prima ''
$prima = @'
        n.fonte, concat_ws(' ', n.venditore_nome, n.venditore_cognome) AS venditore,
        n.venditore_telefono, n.scala, n.piano,
'@
$dopo = @'
        n.fonte, n.scala, n.piano,
'@
Cambia 'SELECT campi venditore' $prima $dopo
$prima = @'
        n.proprietario_contattato, n.incarico_in_essere, n.agenzia_incaricata,
'@
$dopo = @'
        n.incarico_in_essere, n.agenzia_incaricata,
'@
Cambia 'SELECT proprietario contattato' $prima $dopo
$prima = @'
        ["Venditore", n.venditore], ["Telefono venditore", n.venditore_telefono],
'@
Cambia 'visualizzazione venditore' $prima ''
$prima = @'
        ["Proprietario già contattato", n.proprietario_contattato],
'@
Cambia 'visualizzazione proprietario contattato' $prima ''

# Ordine esattamente corrispondente alla scheda Telegram: titolo, stato, data, fonte,
# scala, piano, tipologia, locali, incarico, agenzia, scadenza, segnalazione, follow-up.
$prima = @'
const campiModificabili = {
  titolo: "Titolo",
  testo: "Testo della notizia",
  data_segnalazione: "Data segnalazione",
  fonte: "Fonte",
  venditore_nome: "Nome proprietario",
  venditore_cognome: "Cognome proprietario",
  venditore_telefono: "Telefono proprietario",
  scala: "Scala",
  piano: "Piano",
  tipologia_immobile: "Tipologia",
  numero_locali: "Locali",
  proprietario_contattato: "Proprietario già contattato",
  incarico_in_essere: "Incarico in essere",
  agenzia_incaricata: "Agenzia incaricata",
  scadenza_incarico: "Scadenza incarico",
};
'@
$dopo = @'
// TEMACASE_NOTIZIE_V38
const campiModificabili = {
  titolo: "Titolo",
  stato_notizia: "Stato",
  data_segnalazione: "Data segnalazione",
  fonte: "Fonte",
  scala: "Scala",
  piano: "Piano",
  tipologia_immobile: "Tipologia",
  numero_locali: "Locali",
  incarico_in_essere: "Incarico in essere",
  agenzia_incaricata: "Agenzia incaricata",
  scadenza_incarico: "Scadenza incarico",
  testo: "Segnalazione",
};
'@
Cambia 'campi modificabili ordinati' $prima $dopo
$prima = @'
  if (campo === "proprietario_contattato" || campo === "incarico_in_essere") {
'@
$dopo = @'
  if (campo === "stato_notizia") {
    const s = testo.toLocaleLowerCase('it-IT').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[_-]/g, ' ').trim();
    if (s === 'attiva' || s === 'attivo') return 'attiva';
    if (s === 'non veritiera') return 'non_veritiera';
    return undefined;
  }
  if (campo === "incarico_in_essere") {
'@
Cambia 'validazione stato notizia' $prima $dopo
$prima = @'
    return campo === "testo" || campo === "titolo" ? undefined : null;
'@
$dopo = @'
    return campo === "testo" || campo === "titolo" || campo === "stato_notizia" ? undefined : null;
'@
Cambia 'stato non puo essere svuotato' $prima $dopo
$prima = @'
Per i booleani usa true o false, per le date YYYY-MM-DD, per i locali un intero.
'@
$dopo = @'
Per i booleani usa true o false, per le date YYYY-MM-DD, per i locali un intero. Per stato_notizia ammetti solo "attiva" o "non_veritiera".
'@
Cambia 'specifica istruzioni modifica' $prima $dopo
$prima = @'
    const campo = indice === "*" ? "*" : chiaviCampi[Number(indice)];
'@
$dopo = @'
    // v38: chiavi stabili, mai riusare gli indici numerici di vecchi menu Telegram.
    const campo = indice === "*" ? "*" :
      chiaviCampi.includes(indice as CampoModificabile) ? indice as CampoModificabile : undefined;
'@
Cambia 'callback numerici da disattivare' $prima $dopo
$prima = @'
    if (azione === "campo" && !campo) return;
'@
$dopo = @'
    if (azione === "campo" && !campo) {
      await inviaRisposta(botToken, telegramId, 'Questo pulsante appartiene a un vecchio menu. Riapri la scheda e premi Modifica.');
      return;
    }
'@
Cambia 'vecchi menu numerici notificati' $prima $dopo
$prima = @'
        text: `Modifica notizia #${id}. Scegli un campo oppure descrivi più modifiche.`,
        inline_keyboard: [
          [{ text: "Descrivi le modifiche", callback_data: `m:campo:${id}:*` }],
          [{ text: "Follow-up", callback_data: `m:followup:${id}` }],
          ...chiaviCampi.map((c, i) => [{ text: campiModificabili[c], callback_data: `m:campo:${id}:${i}` }]),
        ],
'@
$dopo = @'
        text: `Modifica notizia #${id}. Scegli il campo da aggiornare.`,
        inline_keyboard: [
          ...chiaviCampi.map((c) => [{ text: campiModificabili[c], callback_data: `m:campo:${id}:${c}` }]),
          [{ text: "Follow-up", callback_data: `m:followup:${id}` }],
          [{ text: "Contatti / Proprietari", callback_data: `t:note:${id}` }],
        ],
'@
Cambia 'menu ordinato senza descrivi modifiche' $prima $dopo
$prima = @'
        : `Notizia #${id} · ${campiModificabili[campo as CampoModificabile]}\nScrivi o detta il nuovo valore. Per svuotare scrivi “svuota”. /annulla per uscire.`;
'@
$dopo = @'
        : campo === "stato_notizia"
          ? `Notizia #${id} · Stato\nScrivi o detta: Attiva oppure Non veritiera. /annulla per uscire.`
          : `Notizia #${id} · ${campiModificabili[campo as CampoModificabile]}\nScrivi o detta il nuovo valore. Per svuotare scrivi “svuota”. /annulla per uscire.`;
'@
Cambia 'istruzioni specifiche per stato' $prima $dopo

# Rubrica unica: scelta del ruolo quando si collega un contatto esistente o se ne crea uno.
$prima = @'
type CrmStato = {
  fase: string;
  notizia?: string;
'@
$dopo = @'
const crmRuoliNotizia = ['proprietario','venditore','comproprietario','acquirente','interessato','locatore','conduttore'] as const;
type CrmStato = {
  fase: string;
  notizia?: string;
  ruolo?: string;
'@
Cambia 'ruoli collegamenti a notizie' $prima $dopo
$prima = @'
        "Nessun contatto collegato. I vecchi campi venditore restano nella notizia."
'@
$dopo = @'
        "Nessun contatto collegato. Associa un contatto della rubrica CRM."
'@
Cambia 'descrizione contatti della notizia' $prima $dopo
$prima = @'
        text: "Collega proprietario esistente",
'@
$dopo = @'
          text: "Collega contatto esistente",
'@
Cambia 'bottone collega contatto' $prima $dopo
$prima = @'
        text: "Crea proprietario",
'@
$dopo = @'
          text: "Crea contatto",
'@
Cambia 'bottone crea contatto' $prima $dopo
$prima = @'
        ? `Scegli il proprietario per la notizia #${notizia}.`
'@
$dopo = @'
        ? `Scegli un contatto da collegare alla notizia #${notizia}.`
'@
Cambia 'testo ricerca collegamento' $prima $dopo
$prima = @'
      (stato.notizia
        ? `\nNotizia collegata: #${stato.notizia}`
'@
$dopo = @'
       (stato.notizia
         ? `\nNotizia collegata: #${stato.notizia} · Ruolo: ${stato.ruolo || 'proprietario'}`
'@
Cambia 'anteprima ruolo collegamento' $prima $dopo
$prima = @'
  const [, azione, arg, extra] =
    String(callback.data || "").split(":");
'@
$dopo = @'
  const [, azione, arg, extra, ruoloScelto] =
    String(callback.data || "").split(":");
'@
Cambia 'lettura callback ruolo' $prima $dopo
$prima = @'
  } else if (
    (azione === "new" || azione === "search") &&
    (arg === "0" || idSchedaValido(arg))
  ) {
'@
$dopo = @'
  } else if (azione === 'role' && idSchedaValido(arg) &&
             idSchedaValido(extra) && crmRuoliNotizia.includes(ruoloScelto as any)) {
    const c = await crmLeggi(id, extra);
    if (c && await crmNotiziaValida(id, arg)) {
      risposta = await crmAnteprima(id, {
        fase: 'conferma', azione: 'collega', notizia: arg, contatto: extra,
        ruolo: ruoloScelto, precedente: c,
      });
    }
  } else if (azione === 'newrole' && idSchedaValido(arg) &&
             crmRuoliNotizia.includes(extra as any)) {
    if (await crmNotiziaValida(id, arg)) {
      await annullaTuttoTelegram(id);
      await crmAttendi(id, { fase: 'dati', azione: 'nuovo', notizia: arg, ruolo: extra });
      risposta = 'Scrivi o detta i dati del nuovo contatto e i recapiti. /annulla per uscire.';
    }
  } else if (
    (azione === "new" || azione === "search") &&
    (arg === "0" || idSchedaValido(arg))
  ) {
'@
Cambia 'flusso new/search ruolo' $prima $dopo
$prima = @'
    } else {
      await annullaTuttoTelegram(id);

      await crmAttendi(id, {
        fase: azione === "new" ? "dati" : "cerca",
'@
$dopo = @'
    } else if (azione === 'new' && arg !== '0') {
      risposta = {
        text: `Quale ruolo avra il nuovo contatto nella notizia #${arg}?`,
        inline_keyboard: crmRuoliNotizia.map(ruolo => [{
          text: ruolo.charAt(0).toUpperCase() + ruolo.slice(1),
          callback_data: `t:newrole:${arg}:${ruolo}`,
        }]),
      };
    } else {
      await annullaTuttoTelegram(id);

      await crmAttendi(id, {
        fase: azione === "new" ? "dati" : "cerca",
'@
Cambia 'menu scelta ruolo per nuovo contatto' $prima $dopo
$prima = @'
          risposta = s.stato.notizia
            ? await crmAnteprima(id, {
              fase: "conferma",
              azione: "collega",
              notizia: s.stato.notizia,
              contatto: extra,
              precedente: c,
            })
            : await crmScheda(id, extra);
'@
$dopo = @'
          risposta = s.stato.notizia
            ? {
              text: `In quale ruolo colleghi ${crmNome(c)} alla notizia #${s.stato.notizia}?`,
              inline_keyboard: crmRuoliNotizia.map(ruolo => [{
                text: ruolo.charAt(0).toUpperCase() + ruolo.slice(1),
                callback_data: `t:role:${s.stato.notizia}:${extra}:${ruolo}`,
              }]),
            }
            : await crmScheda(id, extra);
'@
Cambia 'ruolo dopo selezione contatto' $prima $dopo
$prima = @'
            'proprietario'
          )
          ON CONFLICT DO NOTHING
'@
$dopo = @'
            ${s.ruolo && crmRuoliNotizia.includes(s.ruolo as any) ? s.ruolo : 'proprietario'}
          )
          ON CONFLICT DO NOTHING
'@
Cambia 'INSERT collegamento con ruolo scelto' $prima $dopo
$prima = @'
      } else {
        await db`
          INSERT INTO temacase_test.crm_notizie_contatti
'@
$dopo = @'
      } else {
        // La nuova scelta del ruolo sostituisce un eventuale ruolo precedente.
        await db`
          DELETE FROM temacase_test.crm_notizie_contatti
          WHERE notizia_id = ${s.notizia}::bigint AND contatto_id = ${contatto}::bigint
        `;
        await db`
          INSERT INTO temacase_test.crm_notizie_contatti
'@
Cambia 'sostituzione ruolo contatto gia collegato' $prima $dopo

# Solo ora, superati tutti i controlli, crea backup e aggiorna file.
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$dirBackup = Join-Path $radice ("backup\v38_" + $timestamp)
New-Item -ItemType Directory -Force -Path $dirBackup | Out-Null
$relativi = @($relativo) + $altri
$manifest = @{ versione='v38'; creato=(Get-Date).ToString('o'); sorgenti=@{} }
foreach($p in $relativi) {
  $originale=Join-Path $radice $p
  $dest=Join-Path $dirBackup $p
  New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
  Copy-Item -LiteralPath $originale -Destination $dest -Force
  $manifest.sorgenti[$p]=@{ prima=(Get-FileHash -LiteralPath $originale -Algorithm SHA256).Hash; dopo=$null }
}
try {
  $temp = $file + '.v38.tmp'
  [IO.File]::WriteAllText($temp, $script:codice, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $temp -Destination $file -Force
  foreach($p in $relativi) { $manifest.sorgenti[$p].dopo=(Get-FileHash -LiteralPath (Join-Path $radice $p) -Algorithm SHA256).Hash }
  # File SQL e rollback generati automaticamente nella cartella del progetto.
  $fileCreatiTC = @()
  $assetTC = @{}
  $assetTC['00_database_v38_preflight.sql'] = @'
-- TEMACASE CRM v38 - Diagnostica SOLO LETTURA, prima di modificare Supabase.
SELECT column_name,data_type,column_default,is_nullable
FROM information_schema.columns
WHERE table_schema='temacase_test' AND table_name='notizie_acquisizione'
  AND column_name IN ('data_segnalazione','venditore_nome','venditore_cognome','venditore_telefono','proprietario_contattato','stato_notizia')
ORDER BY column_name;

SELECT c.conname,pg_get_constraintdef(c.oid) AS definizione
FROM pg_constraint c
WHERE c.conrelid='temacase_test.crm_notizie_contatti'::regclass
  AND c.contype='c'
ORDER BY c.conname;

SELECT count(*) AS notizie_con_dati_legacy
FROM temacase_test.notizie_acquisizione n
WHERE coalesce(nullif(btrim(to_jsonb(n)->>'venditore_nome'),''),
               nullif(btrim(to_jsonb(n)->>'venditore_cognome'),''),
               nullif(btrim(to_jsonb(n)->>'venditore_telefono'),'')) IS NOT NULL
   OR to_jsonb(n)->>'proprietario_contattato' IS NOT NULL;
'@
  $assetTC['01_database_v38_prepara.sql'] = @'
-- TEMACASE CRM v38 - FASE 1 (reversibile).
-- Eseguire in Supabase SQL Editor SOLO dopo conferma dello stato della produzione.
-- Conserva integralmente i valori legacy, valorizza le date mancanti e imposta il default.
-- NON elimina alcuna colonna e NON duplica i contatti della rubrica.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS temacase_test.crm38_backup_notizie (
  id bigint PRIMARY KEY,
  data_segnalazione_precedente date,
  legacy jsonb NOT NULL,
  backup_il timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE temacase_test.crm38_backup_notizie ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm38_backup_notizie FORCE ROW LEVEL SECURITY;
REVOKE ALL ON temacase_test.crm38_backup_notizie FROM PUBLIC, anon, authenticated;

INSERT INTO temacase_test.crm38_backup_notizie (id,data_segnalazione_precedente,legacy)
SELECT n.id,n.data_segnalazione,
  jsonb_build_object(
    'venditore_nome',to_jsonb(n)->'venditore_nome',
    'venditore_cognome',to_jsonb(n)->'venditore_cognome',
    'venditore_telefono',to_jsonb(n)->'venditore_telefono',
    'proprietario_contattato',to_jsonb(n)->'proprietario_contattato'
  )
FROM temacase_test.notizie_acquisizione n
ON CONFLICT(id) DO NOTHING;

CREATE TABLE IF NOT EXISTS temacase_test.crm38_backup_default (
  id boolean PRIMARY KEY DEFAULT true CHECK(id),
  espressione_precedente text,
  backup_il timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE temacase_test.crm38_backup_default ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm38_backup_default FORCE ROW LEVEL SECURITY;
REVOKE ALL ON temacase_test.crm38_backup_default FROM PUBLIC, anon, authenticated;

INSERT INTO temacase_test.crm38_backup_default(id,espressione_precedente)
SELECT true,pg_get_expr(d.adbin,d.adrelid)
FROM pg_attribute a
LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
WHERE a.attrelid='temacase_test.notizie_acquisizione'::regclass
  AND a.attname='data_segnalazione'
ON CONFLICT(id) DO NOTHING;

UPDATE temacase_test.notizie_acquisizione n
SET data_segnalazione = (n.creata_il AT TIME ZONE 'Europe/Rome')::date
WHERE n.data_segnalazione IS NULL;

ALTER TABLE temacase_test.notizie_acquisizione
  ALTER COLUMN data_segnalazione SET DEFAULT ((now() AT TIME ZONE 'Europe/Rome')::date);

COMMIT;

-- Diagnostica: quante notizie conservano dati legacy da migrare prima del DROP?
SELECT count(*) AS notizie_con_dati_legacy_da_migrare
FROM temacase_test.notizie_acquisizione n
WHERE coalesce(nullif(btrim(to_jsonb(n)->>'venditore_nome'),''),
               nullif(btrim(to_jsonb(n)->>'venditore_cognome'),''),
               nullif(btrim(to_jsonb(n)->>'venditore_telefono'),'')) IS NOT NULL
   OR (to_jsonb(n)->>'proprietario_contattato') IS NOT NULL;
'@
  $assetTC['02_database_v38_drop_legacy_SOLO_DOPO_MIGRAZIONE.sql'] = @'
-- FASE 2 FACOLTATIVA: DA NON ESEGUIRE PRIMA della migrazione/riconciliazione dei contatti.
-- Il DROP fallisce senza cancellazioni se ci sono valori legacy da migrare.
-- Supabase SQL Editor, solo dopo la verifica delle dipendenze e dei deploy v38.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$
DECLARE residui bigint;
BEGIN
 SELECT count(*) INTO residui
 FROM temacase_test.crm38_backup_notizie b
 WHERE coalesce(nullif(btrim(b.legacy->>'venditore_nome'),''),
                nullif(btrim(b.legacy->>'venditore_cognome'),''),
                nullif(btrim(b.legacy->>'venditore_telefono'),'')) IS NOT NULL
    OR b.legacy->>'proprietario_contattato' IS NOT NULL;
 IF residui>0 THEN
   RAISE EXCEPTION '% notizie con dati legacy: riconciliare con crm_contatti e crm_notizie_contatti prima di eliminare le colonne',residui;
 END IF;
END $$;
ALTER TABLE temacase_test.notizie_acquisizione
  DROP COLUMN IF EXISTS venditore_nome,
  DROP COLUMN IF EXISTS venditore_cognome,
  DROP COLUMN IF EXISTS venditore_telefono,
  DROP COLUMN IF EXISTS proprietario_contattato;
COMMIT;
'@
  $assetTC['03_database_v38_rollback.sql'] = @'
-- ROLLBACK SQL v38, per la fase 1 e, se eseguita, per il DROP della fase 2.
-- Eseguire SOLO con la versione v37 del codice pronta da ripubblicare.
BEGIN;
SET LOCAL lock_timeout='5s';

ALTER TABLE temacase_test.notizie_acquisizione
  ADD COLUMN IF NOT EXISTS venditore_nome text,
  ADD COLUMN IF NOT EXISTS venditore_cognome text,
  ADD COLUMN IF NOT EXISTS venditore_telefono text,
  ADD COLUMN IF NOT EXISTS proprietario_contattato boolean;

UPDATE temacase_test.notizie_acquisizione n
SET venditore_nome = b.legacy->>'venditore_nome',
    venditore_cognome = b.legacy->>'venditore_cognome',
    venditore_telefono = b.legacy->>'venditore_telefono',
    proprietario_contattato = (b.legacy->>'proprietario_contattato')::boolean
FROM temacase_test.crm38_backup_notizie b
WHERE n.id=b.id
  AND (n.venditore_nome IS NULL AND n.venditore_cognome IS NULL
       AND n.venditore_telefono IS NULL AND n.proprietario_contattato IS NULL);

-- Ripristina soltanto i valori data originariamente null e ancora pari alla data automatica.
UPDATE temacase_test.notizie_acquisizione n
SET data_segnalazione=NULL
FROM temacase_test.crm38_backup_notizie b
WHERE b.id=n.id AND b.data_segnalazione_precedente IS NULL
  AND n.data_segnalazione=(n.creata_il AT TIME ZONE 'Europe/Rome')::date;

DO $$
DECLARE vecchio text;
BEGIN
 SELECT espressione_precedente INTO vecchio FROM temacase_test.crm38_backup_default WHERE id=true;
 IF NOT FOUND THEN RAISE EXCEPTION 'Manca il backup del default v38'; END IF;
 IF vecchio IS NULL THEN
   ALTER TABLE temacase_test.notizie_acquisizione ALTER COLUMN data_segnalazione DROP DEFAULT;
 ELSE
   EXECUTE 'ALTER TABLE temacase_test.notizie_acquisizione ALTER COLUMN data_segnalazione SET DEFAULT '||vecchio;
 END IF;
END $$;
COMMIT;
-- Le tabelle di backup NON vengono eliminate, per consentire una verifica successiva.
'@
  $assetTC['Temacase_v38_rollback.ps1'] = @'
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
'@
  foreach($nomeTC in $assetTC.Keys) {
    $percorsoTC = Join-Path $radice $nomeTC
    if(Test-Path -LiteralPath $percorsoTC) { throw "File gia presente, non sovrascrivo: $percorsoTC" }
    [IO.File]::WriteAllText($percorsoTC, $assetTC[$nomeTC], (New-Object System.Text.UTF8Encoding($false)))
    $fileCreatiTC += $percorsoTC
  }
  $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dirBackup 'manifest.json') -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $radice 'V38_ULTIMO_BACKUP.txt') -Value $dirBackup -Encoding UTF8
  Write-Host "`nSORGENTI v38 PREPARATI. Backup: $dirBackup" -ForegroundColor Green
  Write-Host 'NON sono stati eseguiti SQL, deploy o test reali Telegram/Google.' -ForegroundColor Yellow
} catch {
  foreach($percorsoTC in $fileCreatiTC) { if(Test-Path -LiteralPath $percorsoTC) { Remove-Item -LiteralPath $percorsoTC -Force } }
  foreach($p in $relativi) { Copy-Item -LiteralPath (Join-Path $dirBackup $p) -Destination (Join-Path $radice $p) -Force }
  throw
}
