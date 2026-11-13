-- TEMACASE CRM v48 - rollback dello schema, SOLO DOPO il rollback del bot.
-- Se esistono archiviazioni, non cancella nulla: le anagrafiche restano protette.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $rollback$
BEGIN
 IF to_regclass('temacase_test.crm_amministratori_archivio') IS NULL THEN
    RETURN;
 END IF;
 IF EXISTS (SELECT 1 FROM temacase_test.crm_amministratori_archivio LIMIT 1) THEN
    RAISE EXCEPTION 'Rollback SQL interrotto: esistono amministratori archiviati. Ripristinali prima di rimuovere la tabella.';
 END IF;
 DROP TABLE temacase_test.crm_amministratori_archivio;
END;
$rollback$;
COMMIT;
