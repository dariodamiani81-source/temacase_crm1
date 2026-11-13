BEGIN;
SET LOCAL lock_timeout='5s';
CREATE TABLE IF NOT EXISTS temacase_test.crm_google_account_preferito(
 consulente_telegram_id bigint PRIMARY KEY,
 agenzia_id uuid NOT NULL,
 account_id uuid NOT NULL,
 calendario uuid NOT NULL REFERENCES temacase_test.crm_google_destinazioni(id),
 tasks uuid NOT NULL REFERENCES temacase_test.crm_google_destinazioni(id),
 aggiornato_il timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(account_id,agenzia_id,consulente_telegram_id)
  REFERENCES temacase_test.crm_google_account(id,agenzia_id,consulente_telegram_id),
 CHECK(calendario<>tasks)
);
ALTER TABLE temacase_test.crm_google_account_preferito ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_google_account_preferito FORCE ROW LEVEL SECURITY;
REVOKE ALL ON temacase_test.crm_google_account_preferito
 FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT SELECT ON temacase_test.crm_google_account_preferito TO temacase_mcp_login;
DROP POLICY IF EXISTS account_preferito_proprio ON temacase_test.crm_google_account_preferito;
CREATE POLICY account_preferito_proprio ON temacase_test.crm_google_account_preferito
 FOR SELECT TO temacase_mcp_login USING(
 consulente_telegram_id=nullif(current_setting('temacase.telegram_user_id',true),'')::bigint
 AND EXISTS(SELECT 1 FROM temacase_test.crm_membri_agenzia m
 WHERE m.agenzia_id=crm_google_account_preferito.agenzia_id
 AND m.consulente_telegram_id=crm_google_account_preferito.consulente_telegram_id AND m.attivo));
-- Conserva la scelta esistente soltanto se calendario e Tasks appartengono
-- allo stesso account e c'e una sola configurazione completa per utente.
WITH candidati AS(
 SELECT p.consulente_telegram_id,p.agenzia_id,c.connessione_id,p.calendario,p.tasks,
 count(*) OVER(PARTITION BY p.consulente_telegram_id) AS quanti
 FROM temacase_test.crm_google_preferenze p
 JOIN temacase_test.crm_google_destinazioni c ON c.id=p.calendario AND c.tipo='calendario' AND c.attiva
 JOIN temacase_test.crm_google_destinazioni t ON t.id=p.tasks AND t.tipo='tasks' AND t.attiva
 JOIN temacase_test.crm_google_account a ON a.id=c.connessione_id AND a.stato='attivo'
 WHERE c.connessione_id=t.connessione_id AND c.consulente_telegram_id=p.consulente_telegram_id
 AND t.consulente_telegram_id=p.consulente_telegram_id
)
INSERT INTO temacase_test.crm_google_account_preferito(consulente_telegram_id,agenzia_id,account_id,calendario,tasks)
 SELECT consulente_telegram_id,agenzia_id,connessione_id,calendario,tasks FROM candidati WHERE quanti=1
 ON CONFLICT(consulente_telegram_id) DO NOTHING;
CREATE OR REPLACE FUNCTION temacase_test.crm30_account_preferito(k uuid,cal uuid,task uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm_google_v2_utente();
 a temacase_test.crm_google_account%ROWTYPE;c temacase_test.crm_google_destinazioni%ROWTYPE;
 t temacase_test.crm_google_destinazioni%ROWTYPE;
BEGIN
 SELECT * INTO a FROM temacase_test.crm_google_account
 WHERE id=k AND consulente_telegram_id=u AND stato='attivo' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Account non disponibile'; END IF;
 PERFORM temacase_test.crm_google_v2_utente(a.agenzia_id);
 SELECT * INTO c FROM temacase_test.crm_google_destinazioni
 WHERE id=cal AND connessione_id=k AND consulente_telegram_id=u AND attiva AND tipo='calendario' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Calendario non appartenente a questo account'; END IF;
 SELECT * INTO t FROM temacase_test.crm_google_destinazioni
 WHERE id=task AND connessione_id=k AND consulente_telegram_id=u AND attiva AND tipo='tasks' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Lista Tasks non appartenente a questo account'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('account-preferito:'||u::text,30));
 INSERT INTO temacase_test.crm_google_account_preferito(consulente_telegram_id,agenzia_id,account_id,calendario,tasks)
 VALUES(u,a.agenzia_id,k,cal,task)
 ON CONFLICT(consulente_telegram_id) DO UPDATE SET agenzia_id=excluded.agenzia_id,account_id=excluded.account_id,
 calendario=excluded.calendario,tasks=excluded.tasks,aggiornato_il=now();
 INSERT INTO temacase_test.crm_google_preferenze(agenzia_id,consulente_telegram_id,calendario,tasks)
 VALUES(a.agenzia_id,u,cal,task)
 ON CONFLICT(agenzia_id,consulente_telegram_id) DO UPDATE SET calendario=excluded.calendario,tasks=excluded.tasks;
 RETURN jsonb_build_object('email',a.google_email,'calendario',c.nome,'tasks',t.nome);
END $$;
REVOKE ALL ON FUNCTION temacase_test.crm30_account_preferito(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT EXECUTE ON FUNCTION temacase_test.crm30_account_preferito(uuid,uuid,uuid) TO temacase_mcp_login;
COMMIT;
