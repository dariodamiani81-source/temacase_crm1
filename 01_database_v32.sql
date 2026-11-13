BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN IF to_regclass('temacase_test.crm_ai_conversazioni') IS NULL THEN RAISE EXCEPTION 'Eseguire prima 01_database_v31.sql, poi ripetere questa query';END IF;END $$;
ALTER TABLE temacase_test.notizie_acquisizione
 ADD COLUMN IF NOT EXISTS archiviata boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS eliminata_il timestamptz;
DROP POLICY IF EXISTS crm32_notizie_visibili ON temacase_test.notizie_acquisizione;
CREATE POLICY crm32_notizie_visibili ON temacase_test.notizie_acquisizione AS RESTRICTIVE
 FOR SELECT TO temacase_mcp_login USING(
 (NOT archiviata OR current_setting('temacase.includi_archiviate',true)='true')
 AND (eliminata_il IS NULL OR current_setting('temacase.includi_cestino',true)='true'));
ALTER TABLE temacase_test.immobili
 ADD COLUMN IF NOT EXISTS operazione text NOT NULL DEFAULT 'da_definire',
 ADD COLUMN IF NOT EXISTS fase_acquisizione text NOT NULL DEFAULT 'da_definire',
 ADD COLUMN IF NOT EXISTS stato_commerciale text NOT NULL DEFAULT 'da_definire',
 ADD COLUMN IF NOT EXISTS riferimento_unita text,
 ADD COLUMN IF NOT EXISTS incarico_dal date,
 ADD COLUMN IF NOT EXISTS incarico_al date,
 ADD COLUMN IF NOT EXISTS esclusiva boolean;
ALTER TABLE temacase_test.crm_immobili_agenzia
 ADD COLUMN IF NOT EXISTS visibilita text NOT NULL DEFAULT 'agenzia',
 ADD COLUMN IF NOT EXISTS consulente_telegram_id bigint;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='crm32_immobile_classificazione' AND conrelid='temacase_test.immobili'::regclass) THEN
 ALTER TABLE temacase_test.immobili ADD CONSTRAINT crm32_immobile_classificazione CHECK(
 operazione IN('da_definire','vendita','locazione','entrambe') AND
 fase_acquisizione IN('da_definire','da_valutare','notizia_in_lavorazione','contatto_avviato','sopralluogo','trattativa_incarico','incarico_acquisito','non_acquisito') AND
 stato_commerciale IN('da_definire','non_sul_mercato','in_preparazione','disponibile','in_trattativa','venduto','locato','sospeso') AND
 (incarico_dal IS NULL OR incarico_al IS NULL OR incarico_al>=incarico_dal));
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='crm32_immobile_visibilita' AND conrelid='temacase_test.crm_immobili_agenzia'::regclass) THEN
 ALTER TABLE temacase_test.crm_immobili_agenzia ADD CONSTRAINT crm32_immobile_visibilita CHECK(
 visibilita IN('privato','agenzia') AND (visibilita='agenzia' OR consulente_telegram_id IS NOT NULL));
 END IF;
END $$;
DROP POLICY IF EXISTS crm32_immobile_proprio ON temacase_test.crm_immobili_agenzia;
CREATE POLICY crm32_immobile_proprio ON temacase_test.crm_immobili_agenzia AS RESTRICTIVE
 FOR SELECT TO temacase_mcp_login USING(visibilita='agenzia' OR consulente_telegram_id=nullif(current_setting('temacase.telegram_user_id',true),'')::bigint);
DROP POLICY IF EXISTS crm32_immobile_visibile ON temacase_test.immobili;
CREATE POLICY crm32_immobile_visibile ON temacase_test.immobili AS RESTRICTIVE
 FOR SELECT TO temacase_mcp_login USING(EXISTS(SELECT 1 FROM temacase_test.crm_immobili_agenzia a WHERE a.immobile_id=immobili.id));
LOCK TABLE temacase_test.immobili IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='temacase_test.immobili'::regclass AND attname='id' AND attidentity='' AND NOT atthasdef) THEN
 CREATE SEQUENCE IF NOT EXISTS temacase_test.crm32_immobili_id_seq;
 PERFORM setval('temacase_test.crm32_immobili_id_seq',greatest(coalesce((SELECT max(id) FROM temacase_test.immobili),0)+1,1),false);
 ALTER TABLE temacase_test.immobili ALTER COLUMN id SET DEFAULT nextval('temacase_test.crm32_immobili_id_seq');
 ALTER SEQUENCE temacase_test.crm32_immobili_id_seq OWNED BY temacase_test.immobili.id;
 END IF;
