-- TEMACASE v55 rollback protetto. Da eseguire SOLO dopo ripristino v54 del codice.
-- Interrompe se sono presenti prezzi/operazioni o aggiornamenti nello storico.
BEGIN;
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM temacase_test.notizie_acquisizione WHERE operazione IS NOT NULL OR prezzo_richiesto IS NOT NULL) THEN
   RAISE EXCEPTION 'Rollback bloccato: prezzi o operazioni già compilati. Non cancellare i dati.';
 END IF;
 IF EXISTS (SELECT 1 FROM temacase_test.crm_sviluppi_notizie LIMIT 1) THEN
   RAISE EXCEPTION 'Rollback bloccato: lo storico contiene aggiornamenti. Non cancellare i dati.';
 END IF;
END $$;
DROP TABLE IF EXISTS temacase_test.crm_sviluppi_notizie;
ALTER TABLE temacase_test.notizie_acquisizione
 DROP COLUMN IF EXISTS operazione,
 DROP COLUMN IF EXISTS prezzo_richiesto;
COMMIT;
