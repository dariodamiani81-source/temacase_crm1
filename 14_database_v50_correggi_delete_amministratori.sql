-- Temacase CRM: abilita eliminazione anagrafica amministratore dal bot.
-- Risolve il probabile SQLSTATE 42501 sul DELETE della tabella amministratori.
-- Mantiene tutte le anagrafiche, foto e associazioni esistenti: nessuna riga viene cancellata qui.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $guard$
DECLARE v_rls boolean; v_bypass boolean; v_owner boolean;
BEGIN
 SELECT c.relrowsecurity, r.rolbypassrls, c.relowner=r.oid
 INTO v_rls,v_bypass,v_owner
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN pg_roles r
 WHERE n.nspname='temacase_test' AND c.relname='amministratori'
 AND r.rolname='temacase_mcp_login' AND c.relkind IN ('r','p');
 IF v_rls IS DISTINCT FROM true OR v_bypass IS DISTINCT FROM false OR v_owner IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Sicurezza RLS amministratori da verificare: nessun permesso concesso';
 END IF;
END $guard$;

-- Policy aggiuntiva limitata alla sola cancellazione delle proprie anagrafiche.
-- Non permette di cancellare quelle create da altri consulenti.
DO $pol$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE schemaname='temacase_test' AND tablename='amministratori'
    AND policyname='temacase_bot_delete_amministratori_propri') THEN
  CREATE POLICY temacase_bot_delete_amministratori_propri
   ON temacase_test.amministratori FOR DELETE TO temacase_mcp_login
   USING (consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id', true), '')::bigint);
 END IF;
END $pol$;
GRANT DELETE ON TABLE temacase_test.amministratori TO temacase_mcp_login;
COMMIT;
SELECT
 has_table_privilege('temacase_mcp_login','temacase_test.amministratori','DELETE') AS puo_eliminare_amministratori,
 (SELECT relrowsecurity FROM pg_class WHERE oid='temacase_test.amministratori'::regclass) AS rls_attiva,
 EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='temacase_test' AND tablename='amministratori' AND policyname='temacase_bot_delete_amministratori_propri') AS policy_solo_propri_presente;
