-- Rollback mirato dell'intervento 14; non tocca dati, foto o collegamenti.
BEGIN;
SET LOCAL lock_timeout='5s';
REVOKE DELETE ON TABLE temacase_test.amministratori FROM temacase_mcp_login;
DROP POLICY IF EXISTS temacase_bot_delete_amministratori_propri ON temacase_test.amministratori;
COMMIT;
SELECT NOT has_table_privilege('temacase_mcp_login','temacase_test.amministratori','DELETE') AS delete_revocato;
