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