END $$;
CREATE TABLE IF NOT EXISTS temacase_test.crm_notizie_immobili(
 notizia_id bigint NOT NULL REFERENCES temacase_test.notizie_acquisizione(id),
 immobile_id bigint NOT NULL REFERENCES temacase_test.immobili(id),
 consulente_telegram_id bigint NOT NULL,collegato_il timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(notizia_id,immobile_id)
);
ALTER TABLE temacase_test.crm_notizie_immobili ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_notizie_immobili FORCE ROW LEVEL SECURITY;
REVOKE ALL ON temacase_test.crm_notizie_immobili FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT SELECT ON temacase_test.crm_notizie_immobili TO temacase_mcp_login;
DROP POLICY IF EXISTS crm32_collegamento_proprio ON temacase_test.crm_notizie_immobili;
CREATE POLICY crm32_collegamento_proprio ON temacase_test.crm_notizie_immobili FOR SELECT TO temacase_mcp_login USING(
 consulente_telegram_id=nullif(current_setting('temacase.telegram_user_id',true),'')::bigint
 AND EXISTS(SELECT 1 FROM temacase_test.crm_immobili_agenzia a WHERE a.immobile_id=crm_notizie_immobili.immobile_id));
CREATE OR REPLACE FUNCTION temacase_test.crm23_assegna_storico()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE a uuid;BEGIN
 IF (SELECT count(*) FROM temacase_test.crm_agenzie)=1 THEN
 SELECT id INTO a FROM temacase_test.crm_agenzie;
 IF TG_TABLE_NAME='clienti' THEN INSERT INTO temacase_test.crm_clienti_agenzia(agenzia_id,cliente_id) VALUES(a,NEW.id);
 ELSIF TG_TABLE_NAME='immobili' THEN INSERT INTO temacase_test.crm_immobili_agenzia(agenzia_id,immobile_id) VALUES(a,NEW.id);END IF;
 END IF;RETURN NEW;END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm32_immobile_operativo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM temacase_test.crm_immobili_agenzia WHERE immobile_id=NEW.immobile_id AND visibilita='agenzia')
 THEN RAISE EXCEPTION 'Prima di usare questo immobile nelle attivita condivise, condividilo con agenzia'; END IF;
 RETURN NEW;END $$;
