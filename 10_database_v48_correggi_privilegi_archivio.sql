-- TEMACASE CRM v48 - privilegio mirato per connessione PostgreSQL del bot
-- Nessuna modifica ad anagrafiche, associazioni, policy RLS o dati.
BEGIN;
SET LOCAL lock_timeout = '5s';
GRANT SELECT, INSERT, DELETE ON TABLE temacase_test.crm_amministratori_archivio TO temacase_mcp_login;
COMMIT;
SELECT
  has_table_privilege('temacase_mcp_login', 'temacase_test.crm_amministratori_archivio', 'SELECT') AS puo_leggere_archivio,
  has_table_privilege('temacase_mcp_login', 'temacase_test.crm_amministratori_archivio', 'INSERT') AS puo_archiviare,
  has_table_privilege('temacase_mcp_login', 'temacase_test.crm_amministratori_archivio', 'DELETE') AS puo_ripristinare;
