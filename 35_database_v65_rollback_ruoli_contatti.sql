-- Rollback solo della funzione v65, senza cancellare contatti o collegamenti.
BEGIN;
SET LOCAL lock_timeout='5s';
DROP FUNCTION IF EXISTS temacase_test.crm65_ruolo_contatto(text,bigint,bigint,text,boolean);
COMMIT;
