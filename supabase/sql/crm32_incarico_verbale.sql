-- Tipo di incarico sulla scheda immobile. Il codice CRM-uuid resta interno e non e il titolo.
ALTER TABLE temacase_test.immobili
  ADD COLUMN IF NOT EXISTS tipo_incarico text
  CHECK (tipo_incarico IS NULL OR tipo_incarico IN ('verbale','scritto'));

CREATE OR REPLACE FUNCTION temacase_test.crm32_immobile_salva(k uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, temacase_test
AS $function$
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
  IF nullif(v->>'tipo_incarico','') IS NOT NULL AND v->>'tipo_incarico' NOT IN ('verbale','scritto') THEN RAISE EXCEPTION 'Tipo incarico non valido';END IF;
  IF length(coalesce(v->>'tipologia_immobile','')) NOT BETWEEN 1 AND 100 OR length(coalesce(v->>'unita',''))>150
   OR coalesce(v->>'operazione_immobile','') NOT IN('da_definire','vendita','locazione','entrambe')
   OR coalesce(v->>'fase_acquisizione','') NOT IN('da_definire','da_valutare','notizia_in_lavorazione','contatto_avviato','sopralluogo','trattativa_incarico','incarico_acquisito','non_acquisito')
   OR coalesce(v->>'stato_commerciale','') NOT IN('da_definire','non_sul_mercato','in_preparazione','disponibile','in_trattativa','venduto','locato','sospeso') THEN RAISE EXCEPTION 'Classificazione non valida';END IF;
  IF v->>'modo'='nuovo' THEN
   IF v->>'notizia' IS NULL THEN ind:=v->>'indirizzo';citta:=v->>'comune';ELSE ind:=concat(n.via,' ',n.civico);citta:=n.comune;END IF;
   IF v->>'notizia' IS NULL AND (length(btrim(coalesce(v->>'indirizzo',''))) NOT BETWEEN 3 AND 250 OR length(btrim(coalesce(v->>'comune',''))) NOT BETWEEN 2 AND 100) THEN RAISE EXCEPTION 'Indirizzo e comune obbligatori';END IF;
   IF coalesce(v->>'duplicati_verificati','false')<>'true' THEN RAISE EXCEPTION 'Verificare prima le unita gia presenti';END IF;
   INSERT INTO temacase_test.immobili(codice,indirizzo,comune,tipologia,operazione,fase_acquisizione,stato_commerciale,riferimento_unita,incarico_dal,incarico_al,esclusiva,tipo_incarico)
   VALUES('CRM-'||gen_random_uuid()::text,ind,citta,v->>'tipologia_immobile',v->>'operazione_immobile',v->>'fase_acquisizione',v->>'stato_commerciale',nullif(v->>'unita',''),nullif(v->>'incarico_dal','')::date,nullif(v->>'incarico_al','')::date,(v->>'esclusiva')::boolean,nullif(v->>'tipo_incarico','')) RETURNING id INTO iid;
   INSERT INTO temacase_test.crm_immobili_agenzia(agenzia_id,immobile_id,visibilita,consulente_telegram_id) VALUES(a,iid,vis,u)
   ON CONFLICT(immobile_id) DO UPDATE SET agenzia_id=excluded.agenzia_id,visibilita=excluded.visibilita,consulente_telegram_id=excluded.consulente_telegram_id;
  ELSE
   IF length(btrim(coalesce(v->>'indirizzo',''))) NOT BETWEEN 3 AND 250 OR length(btrim(coalesce(v->>'comune',''))) NOT BETWEEN 2 AND 100 THEN RAISE EXCEPTION 'Indirizzo e comune obbligatori';END IF;
   iid:=(v->>'immobile')::bigint;
   PERFORM 1 FROM temacase_test.immobili WHERE id=iid FOR UPDATE;
   r:=temacase_test.crm32_immobile(iid);
   IF r IS NULL
    OR r->>'id' IS DISTINCT FROM (v #>> '{atteso_immobile,id}')
    OR r->>'agenzia' IS DISTINCT FROM (v #>> '{atteso_immobile,agenzia}')
    OR r->>'codice' IS DISTINCT FROM (v #>> '{atteso_immobile,codice}')
    OR r->>'agenzia'<>a::text THEN RAISE EXCEPTION 'Immobile cambiato o non disponibile';END IF;
   IF vis='privato' AND coalesce(r->>'visibilita','')='agenzia' AND (
     r->>'responsabile' IS DISTINCT FROM u::text
     OR EXISTS(SELECT 1 FROM temacase_test.visite WHERE immobile_id=iid)
     OR EXISTS(SELECT 1 FROM temacase_test.crm_attivita_operative WHERE immobile_id=iid)
     OR EXISTS(SELECT 1 FROM temacase_test.crm_immobili_contatti WHERE immobile_id=iid)
   ) THEN RAISE EXCEPTION 'Immobile operativo: deve restare condiviso';END IF;
   UPDATE temacase_test.immobili SET
    indirizzo=btrim(v->>'indirizzo'),
    comune=btrim(v->>'comune'),
    tipologia=v->>'tipologia_immobile',
    operazione=v->>'operazione_immobile',
    fase_acquisizione=v->>'fase_acquisizione',
    stato_commerciale=v->>'stato_commerciale',
    riferimento_unita=nullif(v->>'unita',''),
    incarico_dal=nullif(v->>'incarico_dal','')::date,
    incarico_al=nullif(v->>'incarico_al','')::date,
    esclusiva=(v->>'esclusiva')::boolean,
    tipo_incarico=nullif(v->>'tipo_incarico','')
   WHERE id=iid;
   UPDATE temacase_test.crm_immobili_agenzia SET visibilita=vis WHERE immobile_id=iid;
  END IF;
 END IF;
 IF v->>'notizia' IS NOT NULL THEN
  INSERT INTO temacase_test.crm_notizie_immobili(notizia_id,immobile_id,consulente_telegram_id) VALUES((v->>'notizia')::bigint,iid,u) ON CONFLICT DO NOTHING;
 END IF;
 DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k;
 RETURN jsonb_build_object('immobile',iid::text,'notizia',v->>'notizia');END
$function$;
