BEGIN;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION temacase_test.crm37_campi(j jsonb) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE r text:='';k text;v text;label text;BEGIN
 FOREACH k IN ARRAY ARRAY['titolo','descrizione','testo','stato_notizia','stato','data_segnalazione','fonte','codice','indirizzo','via','civico','comune','scala','piano','tipologia_immobile','tipologia','numero_locali','locali','superficie','prezzo','operazione','fase_acquisizione','stato_commerciale','riferimento_unita','incarico_dal','incarico_al','esclusiva','proprietario_contattato','incarico_in_essere','agenzia_incaricata','scadenza_incarico','venditore_nome','venditore_cognome','venditore_telefono','venditore_email','tipo_soggetto','ragione_sociale','nome','cognome','telefono','email','altri_recapiti','nazionalita','ruolo','data_visita','quando','scadenza_data','scadenza_ora','esito','importo','note'] LOOP
  v:=j->>k;IF v IS NULL OR btrim(v)='' THEN CONTINUE;END IF;
  IF jsonb_typeof(j->k)='boolean' THEN v:=CASE WHEN (j->>k)::boolean THEN 'Si' ELSE 'No' END;END IF;
  label:=CASE k WHEN 'testo' THEN 'Segnalazione' WHEN 'scadenza_data' THEN 'Data attivita' WHEN 'scadenza_ora' THEN 'Ora attivita (Europe/Rome)' WHEN 'quando' THEN 'Data e ora attivita' ELSE initcap(replace(k,'_',' ')) END;
  r:=r||label||': '||v||E'\n';
 END LOOP;RETURN r;END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm37_testo(k uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm32_utente();o temacase_test.crm_google_invii%ROWTYPE;a jsonb;n jsonb;p jsonb;c jsonb;x record;
 nid bigint;pid bigint;iid bigint;cid bigint;ids bigint[]:=ARRAY[]::bigint[];r text;link text;BEGIN
 SELECT * INTO o FROM temacase_test.crm_google_invii WHERE id=k AND consulente_telegram_id=u;
 IF NOT FOUND THEN RETURN NULL;END IF;
 PERFORM temacase_test.crm_google_v2_utente(o.agenzia_id);
 IF NOT EXISTS(SELECT 1 FROM temacase_test.crm_google_destinazioni d WHERE d.id=o.destinazione AND d.consulente_telegram_id=u AND d.agenzia_id=o.agenzia_id) THEN RETURN NULL;END IF;
 IF o.fonte='test' THEN RETURN jsonb_build_object('testo',coalesce(o.payload->>'description',o.payload->>'notes',''),'link','');END IF;
 IF o.fonte='notizia' THEN
  SELECT to_jsonb(f),to_jsonb(z) INTO a,n FROM temacase_test.followup_acquisizione f JOIN temacase_test.notizie_acquisizione z ON z.id=f.notizia_id WHERE f.id=o.fonte_id AND z.consulente_telegram_id=u;
  IF a IS NULL THEN RETURN NULL;END IF;nid:=(n->>'id')::bigint;pid:=(n->>'palazzo_id')::bigint;
  link:='https://t.me/temacase_crm_bot?start=notizia_'||nid;
 ELSIF o.fonte='personale' THEN
  SELECT to_jsonb(z) INTO a FROM temacase_test.crm_attivita_personali z WHERE z.id=o.fonte_id AND z.consulente_telegram_id=u AND z.agenzia_id=o.agenzia_id;
  link:='https://t.me/temacase_crm_bot?start=attivita';
 ELSIF o.fonte='followup' THEN
  SELECT to_jsonb(z) INTO a FROM temacase_test.crm_attivita_operative z WHERE z.id=o.fonte_id AND z.agenzia_id=o.agenzia_id;
  iid:=(a->>'immobile_id')::bigint;cid:=(a->>'contatto_id')::bigint;
 ELSIF o.fonte='visita' THEN
  SELECT to_jsonb(z) INTO a FROM temacase_test.visite z JOIN temacase_test.crm_immobili_agenzia ia ON ia.immobile_id=z.immobile_id WHERE z.id=o.fonte_id AND ia.agenzia_id=o.agenzia_id;
  iid:=(a->>'immobile_id')::bigint;
  SELECT cc.contatto_id INTO cid FROM temacase_test.crm_clienti_contatti cc WHERE cc.cliente_id=(a->>'cliente_id')::bigint AND cc.agenzia_id=o.agenzia_id;
 ELSE RETURN NULL;END IF;
 IF a IS NULL THEN RETURN NULL;END IF;
 r:='ATTIVITA CRM'||E'\n'||temacase_test.crm37_campi(a);
 IF n IS NOT NULL THEN
  r:=r||E'\nNOTIZIA #'||nid||E'\n'||temacase_test.crm37_campi(n);
  SELECT to_jsonb(z) INTO p FROM temacase_test.palazzi z WHERE z.id=pid;r:=r||temacase_test.crm37_campi(p);
  FOR x IN SELECT to_jsonb(cp) AS dati FROM temacase_test.contatti_palazzo cp WHERE cp.palazzo_id=pid AND cp.consulente_telegram_id=u LOOP r:=r||E'\nCONTATTO DEL PALAZZO\n'||temacase_test.crm37_campi(x.dati);END LOOP;
  FOR x IN SELECT to_jsonb(cu) AS dati FROM temacase_test.palazzi_custodi pc JOIN temacase_test.custodi cu ON cu.id=pc.custode_id WHERE pc.palazzo_id=pid AND pc.consulente_telegram_id=u AND cu.consulente_telegram_id=u LOOP r:=r||E'\nCUSTODE DEL PALAZZO\n'||temacase_test.crm37_campi(x.dati);END LOOP;
  FOR x IN SELECT to_jsonb(ad) AS dati FROM temacase_test.palazzi_amministratori pa JOIN temacase_test.amministratori ad ON ad.id=pa.amministratore_id WHERE pa.palazzo_id=pid AND pa.consulente_telegram_id=u LOOP r:=r||E'\nAMMINISTRATORE DEL PALAZZO\n'||temacase_test.crm37_campi(x.dati);END LOOP;
  FOR x IN SELECT to_jsonb(z)||jsonb_build_object('ruolo',nc.ruolo) AS dati FROM temacase_test.crm_notizie_contatti nc JOIN temacase_test.crm_contatti z ON z.id=nc.contatto_id WHERE nc.notizia_id=nid AND (z.consulente_telegram_id=u OR (z.visibilita='agenzia' AND z.agenzia_id=o.agenzia_id)) LOOP r:=r||E'\nCONTATTO DELLA NOTIZIA\n'||temacase_test.crm37_campi(x.dati);END LOOP;
  SELECT coalesce(array_agg(immobile_id),ARRAY[]::bigint[]) INTO ids FROM temacase_test.crm_notizie_immobili WHERE notizia_id=nid AND consulente_telegram_id=u;
 END IF;
 IF iid IS NOT NULL THEN ids:=array_append(ids,iid);link:='https://t.me/temacase_crm_bot?start=immobile_'||iid;END IF;
 IF cid IS NOT NULL THEN
  SELECT to_jsonb(z) INTO c FROM temacase_test.crm_contatti z WHERE z.id=cid AND (z.consulente_telegram_id=u OR(z.visibilita='agenzia' AND z.agenzia_id=o.agenzia_id));
  IF c IS NOT NULL THEN r:=r||E'\nCONTATTO DELL’ATTIVITA\n'||temacase_test.crm37_campi(c);END IF;
 END IF;
 FOREACH iid IN ARRAY ids LOOP
  p:=temacase_test.crm32_immobile(iid);IF p IS NULL OR p->>'agenzia'<>o.agenzia_id::text THEN CONTINUE;END IF;
  r:=r||E'\nIMMOBILE #'||iid||E'\n'||temacase_test.crm37_campi(p);
  FOR x IN SELECT cu.value AS dati FROM jsonb_array_elements(temacase_test.crm35_elenco(iid))cu LOOP
   c:=temacase_test.crm35_persona(iid,x.dati->>'tipo',(x.dati->>'persona_id')::bigint);
   IF c IS NOT NULL THEN r:=r||E'\n'||upper(x.dati->>'tipo')||E' DELL’IMMOBILE\n'||temacase_test.crm37_campi(c);END IF;
  END LOOP;
  FOR x IN SELECT to_jsonb(z)||jsonb_build_object('ruolo',ic.ruolo) AS dati FROM temacase_test.crm_immobili_contatti ic JOIN temacase_test.crm_contatti z ON z.id=ic.contatto_id WHERE ic.immobile_id=iid AND ic.agenzia_id=o.agenzia_id AND (z.consulente_telegram_id=u OR (z.visibilita='agenzia' AND z.agenzia_id=o.agenzia_id)) LOOP r:=r||E'\nCONTATTO OPERATIVO DELL’IMMOBILE\n'||temacase_test.crm37_campi(x.dati);END LOOP;
 END LOOP;
 RETURN jsonb_build_object('testo',r,'link',coalesce(link,''));END $$;
REVOKE ALL ON FUNCTION temacase_test.crm37_campi(jsonb),temacase_test.crm37_testo(uuid) FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT EXECUTE ON FUNCTION temacase_test.crm37_testo(uuid) TO temacase_mcp_login;
COMMIT;
