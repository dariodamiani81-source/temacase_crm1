BEGIN;
SET LOCAL lock_timeout='5s';
CREATE TABLE IF NOT EXISTS temacase_test.crm_immobili_referenti(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 consulente_telegram_id bigint NOT NULL,
 immobile_id bigint NOT NULL REFERENCES temacase_test.immobili(id),
 tipo text NOT NULL CHECK(tipo IN('proprietario','custode')),
 contatto_id bigint REFERENCES temacase_test.crm_contatti(id),
 custode_id bigint REFERENCES temacase_test.custodi(id),
 collegato_il timestamptz NOT NULL DEFAULT now(),
 CHECK((tipo='proprietario' AND contatto_id IS NOT NULL AND custode_id IS NULL) OR (tipo='custode' AND custode_id IS NOT NULL AND contatto_id IS NULL)));
CREATE UNIQUE INDEX IF NOT EXISTS crm35_proprietario_unico ON temacase_test.crm_immobili_referenti(consulente_telegram_id,immobile_id,contatto_id) WHERE tipo='proprietario';
CREATE UNIQUE INDEX IF NOT EXISTS crm35_custode_unico ON temacase_test.crm_immobili_referenti(consulente_telegram_id,immobile_id,custode_id) WHERE tipo='custode';
ALTER TABLE temacase_test.crm_immobili_referenti ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_immobili_referenti FORCE ROW LEVEL SECURITY;
REVOKE ALL ON temacase_test.crm_immobili_referenti FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
CREATE OR REPLACE FUNCTION temacase_test.crm35_persona(i bigint,t text,r bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm32_utente();p jsonb;x jsonb;BEGIN
 p:=temacase_test.crm32_immobile(i);IF p IS NULL THEN RETURN NULL;END IF;
 IF t='custode' THEN SELECT to_jsonb(c)||jsonb_build_object('nome_visualizzato',btrim(concat_ws(' ',c.nome,c.cognome))) INTO x FROM temacase_test.custodi c WHERE c.id=r AND c.consulente_telegram_id=u;
 ELSIF t='proprietario' THEN
 SELECT to_jsonb(c)||jsonb_build_object('nome_visualizzato',coalesce(nullif(c.ragione_sociale,''),nullif(btrim(concat_ws(' ',c.nome,c.cognome)),''),'Senza nome')) INTO x
 FROM temacase_test.crm_contatti c WHERE c.id=r AND NOT c.archiviato AND (c.consulente_telegram_id=u OR (c.visibilita='agenzia' AND c.agenzia_id=(p->>'agenzia')::uuid));
 END IF;RETURN x;END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm35_rubrica(i bigint,t text,q text DEFAULT '',pagina integer DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm32_utente();p jsonb;r jsonb;BEGIN
 p:=temacase_test.crm32_immobile(i);IF p IS NULL OR t NOT IN('custode','proprietario') OR pagina NOT BETWEEN 0 AND 10000 THEN RETURN NULL;END IF;
 IF t='custode' THEN
 SELECT coalesce(jsonb_agg(to_jsonb(z)),'[]') INTO r FROM (SELECT c.id::text,btrim(concat_ws(' ',c.nome,c.cognome)) AS nome,c.telefono FROM temacase_test.custodi c WHERE c.consulente_telegram_id=u AND strpos(lower(concat_ws(' ',c.nome,c.cognome,c.telefono,c.email)),lower(left(coalesce(q,''),120)))>0 ORDER BY c.nome,c.id LIMIT 9 OFFSET pagina*8)z;
 ELSE
 SELECT coalesce(jsonb_agg(to_jsonb(z)),'[]') INTO r FROM (SELECT c.id::text,coalesce(nullif(c.ragione_sociale,''),nullif(btrim(concat_ws(' ',c.nome,c.cognome)),''),'Senza nome') AS nome,c.telefono FROM temacase_test.crm_contatti c WHERE NOT c.archiviato AND (c.consulente_telegram_id=u OR (c.visibilita='agenzia' AND c.agenzia_id=(p->>'agenzia')::uuid)) AND strpos(lower(concat_ws(' ',c.nome,c.cognome,c.ragione_sociale,c.telefono,c.email)),lower(left(coalesce(q,''),120)))>0 ORDER BY c.nome,c.id LIMIT 9 OFFSET pagina*8)z;
 END IF;RETURN r;END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm35_elenco(i bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm32_utente();p jsonb;r jsonb;BEGIN
 p:=temacase_test.crm32_immobile(i);IF p IS NULL THEN RETURN NULL;END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(z)),'[]') INTO r FROM (
 SELECT a.id::text,a.tipo,coalesce(a.contatto_id,a.custode_id)::text AS persona_id,x.dati->>'nome_visualizzato' AS nome,x.dati->>'telefono' AS telefono
 FROM temacase_test.crm_immobili_referenti a
 CROSS JOIN LATERAL (SELECT temacase_test.crm35_persona(i,a.tipo,coalesce(a.contatto_id,a.custode_id)) AS dati)x
 WHERE a.immobile_id=i AND a.consulente_telegram_id=u AND x.dati IS NOT NULL ORDER BY a.tipo,a.collegato_il,a.id)z;
 RETURN r;END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm35_salva(k uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm32_utente();s jsonb;v jsonb;p jsonb;r jsonb;i bigint;pid bigint;t text;BEGIN
 SELECT stato INTO s FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k AND scade_il>now() AND stato->>'fase'='g35' FOR UPDATE;
 v:=s->'valori';IF v IS NULL OR v->>'step'<>'conferma' THEN RETURN NULL;END IF;
 i:=(v->>'immobile')::bigint;t:=v->>'tipo';p:=temacase_test.crm32_immobile(i);
 IF p IS NULL OR t NOT IN('proprietario','custode') THEN RAISE EXCEPTION 'Immobile o ruolo non disponibile';END IF;
 IF v->>'azione'='scollega' THEN
 DELETE FROM temacase_test.crm_immobili_referenti WHERE id=(v->>'collegamento')::uuid AND consulente_telegram_id=u AND immobile_id=i AND tipo=t RETURNING jsonb_build_object('immobile',i::text,'tipo',t) INTO r;
 IF r IS NULL THEN RAISE EXCEPTION 'Collegamento cambiato';END IF;
 ELSIF v->>'azione' IN('collega','nuovo') THEN
 IF v->>'azione'='nuovo' THEN
 IF length(btrim(concat_ws(' ',v->>'nome',v->>'cognome'))) NOT BETWEEN 2 AND 200 OR length(coalesce(v->>'telefono',''))>80 OR length(coalesce(v->>'email',''))>254 THEN RAISE EXCEPTION 'Dati non validi';END IF;
 IF t='custode' THEN
 INSERT INTO temacase_test.custodi(consulente_telegram_id,nome,cognome,telefono,email,altri_recapiti,nazionalita) VALUES(u,v->>'nome',v->>'cognome',v->>'telefono',v->>'email',left(v->>'altri_recapiti',1000),left(v->>'nazionalita',100)) RETURNING id INTO pid;
 ELSE
 INSERT INTO temacase_test.crm_contatti(agenzia_id,consulente_telegram_id,tipo_soggetto,nome,cognome,telefono,email,altri_recapiti,visibilita)
 VALUES((p->>'agenzia')::uuid,u,'persona',v->>'nome',v->>'cognome',v->>'telefono',v->>'email',left(v->>'altri_recapiti',1000),'privato') RETURNING id INTO pid;
 END IF;
 ELSE
 pid:=(v->>'persona')::bigint;
 r:=temacase_test.crm35_persona(i,t,pid);
 IF r IS NULL OR r IS DISTINCT FROM v->'atteso' THEN RAISE EXCEPTION 'Contatto cambiato o non disponibile';END IF;
 END IF;
 INSERT INTO temacase_test.crm_immobili_referenti(consulente_telegram_id,immobile_id,tipo,contatto_id,custode_id)
 VALUES(u,i,t,CASE WHEN t='proprietario' THEN pid END,CASE WHEN t='custode' THEN pid END) ON CONFLICT DO NOTHING;
 r:=jsonb_build_object('immobile',i::text,'tipo',t,'persona',pid::text);
 ELSE RAISE EXCEPTION 'Operazione non valida';END IF;
 DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k;
 RETURN r;END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm35_immobili(t text,pid bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm32_utente();r jsonb;BEGIN
 SELECT coalesce(jsonb_agg(to_jsonb(z)),'[]') INTO r FROM (
 SELECT a.immobile_id::text AS id,x.p->>'indirizzo' AS indirizzo,x.p->>'comune' AS comune
 FROM temacase_test.crm_immobili_referenti a
 CROSS JOIN LATERAL (SELECT temacase_test.crm32_immobile(a.immobile_id) AS p)x
 WHERE a.consulente_telegram_id=u AND a.tipo=t AND coalesce(a.contatto_id,a.custode_id)=pid AND x.p IS NOT NULL ORDER BY a.collegato_il DESC LIMIT 30)z;
 RETURN r;END $$;
REVOKE ALL ON FUNCTION temacase_test.crm35_immobili(text,bigint) FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT EXECUTE ON FUNCTION temacase_test.crm35_immobili(text,bigint) TO temacase_mcp_login;
CREATE OR REPLACE FUNCTION temacase_test.crm35_immobile_collegamento(k uuid) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm32_utente();i bigint;BEGIN
 SELECT immobile_id INTO i FROM temacase_test.crm_immobili_referenti WHERE id=k AND consulente_telegram_id=u;
 IF i IS NULL OR temacase_test.crm32_immobile(i) IS NULL THEN RETURN NULL;END IF;RETURN i::text;END $$;
REVOKE ALL ON FUNCTION temacase_test.crm35_immobile_collegamento(uuid) FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT EXECUTE ON FUNCTION temacase_test.crm35_immobile_collegamento(uuid) TO temacase_mcp_login;
REVOKE ALL ON FUNCTION temacase_test.crm35_persona(bigint,text,bigint),temacase_test.crm35_rubrica(bigint,text,text,integer),temacase_test.crm35_elenco(bigint),temacase_test.crm35_salva(uuid) FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT EXECUTE ON FUNCTION temacase_test.crm35_persona(bigint,text,bigint),temacase_test.crm35_rubrica(bigint,text,text,integer),temacase_test.crm35_elenco(bigint),temacase_test.crm35_salva(uuid) TO temacase_mcp_login;
COMMIT;