DO $$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['visite','crm_attivita_operative','crm_immobili_contatti'] LOOP
 EXECUTE format('DROP TRIGGER IF EXISTS crm32_immobile_operativo ON temacase_test.%I',t);
 EXECUTE format('CREATE TRIGGER crm32_immobile_operativo BEFORE INSERT OR UPDATE OF immobile_id ON temacase_test.%I FOR EACH ROW EXECUTE FUNCTION temacase_test.crm32_immobile_operativo()',t);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm32_utente() RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=nullif(current_setting('temacase.telegram_user_id',true),'')::bigint;BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM temacase_test.consulenti_telegram WHERE telegram_user_id=u AND attivo) THEN RAISE EXCEPTION 'Accesso negato';END IF;RETURN u;END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm32_notizia(nid bigint,azione text DEFAULT 'leggi',k uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm32_utente();n record;s jsonb;key uuid;v jsonb;BEGIN
 SELECT x.*,p.via,p.civico,p.comune INTO n FROM temacase_test.notizie_acquisizione x
 JOIN temacase_test.palazzi p ON p.id=x.palazzo_id WHERE x.id=nid AND x.consulente_telegram_id=u FOR UPDATE OF x;
 IF NOT FOUND THEN RETURN NULL;END IF;
 IF azione='leggi' THEN RETURN to_jsonb(n);END IF;
 IF azione IN('archivia','riattiva','elimina','ripristina') THEN
 key:=gen_random_uuid();
 INSERT INTO temacase_test.crm_sessioni_telegram(consulente_telegram_id,chiave,stato,scade_il)
 VALUES(u,key,jsonb_build_object('fase','g32_nota','valori',jsonb_build_object('notizia',nid::text,'azione',azione,'attesa',to_jsonb(n))),now()+interval '10 minutes')
 ON CONFLICT(consulente_telegram_id) DO UPDATE SET chiave=excluded.chiave,stato=excluded.stato,scade_il=excluded.scade_il;
 RETURN jsonb_build_object('chiave',key,'notizia',nid::text,'azione',azione,'titolo',n.titolo,'indirizzo',concat(n.via,' ',n.civico,', ',n.comune));
 END IF;
 IF azione<>'conferma' THEN RAISE EXCEPTION 'Azione non valida';END IF;
 SELECT stato INTO s FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k AND scade_il>now() AND stato->>'fase'='g32_nota' FOR UPDATE;
 v:=s->'valori';IF v IS NULL OR v->>'notizia'<>nid::text THEN RETURN NULL;END IF;
 IF to_jsonb(n) IS DISTINCT FROM v->'attesa' THEN RAISE EXCEPTION 'Notizia cambiata: ripetere anteprima';END IF;
 CASE v->>'azione'
 WHEN 'archivia' THEN IF n.eliminata_il IS NOT NULL THEN RAISE EXCEPTION 'Notizia nel cestino';END IF;UPDATE temacase_test.notizie_acquisizione SET archiviata=true WHERE id=nid;
 WHEN 'riattiva' THEN IF n.eliminata_il IS NOT NULL THEN RAISE EXCEPTION 'Notizia nel cestino';END IF;UPDATE temacase_test.notizie_acquisizione SET archiviata=false WHERE id=nid;
 WHEN 'elimina' THEN UPDATE temacase_test.notizie_acquisizione SET eliminata_il=coalesce(eliminata_il,now()) WHERE id=nid;
 WHEN 'ripristina' THEN UPDATE temacase_test.notizie_acquisizione SET eliminata_il=NULL WHERE id=nid;
 ELSE RAISE EXCEPTION 'Azione non valida';END CASE;
 DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k;
 RETURN jsonb_build_object('notizia',nid::text,'azione',v->>'azione','archiviata',CASE WHEN v->>'azione'='archivia' THEN true WHEN v->>'azione'='riattiva' THEN false ELSE n.archiviata END);
END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm32_immobile(iid bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm_google_v2_utente();r jsonb;BEGIN
 SELECT to_jsonb(i)||jsonb_build_object('agenzia',a.agenzia_id::text,'visibilita',a.visibilita,'responsabile',a.consulente_telegram_id::text) INTO r
 FROM temacase_test.immobili i JOIN temacase_test.crm_immobili_agenzia a ON a.immobile_id=i.id
 WHERE i.id=iid AND (a.visibilita='agenzia' OR a.consulente_telegram_id=u)
 AND EXISTS(SELECT 1 FROM temacase_test.crm_membri_agenzia m WHERE m.agenzia_id=a.agenzia_id AND m.consulente_telegram_id=u AND m.attivo);
 RETURN r;END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm32_immobile_salva(k uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm_google_v2_utente();s jsonb;v jsonb;n record;iid bigint;a uuid;r jsonb;vis text;BEGIN
 SELECT stato INTO s FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k AND scade_il>now() AND stato->>'fase'='g32_immobile' FOR UPDATE;
 v:=s->'valori';IF v IS NULL OR v->>'step'<>'conferma' THEN RETURN NULL;END IF;
 IF coalesce(v->>'modo','') NOT IN('nuovo','modifica','collega') THEN RAISE EXCEPTION 'Modalita non valida';END IF;
 IF v->>'notizia' IS NOT NULL THEN
 SELECT x.*,p.via,p.civico,p.comune INTO n FROM temacase_test.notizie_acquisizione x JOIN temacase_test.palazzi p ON p.id=x.palazzo_id
 WHERE x.id=(v->>'notizia')::bigint AND x.consulente_telegram_id=u AND x.eliminata_il IS NULL AND NOT x.archiviata FOR UPDATE OF x;
 IF NOT FOUND OR to_jsonb(n) IS DISTINCT FROM v->'attesa_notizia' THEN RAISE EXCEPTION 'Notizia cambiata o non disponibile';END IF;
 END IF;
 IF v->>'modo'='collega' THEN
 iid:=(v->>'immobile')::bigint;r:=temacase_test.crm32_immobile(iid);
 IF r IS NULL OR r IS DISTINCT FROM v->'atteso_immobile' OR v->>'notizia' IS NULL THEN RAISE EXCEPTION 'Collegamento non disponibile';END IF;
 ELSE
 a:=(v->>'agenzia')::uuid;PERFORM temacase_test.crm_google_v2_utente(a);
 vis:=coalesce(v->>'visibilita','privato');
 IF a IS NULL OR vis NOT IN('privato','agenzia') THEN RAISE EXCEPTION 'Agenzia o visibilita non valida';END IF;
 IF length(coalesce(v->>'tipologia_immobile','')) NOT BETWEEN 1 AND 100 OR length(coalesce(v->>'unita',''))>150
 OR coalesce(v->>'operazione_immobile','') NOT IN('da_definire','vendita','locazione','entrambe')
 OR coalesce(v->>'fase_acquisizione','') NOT IN('da_definire','da_valutare','notizia_in_lavorazione','contatto_avviato','sopralluogo','trattativa_incarico','incarico_acquisito','non_acquisito')
 OR coalesce(v->>'stato_commerciale','') NOT IN('da_definire','non_sul_mercato','in_preparazione','disponibile','in_trattativa','venduto','locato','sospeso') THEN RAISE EXCEPTION 'Classificazione non valida';END IF;
 IF v->>'modo'='nuovo' THEN
 IF v->>'notizia' IS NULL THEN RAISE EXCEPTION 'Notizia di origine mancante';END IF;
 IF coalesce(v->>'duplicati_verificati','false')<>'true' THEN RAISE EXCEPTION 'Verificare prima le unita gia presenti';END IF;
 INSERT INTO temacase_test.immobili(codice,indirizzo,comune,tipologia,operazione,fase_acquisizione,stato_commerciale,riferimento_unita,incarico_dal,incarico_al,esclusiva)
 VALUES('CRM-'||gen_random_uuid()::text,concat(n.via,' ',n.civico),n.comune,v->>'tipologia_immobile',v->>'operazione_immobile',v->>'fase_acquisizione',v->>'stato_commerciale',nullif(v->>'unita',''),(v->>'incarico_dal')::date,(v->>'incarico_al')::date,(v->>'esclusiva')::boolean) RETURNING id INTO iid;
 INSERT INTO temacase_test.crm_immobili_agenzia(agenzia_id,immobile_id,visibilita,consulente_telegram_id) VALUES(a,iid,vis,u)
 ON CONFLICT(immobile_id) DO UPDATE SET agenzia_id=excluded.agenzia_id,visibilita=excluded.visibilita,consulente_telegram_id=excluded.consulente_telegram_id;
 ELSE
 iid:=(v->>'immobile')::bigint;
 PERFORM 1 FROM temacase_test.immobili WHERE id=iid FOR UPDATE;
 r:=temacase_test.crm32_immobile(iid);
 IF r IS NULL OR r IS DISTINCT FROM v->'atteso_immobile' OR r->>'agenzia'<>a::text THEN RAISE EXCEPTION 'Immobile cambiato o non disponibile';END IF;
 IF vis='privato' AND (r->>'responsabile' IS DISTINCT FROM u::text OR EXISTS(SELECT 1 FROM temacase_test.visite WHERE immobile_id=iid) OR EXISTS(SELECT 1 FROM temacase_test.crm_attivita_operative WHERE immobile_id=iid) OR EXISTS(SELECT 1 FROM temacase_test.crm_immobili_contatti WHERE immobile_id=iid)) THEN RAISE EXCEPTION 'Immobile operativo: deve restare condiviso';END IF;
 UPDATE temacase_test.immobili SET tipologia=v->>'tipologia_immobile',operazione=v->>'operazione_immobile',fase_acquisizione=v->>'fase_acquisizione',stato_commerciale=v->>'stato_commerciale',riferimento_unita=nullif(v->>'unita',''),incarico_dal=(v->>'incarico_dal')::date,incarico_al=(v->>'incarico_al')::date,esclusiva=(v->>'esclusiva')::boolean WHERE id=iid;
 UPDATE temacase_test.crm_immobili_agenzia SET visibilita=vis WHERE immobile_id=iid;
 END IF;
 END IF;
 IF v->>'notizia' IS NOT NULL THEN
 INSERT INTO temacase_test.crm_notizie_immobili(notizia_id,immobile_id,consulente_telegram_id) VALUES((v->>'notizia')::bigint,iid,u) ON CONFLICT DO NOTHING;
 END IF;
 DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k;
 RETURN jsonb_build_object('immobile',iid::text,'notizia',v->>'notizia');END $$;
REVOKE ALL ON FUNCTION temacase_test.crm32_utente(),temacase_test.crm32_immobile_operativo() FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
REVOKE ALL ON FUNCTION temacase_test.crm32_notizia(bigint,text,uuid),temacase_test.crm32_immobile(bigint),temacase_test.crm32_immobile_salva(uuid) FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT EXECUTE ON FUNCTION temacase_test.crm32_notizia(bigint,text,uuid),temacase_test.crm32_immobile(bigint),temacase_test.crm32_immobile_salva(uuid) TO temacase_mcp_login;
COMMIT;
