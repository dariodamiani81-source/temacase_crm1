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