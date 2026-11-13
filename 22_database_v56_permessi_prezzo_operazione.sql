-- TEMACASE CRM v56 - correzione minima dei privilegi sui campi v55
-- Non modifica ne' elimina dati, tabelle, policy RLS o vincoli.
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'temacase_mcp_login') THEN
    RAISE EXCEPTION 'Ruolo temacase_mcp_login non presente';
  END IF;
  IF to_regclass('temacase_test.notizie_acquisizione') IS NULL THEN
    RAISE EXCEPTION 'Tabella temacase_test.notizie_acquisizione non presente';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'temacase_test.notizie_acquisizione'::regclass
      AND attname = 'operazione' AND attnum > 0 AND NOT attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'temacase_test.notizie_acquisizione'::regclass
      AND attname = 'prezzo_richiesto' AND attnum > 0 AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'Colonne operazione/prezzo_richiesto mancanti: verificare migrazione v55';
  END IF;
END $$;

GRANT INSERT (operazione, prezzo_richiesto),
      UPDATE (operazione, prezzo_richiesto)
ON TABLE temacase_test.notizie_acquisizione
TO temacase_mcp_login;

DO $$
BEGIN
  IF NOT (
    has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'operazione', 'INSERT')
    AND has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'prezzo_richiesto', 'INSERT')
    AND has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'operazione', 'UPDATE')
    AND has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'prezzo_richiesto', 'UPDATE')
  ) THEN
    RAISE EXCEPTION 'Verifica privilegi v56 fallita; transazione annullata';
  END IF;
END $$;

COMMIT;

SELECT
  has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'operazione', 'INSERT') AS operazione_insert,
  has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'prezzo_richiesto', 'INSERT') AS prezzo_insert,
  has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'operazione', 'UPDATE') AS operazione_update,
  has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'prezzo_richiesto', 'UPDATE') AS prezzo_update;
