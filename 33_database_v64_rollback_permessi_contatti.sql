-- Revoca i soli privilegi aggiunti dalla v64.
-- Eseguire esclusivamente se si desidera rimuovere la capacita di modifica dei contatti.
BEGIN;
SET LOCAL lock_timeout='5s';
DROP POLICY IF EXISTS crm64_update_contatti_propri ON temacase_test.crm_contatti;
REVOKE UPDATE (tipo_soggetto,nome,cognome,ragione_sociale,telefono,email,altri_recapiti,visibilita,archiviato)
ON temacase_test.crm_contatti FROM temacase_mcp_login;
COMMIT;
