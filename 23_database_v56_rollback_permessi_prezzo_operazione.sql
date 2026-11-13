-- TEMACASE CRM v56 - rollback dei soli privilegi sulle due colonne v55.
-- ATTENZIONE: eseguire SOLO se si desidera disabilitare nuovamente salvataggio/modifica
-- di operazione e prezzo_richiesto mediante il ruolo temacase_mcp_login.
-- Non modifica i dati gia' registrati.
BEGIN;
REVOKE INSERT (operazione, prezzo_richiesto),
       UPDATE (operazione, prezzo_richiesto)
ON TABLE temacase_test.notizie_acquisizione
FROM temacase_mcp_login;
COMMIT;
SELECT
  has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'operazione', 'INSERT') AS operazione_insert,
  has_column_privilege('temacase_mcp_login', 'temacase_test.notizie_acquisizione', 'prezzo_richiesto', 'INSERT') AS prezzo_insert;
