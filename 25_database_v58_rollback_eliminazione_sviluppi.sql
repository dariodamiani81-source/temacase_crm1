-- Temacase CRM v58 - ripristina i privilegi di cancellazione precedenti.
-- Non cancella note né altera lo storico.
BEGIN;
REVOKE DELETE ON TABLE temacase_test.crm_sviluppi_notizie FROM temacase_mcp_login;
COMMIT;
SELECT has_table_privilege('temacase_mcp_login','temacase_test.crm_sviluppi_notizie','DELETE') AS bot_puo_eliminare_nota;
