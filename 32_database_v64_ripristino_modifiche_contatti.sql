-- TEMACASE v64: ripristina modifiche ai soli campi dei contatti.
-- Non modifica o elimina alcun contatto e non disattiva la RLS.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$
BEGIN
  IF to_regclass('temacase_test.crm_contatti') IS NULL THEN
    RAISE EXCEPTION 'Tabella crm_contatti non disponibile';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='temacase_mcp_login') THEN
    RAISE EXCEPTION 'Ruolo temacase_mcp_login non disponibile';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='temacase_test.crm_contatti'::regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'RLS disattivata: nessun permesso concesso';
  END IF;
END $$;
GRANT UPDATE (tipo_soggetto,nome,cognome,ragione_sociale,telefono,email,altri_recapiti,visibilita,archiviato)
ON temacase_test.crm_contatti TO temacase_mcp_login;
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='temacase_test' AND tablename='crm_contatti' AND policyname='crm64_update_contatti_propri') THEN
  CREATE POLICY crm64_update_contatti_propri
  ON temacase_test.crm_contatti FOR UPDATE TO temacase_mcp_login
  USING (consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id',true),'')::bigint)
  WITH CHECK (consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id',true),'')::bigint);
 END IF;
END $$;
SELECT c.colonna,
       has_column_privilege('temacase_mcp_login','temacase_test.crm_contatti',c.colonna,'UPDATE') AS puo_modificare,
       (SELECT relrowsecurity FROM pg_class WHERE oid='temacase_test.crm_contatti'::regclass) AS rls_attiva,
       EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='temacase_test' AND tablename='crm_contatti' AND policyname='crm64_update_contatti_propri') AS policy_personale
FROM (VALUES ('tipo_soggetto'),('nome'),('cognome'),('ragione_sociale'),('telefono'),('email'),('altri_recapiti'),('visibilita'),('archiviato')) c(colonna)
ORDER BY c.colonna;
COMMIT;
