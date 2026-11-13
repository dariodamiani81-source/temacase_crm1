-- Temacase CRM v58 - permette al bot di cancellare le sole note proprie.
-- Non elimina alcuna nota. La cancellazione avviene soltanto da Telegram,
-- dopo una conferma distinta sul singolo ID.
BEGIN;
DO $$
DECLARE
  rls_on boolean;
  regola_presente boolean;
BEGIN
  SELECT c.relrowsecurity INTO rls_on
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='temacase_test' AND c.relname='crm_sviluppi_notizie';
  IF rls_on IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Sicurezza: RLS non attiva sulla tabella degli sviluppi. Nessun permesso concesso.';
  END IF;
  SELECT EXISTS(
    SELECT 1 FROM pg_policies
    WHERE schemaname='temacase_test' AND tablename='crm_sviluppi_notizie'
      AND policyname='crm_sviluppi_notizie_v55_personali'
      AND cmd='ALL' AND 'public'=ANY(roles)
      AND qual LIKE '%temacase.telegram_user_id%'
  ) INTO regola_presente;
  IF NOT regola_presente THEN
    RAISE EXCEPTION 'Sicurezza: policy personale RLS non riconosciuta. Nessun permesso concesso.';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='temacase_mcp_login') THEN
    RAISE EXCEPTION 'Ruolo temacase_mcp_login non disponibile.';
  END IF;
  GRANT DELETE ON TABLE temacase_test.crm_sviluppi_notizie TO temacase_mcp_login;
END $$;
COMMIT;
SELECT
  has_table_privilege('temacase_mcp_login','temacase_test.crm_sviluppi_notizie','DELETE') AS bot_puo_eliminare_nota,
  (SELECT relrowsecurity FROM pg_class WHERE oid='temacase_test.crm_sviluppi_notizie'::regclass) AS rls_attiva,
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='temacase_test'
    AND tablename='crm_sviluppi_notizie' AND policyname='crm_sviluppi_notizie_v55_personali') AS policy_personale_presente;
