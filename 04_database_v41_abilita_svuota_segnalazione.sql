-- TEMACASE CRM v41: abilita il comando "svuota" per la Segnalazione.
-- Mantiene testo NOT NULL; la stringa vuota '' e' un valore valido.
-- Non modifica alcuna notizia esistente.
BEGIN;
ALTER TABLE temacase_test.notizie_acquisizione
  DROP CONSTRAINT IF EXISTS notizie_acquisizione_testo_check;
COMMIT;

-- Verifica: deve restituire consentito = true.
SELECT
  NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'temacase_test.notizie_acquisizione'::regclass
      AND conname = 'notizie_acquisizione_testo_check'
  ) AS svuotamento_consentito,
  (SELECT count(*) FROM temacase_test.notizie_acquisizione WHERE btrim(testo) = '')
    AS notizie_con_segnalazione_vuota;
