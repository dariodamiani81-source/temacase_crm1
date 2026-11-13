-- TEMACASE v63: collega Task personali esistenti a Notizie, senza duplicare eventi Google.
-- La migrazione non crea né modifica Task, Notizie o eventi Google.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $$ BEGIN
 IF to_regclass('temacase_test.crm_attivita_personali') IS NULL OR
    to_regclass('temacase_test.notizie_acquisizione') IS NULL OR
    to_regclass('temacase_test.crm_google_invii') IS NULL THEN
  RAISE EXCEPTION 'Le tabelle CRM previste non sono presenti. Nessuna modifica.';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='temacase_mcp_login') THEN
  RAISE EXCEPTION 'Ruolo CRM mancante.';
 END IF;
END $$;
CREATE TABLE IF NOT EXISTS temacase_test.crm_personali_notizie(
 personale_id uuid PRIMARY KEY REFERENCES temacase_test.crm_attivita_personali(id) ON DELETE CASCADE,
 notizia_id bigint NOT NULL REFERENCES temacase_test.notizie_acquisizione(id) ON DELETE CASCADE,
 consulente_telegram_id bigint NOT NULL,
 associato_il timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS crm_personali_notizie_nota_idx
 ON temacase_test.crm_personali_notizie(consulente_telegram_id,notizia_id);
ALTER TABLE temacase_test.crm_personali_notizie ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_personali_notizie FORCE ROW LEVEL SECURITY;
REVOKE ALL ON temacase_test.crm_personali_notizie FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT SELECT,INSERT ON temacase_test.crm_personali_notizie TO temacase_mcp_login;
DROP POLICY IF EXISTS crm63_personali_nota_propria ON temacase_test.crm_personali_notizie;
CREATE POLICY crm63_personali_nota_propria ON temacase_test.crm_personali_notizie
 FOR ALL TO temacase_mcp_login
 USING (
  consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id',true),'')::bigint
  AND EXISTS(SELECT 1 FROM temacase_test.crm_attivita_personali a WHERE a.id=personale_id AND a.consulente_telegram_id=crm_personali_notizie.consulente_telegram_id)
  AND EXISTS(SELECT 1 FROM temacase_test.notizie_acquisizione n WHERE n.id=notizia_id AND n.consulente_telegram_id=crm_personali_notizie.consulente_telegram_id)
 )
 WITH CHECK (
  consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id',true),'')::bigint
  AND EXISTS(SELECT 1 FROM temacase_test.crm_attivita_personali a WHERE a.id=personale_id AND a.consulente_telegram_id=crm_personali_notizie.consulente_telegram_id)
  AND EXISTS(SELECT 1 FROM temacase_test.notizie_acquisizione n WHERE n.id=notizia_id AND n.consulente_telegram_id=crm_personali_notizie.consulente_telegram_id)
 );
-- Riutilizza la funzione di descrizione Google già collaudata (v37): cambia
-- esclusivamente il ramo personale per leggere una Notizia SE collegata.
-- La funzione viene derivata dalla definizione attualmente installata,
-- preservando gli altri rami e le evoluzioni successive.
DO $v63$
DECLARE ddl text;old_fragment text;new_fragment text;
BEGIN
 ddl:=pg_get_functiondef('temacase_test.crm37_testo(uuid)'::regprocedure);
 old_fragment:='link:=''https://t.me/temacase_crm_bot?start=attivita'';';
 IF strpos(ddl,old_fragment)=0 OR strpos(ddl,'crm_personali_notizie')>0 THEN
  RAISE EXCEPTION 'Definizione Google non conforme alla versione attesa. Nessuna migrazione applicata.';
 END IF;
 new_fragment:=old_fragment||E'\n'||
 $extra$  -- Il Task resta personale nel CRM ma eredita il contesto della Notizia esplicitamente associata.
  SELECT to_jsonb(z),z.id,z.palazzo_id INTO n,nid,pid
  FROM temacase_test.crm_personali_notizie l
  JOIN temacase_test.notizie_acquisizione z ON z.id=l.notizia_id
  WHERE l.personale_id=o.fonte_id AND l.consulente_telegram_id=u AND z.consulente_telegram_id=u;
  IF nid IS NOT NULL THEN link:='https://t.me/temacase_crm_bot?start=notizia_'||nid;END IF;
$extra$;
 EXECUTE replace(ddl,old_fragment,new_fragment);
END $v63$;
-- Aggiunge Prezzo richiesto ai dettagli (il helper esistente già formatta i campi).
DO $v63$
DECLARE ddl text;orig text;
BEGIN
 ddl:=pg_get_functiondef('temacase_test.crm37_campi(jsonb)'::regprocedure);
 orig:=$x$'prezzo','operazione'$x$;
 IF strpos(ddl,$x$'prezzo_richiesto'$x$)=0 THEN
  IF strpos(ddl,orig)=0 THEN RAISE EXCEPTION 'Helper descrizioni inatteso, nessuna migrazione.';END IF;
  EXECUTE replace(ddl,orig,$x$'prezzo','prezzo_richiesto','operazione'$x$);
 END IF;
END $v63$;
SELECT
 to_regclass('temacase_test.crm_personali_notizie') IS NOT NULL AS collegamenti_disponibili,
 has_table_privilege('temacase_mcp_login','temacase_test.crm_personali_notizie','SELECT') AS bot_puo_leggere,
 has_table_privilege('temacase_mcp_login','temacase_test.crm_personali_notizie','INSERT') AS bot_puo_collegare,
 (SELECT relrowsecurity FROM pg_class WHERE oid='temacase_test.crm_personali_notizie'::regclass) AS rls_attiva,
 strpos(pg_get_functiondef('temacase_test.crm37_testo(uuid)'::regprocedure),'crm_personali_notizie')>0 AS descrizione_google_collegata;
COMMIT;
