-- TEMACASE v60 - ripristino delle modifiche alle notizie, senza cambiare dati esistenti.
-- Eseguire con SQL Editor di Supabase. Privilegi limitati ai campi modificabili.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $$
DECLARE c text;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='temacase_mcp_login') THEN
   RAISE EXCEPTION 'Ruolo applicativo temacase_mcp_login assente';
 END IF;
 IF to_regclass('temacase_test.notizie_acquisizione') IS NULL THEN
   RAISE EXCEPTION 'Tabella notizie_acquisizione assente';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='temacase_test.notizie_acquisizione'::regclass AND relrowsecurity) THEN
   RAISE EXCEPTION 'RLS non attiva: nessun permesso aggiunto';
 END IF;
 FOREACH c IN ARRAY ARRAY['titolo','palazzo_id','stato_notizia','data_segnalazione','fonte',
   'scala','piano','tipologia_immobile','numero_locali','operazione','prezzo_richiesto',
   'incarico_in_essere','agenzia_incaricata','scadenza_incarico','testo'] LOOP
   IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='temacase_test' AND table_name='notizie_acquisizione' AND column_name=c) THEN
     RAISE EXCEPTION 'Colonna prevista mancante: %',c;
   END IF;
 END LOOP;
END $$;
GRANT UPDATE (
  titolo, palazzo_id, stato_notizia, data_segnalazione, fonte, scala,
  piano, tipologia_immobile, numero_locali, operazione, prezzo_richiesto,
  incarico_in_essere, agenzia_incaricata, scadenza_incarico, testo
) ON temacase_test.notizie_acquisizione TO temacase_mcp_login;
-- Anche se le policy precedenti fossero state sovrascritte, non consentire mai
-- la modifica di una notizia di un altro consulente.
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='temacase_test'
   AND tablename='notizie_acquisizione' AND policyname='crm60_notizie_update_proprie') THEN
   CREATE POLICY crm60_notizie_update_proprie
     ON temacase_test.notizie_acquisizione FOR UPDATE TO temacase_mcp_login
     USING (consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id',true),'')::bigint)
     WITH CHECK (consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id',true),'')::bigint);
 END IF;
END $$;
SELECT c.colonna,
       has_column_privilege('temacase_mcp_login','temacase_test.notizie_acquisizione',c.colonna,'UPDATE') AS puo_modificare,
       (SELECT relrowsecurity FROM pg_class WHERE oid='temacase_test.notizie_acquisizione'::regclass) AS rls_attiva,
       EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='temacase_test'
            AND tablename='notizie_acquisizione' AND policyname='crm60_notizie_update_proprie') AS policy_personale
FROM (VALUES ('titolo'),('palazzo_id'),('stato_notizia'),('data_segnalazione'),('fonte'),
 ('scala'),('piano'),('tipologia_immobile'),('numero_locali'),('operazione'),('prezzo_richiesto'),
 ('incarico_in_essere'),('agenzia_incaricata'),('scadenza_incarico'),('testo')) AS c(colonna)
ORDER BY c.colonna;
COMMIT;
