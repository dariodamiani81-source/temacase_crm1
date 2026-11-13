-- Temacase v59 - rollback prudenziale.
-- Non elimina la tabella se contiene allegati, per non perdere riferimenti Telegram.
DO $$
BEGIN
 IF to_regclass('temacase_test.crm_allegati_notizie') IS NULL THEN RETURN; END IF;
 IF EXISTS (SELECT 1 FROM temacase_test.crm_allegati_notizie LIMIT 1) THEN
   RAISE EXCEPTION 'Rollback bloccato: ci sono allegati da conservare. Nessun dato eliminato.';
 END IF;
END $$;
BEGIN;
DROP TABLE IF EXISTS temacase_test.crm_allegati_notizie;
COMMIT;
