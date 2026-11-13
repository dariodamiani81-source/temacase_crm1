-- Rollback dei soli privilegi concessi da 10_database_v48_correggi_privilegi_archivio.sql.
-- Attenzione: non eseguire finche il bot richiede questi privilegi.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE SELECT, INSERT, DELETE ON TABLE temacase_test.crm_amministratori_archivio FROM temacase_mcp_login;
COMMIT;
