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