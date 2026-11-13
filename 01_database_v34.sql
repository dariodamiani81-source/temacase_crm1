BEGIN;
SET LOCAL lock_timeout='5s';
CREATE TABLE IF NOT EXISTS temacase_test.crm_archivi_personali(
 consulente_telegram_id bigint NOT NULL, tipo text NOT NULL CHECK(tipo IN('immobili','custodi')),
 record_id bigint NOT NULL, archiviato_il timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(consulente_telegram_id,tipo,record_id));
ALTER TABLE temacase_test.crm_archivi_personali ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_archivi_personali FORCE ROW LEVEL SECURITY;
REVOKE ALL ON temacase_test.crm_archivi_personali FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT SELECT ON temacase_test.crm_archivi_personali TO temacase_mcp_login;
DROP POLICY IF EXISTS crm34_archivi_propri ON temacase_test.crm_archivi_personali;
CREATE POLICY crm34_archivi_propri ON temacase_test.crm_archivi_personali FOR SELECT TO temacase_mcp_login USING(consulente_telegram_id=nullif(current_setting('temacase.telegram_user_id',true),'')::bigint);
CREATE OR REPLACE FUNCTION temacase_test.crm34_salva(k uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm32_utente();s jsonb;v jsonb;r jsonb;i bigint;c temacase_test.custodi%ROWTYPE;BEGIN
 SELECT stato INTO s FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k AND scade_il>now() FOR UPDATE;
 v:=s->'valori';IF v IS NULL OR v->>'step'<>'conferma' THEN RETURN NULL;END IF;
 IF s->>'fase'='g34_archivio' THEN
 i:=(v->>'record')::bigint;
 IF v->>'modulo'='immobili' THEN
 IF temacase_test.crm32_immobile(i) IS NULL THEN RAISE EXCEPTION 'Immobile non disponibile';END IF;
 ELSIF v->>'modulo'='custodi' THEN
 IF NOT EXISTS(SELECT 1 FROM temacase_test.custodi WHERE id=i AND consulente_telegram_id=u) THEN RAISE EXCEPTION 'Custode non disponibile';END IF;
 ELSE RAISE EXCEPTION 'Modulo non valido';END IF;
 IF coalesce((v->>'archivia')::boolean,false) THEN
 INSERT INTO temacase_test.crm_archivi_personali(consulente_telegram_id,tipo,record_id) VALUES(u,v->>'modulo',i) ON CONFLICT DO NOTHING;
 ELSE DELETE FROM temacase_test.crm_archivi_personali WHERE consulente_telegram_id=u AND tipo=v->>'modulo' AND record_id=i;END IF;
 r:=jsonb_build_object('record',i::text,'archiviato',v->'archivia');
 ELSIF s->>'fase'='g34_custode' THEN
 IF length(btrim(concat_ws(' ',v->>'nome',v->>'cognome'))) NOT BETWEEN 2 AND 200 OR length(coalesce(v->>'telefono',''))>80 OR length(coalesce(v->>'email',''))>254 OR length(coalesce(v->>'altri_recapiti',''))>1000 OR length(coalesce(v->>'nazionalita',''))>100 THEN RAISE EXCEPTION 'Dati custode non validi';END IF;
 IF v->>'record' IS NOT NULL THEN
 SELECT * INTO c FROM temacase_test.custodi WHERE id=(v->>'record')::bigint AND consulente_telegram_id=u FOR UPDATE;
 IF NOT FOUND OR to_jsonb(c) IS DISTINCT FROM v->'atteso' THEN RAISE EXCEPTION 'Custode cambiato o non disponibile';END IF;
 UPDATE temacase_test.custodi SET nome=v->>'nome',cognome=v->>'cognome',telefono=v->>'telefono',email=v->>'email',altri_recapiti=v->>'altri_recapiti',nazionalita=v->>'nazionalita' WHERE id=c.id RETURNING id INTO i;
 ELSE
 INSERT INTO temacase_test.custodi(consulente_telegram_id,nome,cognome,telefono,email,altri_recapiti,nazionalita) VALUES(u,v->>'nome',v->>'cognome',v->>'telefono',v->>'email',v->>'altri_recapiti',v->>'nazionalita') RETURNING id INTO i;
 END IF;r:=jsonb_build_object('record',i::text);
 ELSE RETURN NULL;END IF;
 DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k;
 RETURN r;END $$;
REVOKE ALL ON FUNCTION temacase_test.crm34_salva(uuid) FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT EXECUTE ON FUNCTION temacase_test.crm34_salva(uuid) TO temacase_mcp_login;
CREATE OR REPLACE FUNCTION temacase_test.crm32_immobile_salva(k uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm_google_v2_utente();s jsonb;v jsonb;n record;iid bigint;a uuid;r jsonb;vis text;ind text;citta text;BEGIN
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
 IF v->>'notizia' IS NULL THEN ind:=v->>'indirizzo';citta:=v->>'comune';ELSE ind:=concat(n.via,' ',n.civico);citta:=n.comune;END IF;
 IF v->>'notizia' IS NULL AND (length(btrim(coalesce(v->>'indirizzo',''))) NOT BETWEEN 3 AND 250 OR length(btrim(coalesce(v->>'comune',''))) NOT BETWEEN 2 AND 100) THEN RAISE EXCEPTION 'Indirizzo e comune obbligatori';END IF;
 IF coalesce(v->>'duplicati_verificati','false')<>'true' THEN RAISE EXCEPTION 'Verificare prima le unita gia presenti';END IF;
 INSERT INTO temacase_test.immobili(codice,indirizzo,comune,tipologia,operazione,fase_acquisizione,stato_commerciale,riferimento_unita,incarico_dal,incarico_al,esclusiva)
 VALUES('CRM-'||gen_random_uuid()::text,ind,citta,v->>'tipologia_immobile',v->>'operazione_immobile',v->>'fase_acquisizione',v->>'stato_commerciale',nullif(v->>'unita',''),(v->>'incarico_dal')::date,(v->>'incarico_al')::date,(v->>'esclusiva')::boolean) RETURNING id INTO iid;
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
COMMIT;
