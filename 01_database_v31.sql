BEGIN;
SET LOCAL lock_timeout='5s';
CREATE TABLE IF NOT EXISTS temacase_test.crm_ai_conversazioni(
 consulente_telegram_id bigint PRIMARY KEY,
 storia jsonb NOT NULL DEFAULT '[]',pulsanti jsonb NOT NULL DEFAULT '[]',
 ultimo_turno uuid,diagnostica jsonb NOT NULL DEFAULT '{}',aggiornato_il timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE temacase_test.crm_ai_conversazioni ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_ai_conversazioni FORCE ROW LEVEL SECURITY;
REVOKE ALL ON temacase_test.crm_ai_conversazioni FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT SELECT ON temacase_test.crm_ai_conversazioni TO temacase_mcp_login;
DROP POLICY IF EXISTS conversazione_propria ON temacase_test.crm_ai_conversazioni;
CREATE POLICY conversazione_propria ON temacase_test.crm_ai_conversazioni FOR SELECT TO temacase_mcp_login USING(
 consulente_telegram_id=nullif(current_setting('temacase.telegram_user_id',true),'')::bigint);
CREATE OR REPLACE FUNCTION temacase_test.crm31_traccia(ruolo text,t text,b jsonb DEFAULT '[]',d jsonb DEFAULT '{}')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=nullif(current_setting('temacase.telegram_user_id',true),'')::bigint;k uuid:=gen_random_uuid();
BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM temacase_test.consulenti_telegram WHERE telegram_user_id=u AND attivo) THEN RAISE EXCEPTION 'Accesso negato'; END IF;
 IF ruolo NOT IN('user','assistant','diagnostica') OR jsonb_typeof(b)<>'array' OR jsonb_typeof(d)<>'object' THEN RAISE EXCEPTION 'Traccia non valida'; END IF;
 INSERT INTO temacase_test.crm_ai_conversazioni(consulente_telegram_id) VALUES(u) ON CONFLICT DO NOTHING;
 UPDATE temacase_test.crm_ai_conversazioni SET
 storia=CASE WHEN ruolo='diagnostica' THEN storia ELSE (
 SELECT coalesce(jsonb_agg(x ORDER BY n),'[]'::jsonb) FROM jsonb_array_elements(
 CASE WHEN aggiornato_il<now()-interval '30 minutes' THEN '[]'::jsonb ELSE storia END
 ||jsonb_build_array(jsonb_build_object('role',ruolo,'content',left(coalesce(t,''),4000)))) WITH ORDINALITY a(x,n)
 WHERE n>jsonb_array_length(CASE WHEN aggiornato_il<now()-interval '30 minutes' THEN '[]'::jsonb ELSE storia END)-10
 ) END,
 pulsanti=CASE WHEN ruolo='assistant' THEN b ELSE pulsanti END,
 diagnostica=CASE WHEN d='{}'::jsonb THEN diagnostica ELSE d END,
 ultimo_turno=CASE WHEN ruolo='user' THEN k ELSE ultimo_turno END,
 aggiornato_il=now() WHERE consulente_telegram_id=u;
 RETURN CASE WHEN ruolo='user' THEN k ELSE (SELECT ultimo_turno FROM temacase_test.crm_ai_conversazioni WHERE consulente_telegram_id=u) END;
END $$;
CREATE TABLE IF NOT EXISTS temacase_test.crm_attivita_personali(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 agenzia_id uuid NOT NULL,consulente_telegram_id bigint NOT NULL,
 tipo text NOT NULL CHECK(tipo IN('tasks','calendario')),
 descrizione text NOT NULL CHECK(length(btrim(descrizione)) BETWEEN 1 AND 300),
 scadenza_data date,scadenza_ora time,
 stato text NOT NULL DEFAULT 'aperto' CHECK(stato IN('aperto','completato','annullato')),
 creato_il timestamptz NOT NULL DEFAULT now(),
 google_titolo text,google_note text,google_fine timestamptz,
 google_giornata_intera boolean NOT NULL DEFAULT false,
 google_senza_scadenza boolean NOT NULL DEFAULT false,
 FOREIGN KEY(agenzia_id,consulente_telegram_id) REFERENCES temacase_test.crm_membri_agenzia(agenzia_id,consulente_telegram_id)
);
ALTER TABLE temacase_test.crm_attivita_personali ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_attivita_personali FORCE ROW LEVEL SECURITY;
REVOKE ALL ON temacase_test.crm_attivita_personali FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT SELECT ON temacase_test.crm_attivita_personali TO temacase_mcp_login;
DROP POLICY IF EXISTS attivita_personale_propria ON temacase_test.crm_attivita_personali;
CREATE POLICY attivita_personale_propria ON temacase_test.crm_attivita_personali FOR SELECT TO temacase_mcp_login USING(
 consulente_telegram_id=nullif(current_setting('temacase.telegram_user_id',true),'')::bigint
 AND EXISTS(SELECT 1 FROM temacase_test.crm_membri_agenzia m WHERE m.agenzia_id=crm_attivita_personali.agenzia_id
 AND m.consulente_telegram_id=crm_attivita_personali.consulente_telegram_id AND m.attivo));
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname FROM pg_constraint
 WHERE conrelid='temacase_test.crm_google_invii'::regclass AND contype='c'
 AND conkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='temacase_test.crm_google_invii'::regclass AND attname='fonte')]
 LOOP EXECUTE format('ALTER TABLE temacase_test.crm_google_invii DROP CONSTRAINT %I',c.conname); END LOOP;
END $$;
ALTER TABLE temacase_test.crm_google_invii ADD CONSTRAINT crm31_fonte_check CHECK(fonte IN('visita','followup','test','notizia','personale'));
CREATE OR REPLACE FUNCTION temacase_test.crm31_personale_salva(k uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm_google_v2_utente();s jsonb;v jsonb;
 d temacase_test.crm_google_destinazioni%ROWTYPE;a uuid;f bigint;p jsonb;op uuid;locale timestamp;istante timestamptz;durata integer;
BEGIN
 SELECT stato INTO s FROM temacase_test.crm_sessioni_telegram
 WHERE consulente_telegram_id=u AND chiave=k AND scade_il>now() AND stato->>'fase'='ai31_personale' FOR UPDATE;
 v:=s->'valori';IF v->>'step' IS DISTINCT FROM 'conferma' THEN RETURN jsonb_build_object('messaggio','Operazione scaduta o gia gestita.'); END IF;
 IF length(btrim(coalesce(v->>'descrizione',''))) NOT BETWEEN 1 AND 300
 OR coalesce(v->>'data','')!~'^\d{4}-\d{2}-\d{2}$'
 OR (v->>'ora' IS NOT NULL AND v->>'ora'!~'^([01][0-9]|2[0-3]):[0-5][0-9]$')
 OR coalesce(v->>'google_mode','') NOT IN('crm','google') THEN RAISE EXCEPTION 'Dati non validi'; END IF;
 IF v->>'google_mode'='google' THEN
 SELECT x.* INTO d FROM temacase_test.crm_google_destinazioni x
 JOIN temacase_test.crm_google_account c ON c.id=x.connessione_id AND c.stato='attivo'
 WHERE x.id=(v->>'google_destinazione')::uuid AND x.consulente_telegram_id=u AND x.attiva;
 IF NOT FOUND THEN RAISE EXCEPTION 'Destinazione non disponibile'; END IF;a:=d.agenzia_id;
 ELSE a:=(v->>'agenzia')::uuid; END IF;
 PERFORM temacase_test.crm_google_v2_utente(a);
 IF a IS NULL THEN RAISE EXCEPTION 'Scegliere una agenzia'; END IF;
 IF coalesce(d.tipo,v->>'google_tipo')='calendario' AND v->>'ora' IS NULL THEN RAISE EXCEPTION 'Indicare orario evento'; END IF;
 durata:=coalesce((v->>'durata_minuti')::integer,30);IF durata NOT BETWEEN 1 AND 480 THEN RAISE EXCEPTION 'Durata non valida'; END IF;
 locale:=((v->>'data')||' '||coalesce(v->>'ora','00:00'))::timestamp;istante:=locale AT TIME ZONE 'Europe/Rome';
 IF coalesce(d.tipo,v->>'google_tipo')='calendario' AND (istante AT TIME ZONE 'Europe/Rome'<>locale OR (istante+interval '1 hour') AT TIME ZONE 'Europe/Rome'=locale OR (istante-interval '1 hour') AT TIME ZONE 'Europe/Rome'=locale) THEN RAISE EXCEPTION 'Orario ambiguo o inesistente'; END IF;
 INSERT INTO temacase_test.crm_attivita_personali(agenzia_id,consulente_telegram_id,tipo,descrizione,scadenza_data,scadenza_ora)
 VALUES(a,u,coalesce(d.tipo,v->>'google_tipo','tasks'),v->>'descrizione',(v->>'data')::date,(v->>'ora')::time) RETURNING id INTO f;
 IF v->>'google_mode'='google' THEN
 IF d.tipo='tasks' THEN p:=jsonb_build_object('title',v->>'descrizione','notes','Attivita personale CRM','due',(v->>'data')||'T00:00:00.000Z');
 ELSE p:=jsonb_build_object('summary',v->>'descrizione','description','Attivita personale CRM',
 'start',jsonb_build_object('dateTime',to_char(istante AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'timeZone','Europe/Rome'),
 'end',jsonb_build_object('dateTime',to_char((istante+make_interval(mins=>durata)) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'timeZone','Europe/Rome')); END IF;
 INSERT INTO temacase_test.crm_google_invii(agenzia_id,consulente_telegram_id,destinazione,fonte,fonte_id,payload)
 VALUES(a,u,d.id,'personale',f,p) RETURNING id INTO op;END IF;
 DELETE FROM temacase_test.crm_sessioni_telegram WHERE consulente_telegram_id=u AND chiave=k;
 RETURN jsonb_build_object('messaggio','Attivita personale registrata.','id',f::text,'google_operazione',op);
END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm27_locale(k uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE o temacase_test.crm_google_invii%ROWTYPE; r jsonb;
BEGIN
 SELECT * INTO o FROM temacase_test.crm_google_invii WHERE id=k;
 IF o.fonte='followup' THEN
  SELECT to_jsonb(a)-ARRAY['creato_il'] INTO r
  FROM temacase_test.crm_attivita_operative a WHERE a.id=o.fonte_id
  AND a.agenzia_id=o.agenzia_id AND a.tipo='followup';
 ELSIF o.fonte='personale' THEN
  SELECT to_jsonb(p) INTO r FROM temacase_test.crm_attivita_personali p
  WHERE p.id=o.fonte_id AND p.consulente_telegram_id=o.consulente_telegram_id;
 ELSIF o.fonte='notizia' THEN
  SELECT to_jsonb(f) INTO r FROM temacase_test.followup_acquisizione f
  JOIN temacase_test.notizie_acquisizione n ON n.id=f.notizia_id
  WHERE f.id=o.fonte_id AND n.consulente_telegram_id=o.consulente_telegram_id;
 ELSIF o.fonte='visita' THEN
  SELECT to_jsonb(v) INTO r FROM temacase_test.visite v
  JOIN temacase_test.crm_immobili_agenzia i ON i.immobile_id=v.immobile_id
  WHERE v.id=o.fonte_id AND i.agenzia_id=o.agenzia_id;
 END IF;
 RETURN r;
END $$;
CREATE OR REPLACE FUNCTION temacase_test.crm27_applica(k uuid,l uuid,p jsonb) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,temacase_test AS $$
DECLARE u bigint:=temacase_test.crm_google_v2_utente();
 o temacase_test.crm_google_invii%ROWTYPE; x temacase_test.crm_google_ritorni%ROWTYPE;
 corrente jsonb; nuovo jsonb; eliminato boolean; istante_google timestamptz; fine timestamptz;
 giorno boolean:=false; stato_nuovo text; vecchia_ora time;
BEGIN
 SELECT * INTO o FROM temacase_test.crm_google_invii
 WHERE id=k AND consulente_telegram_id=u FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invio non disponibile'; END IF;
 PERFORM temacase_test.crm_google_v2_utente(o.agenzia_id);
 SELECT * INTO x FROM temacase_test.crm_google_ritorni WHERE invio=k FOR UPDATE;
 IF x.lease IS DISTINCT FROM l OR x.lease IS NULL THEN RETURN 'superato'; END IF;
 IF p ? 'errore' THEN
  UPDATE temacase_test.crm_google_ritorni SET errore=left(p->>'errore',100),lease=NULL,preso_il=NULL WHERE invio=k;
  RETURN 'errore';
 END IF;
 eliminato:=coalesce((p->>'deleted')::boolean,false) OR coalesce(p->>'status','')='cancelled';
 IF p->>'mancante'='true' THEN
  IF x.assente_il IS NULL OR x.assente_il>now()-interval '45 seconds' THEN
   UPDATE temacase_test.crm_google_ritorni SET assente_il=coalesce(assente_il,now()),errore='assenza_da_confermare',lease=NULL,preso_il=NULL WHERE invio=k;
   RETURN 'da_confermare';
  END IF;
  eliminato:=true;
 END IF;
 IF NOT eliminato AND coalesce(p->>'id','')<>o.google_id THEN RAISE EXCEPTION 'ID diverso'; END IF;
 nuovo:=CASE WHEN eliminato THEN jsonb_build_object('deleted',true) ELSE
 jsonb_build_object('title',coalesce(p->>'summary',p->>'title',''),
 'notes',coalesce(p->>'description',p->>'notes',''),
 'start',p->'start','end',p->'end','due',p->>'due',
 'status',coalesce(p->>'status',''),'deleted',false) END;
 IF o.fonte='personale' THEN
  PERFORM 1 FROM temacase_test.crm_attivita_personali WHERE id=o.fonte_id AND consulente_telegram_id=u FOR UPDATE;
 ELSIF o.fonte='notizia' THEN
  PERFORM 1 FROM temacase_test.followup_acquisizione f
  JOIN temacase_test.notizie_acquisizione n ON n.id=f.notizia_id
  WHERE f.id=o.fonte_id AND n.consulente_telegram_id=u FOR UPDATE OF f;
 ELSIF o.fonte='followup' THEN
  PERFORM 1 FROM temacase_test.crm_attivita_operative WHERE id=o.fonte_id FOR UPDATE;
 ELSE PERFORM 1 FROM temacase_test.visite WHERE id=o.fonte_id FOR UPDATE; END IF;
 corrente:=temacase_test.crm27_locale(k);
 IF corrente IS NULL THEN
  UPDATE temacase_test.crm_google_ritorni SET errore='attivita_crm_assente',lease=NULL,preso_il=NULL WHERE invio=k;
  RETURN 'errore';
 END IF;
 IF x.remoto IS NOT DISTINCT FROM nuovo THEN
  UPDATE temacase_test.crm_google_ritorni SET errore=NULL,assente_il=NULL,lease=NULL,preso_il=NULL WHERE invio=k;
  RETURN 'invariato';
 END IF;
 IF x.locale IS DISTINCT FROM corrente THEN
  UPDATE temacase_test.crm_google_ritorni SET remoto=nuovo,conflitto=true,errore='modifiche_anche_nel_crm',lease=NULL,preso_il=NULL WHERE invio=k;
  RETURN 'conflitto';
 END IF;
 IF NOT eliminato THEN
  IF p->'start'->>'dateTime' IS NOT NULL THEN
   istante_google:=(p->'start'->>'dateTime')::timestamptz;
   fine:=(p->'end'->>'dateTime')::timestamptz;
  ELSIF p->'start'->>'date' IS NOT NULL THEN
   istante_google:=(p->'start'->>'date')::date::timestamp AT TIME ZONE 'Europe/Rome';
   fine:=(p->'end'->>'date')::date::timestamp AT TIME ZONE 'Europe/Rome';giorno:=true;
  ELSIF p->>'due' IS NOT NULL THEN
   vecchia_ora:=CASE WHEN o.fonte IN('notizia','personale') THEN coalesce((corrente->>'scadenza_ora')::time,'00:00'::time) ELSE ((corrente->>'quando')::timestamptz AT TIME ZONE 'Europe/Rome')::time END;
   istante_google:=((left(p->>'due',10)::date+vecchia_ora) AT TIME ZONE 'Europe/Rome');
  END IF;
 END IF;
 IF o.fonte='personale' THEN
  UPDATE temacase_test.crm_attivita_personali SET
   stato=CASE WHEN eliminato THEN 'annullato' WHEN p->>'status'='completed' THEN 'completato'
    WHEN p->>'status'='needsAction' THEN 'aperto' WHEN stato='annullato' THEN 'aperto' ELSE stato END,
   scadenza_data=CASE WHEN eliminato THEN scadenza_data
    WHEN p->>'status' IN('completed','needsAction') AND p->>'due' IS NULL THEN NULL
    ELSE coalesce((istante_google AT TIME ZONE 'Europe/Rome')::date,scadenza_data) END,
   scadenza_ora=CASE WHEN eliminato THEN scadenza_ora
    WHEN giorno OR (p->>'status' IN('completed','needsAction') AND p->>'due' IS NULL) THEN NULL
    WHEN p->'start' IS NOT NULL THEN (istante_google AT TIME ZONE 'Europe/Rome')::time ELSE scadenza_ora END,
   google_titolo=CASE WHEN eliminato THEN google_titolo ELSE nuovo->>'title' END,
   google_note=CASE WHEN eliminato THEN google_note ELSE nuovo->>'notes' END,
   google_fine=CASE WHEN eliminato THEN google_fine ELSE fine END,
   google_giornata_intera=CASE WHEN eliminato THEN google_giornata_intera ELSE giorno END,
   google_senza_scadenza=CASE WHEN eliminato THEN google_senza_scadenza ELSE p->>'status' IN('completed','needsAction') AND p->>'due' IS NULL END
  WHERE id=o.fonte_id AND consulente_telegram_id=u;
 ELSIF o.fonte='notizia' THEN
  UPDATE temacase_test.followup_acquisizione SET
   stato=CASE WHEN eliminato THEN 'annullato' WHEN p->>'status'='completed' THEN 'completato'
    WHEN p->>'status'='needsAction' THEN 'aperto' WHEN stato='annullato' THEN 'aperto' ELSE stato END,
   scadenza_data=CASE WHEN eliminato THEN scadenza_data
    WHEN p->>'status' IN('completed','needsAction') AND p->>'due' IS NULL THEN NULL
    ELSE coalesce((istante_google AT TIME ZONE 'Europe/Rome')::date,scadenza_data) END,
   scadenza_ora=CASE WHEN eliminato THEN scadenza_ora
    WHEN giorno OR (p->>'status' IN('completed','needsAction') AND p->>'due' IS NULL) THEN NULL
    WHEN p->'start' IS NOT NULL THEN (istante_google AT TIME ZONE 'Europe/Rome')::time ELSE scadenza_ora END,
   google_titolo=CASE WHEN eliminato THEN google_titolo ELSE nuovo->>'title' END,
   google_note=CASE WHEN eliminato THEN google_note ELSE nuovo->>'notes' END,
   google_fine=CASE WHEN eliminato THEN google_fine ELSE fine END,
   google_giornata_intera=CASE WHEN eliminato THEN google_giornata_intera ELSE giorno END,
   google_senza_scadenza=CASE WHEN eliminato THEN google_senza_scadenza ELSE p->>'status' IN('completed','needsAction') AND p->>'due' IS NULL END
  WHERE id=o.fonte_id;
 ELSIF o.fonte='followup' THEN
  stato_nuovo:=CASE WHEN eliminato THEN 'annullato' WHEN p->>'status'='completed' THEN 'concluso'
   WHEN p->>'status'='needsAction' THEN 'aperto'
   WHEN corrente->>'stato'='annullato' THEN 'aperto' ELSE corrente->>'stato' END;
  UPDATE temacase_test.crm_attivita_operative SET stato=stato_nuovo,
   quando=coalesce(istante_google,crm_attivita_operative.quando),
   google_titolo=CASE WHEN eliminato THEN google_titolo ELSE nuovo->>'title' END,
   google_note=CASE WHEN eliminato THEN google_note ELSE nuovo->>'notes' END,
   google_fine=CASE WHEN eliminato THEN google_fine ELSE fine END,
   google_giornata_intera=CASE WHEN eliminato THEN google_giornata_intera ELSE giorno END,
   google_senza_scadenza=CASE WHEN eliminato THEN google_senza_scadenza ELSE p->>'status' IN('completed','needsAction') AND p->>'due' IS NULL END
  WHERE id=o.fonte_id AND agenzia_id=o.agenzia_id AND tipo='followup';
 ELSE
  UPDATE temacase_test.visite SET
   stato=CASE WHEN eliminato THEN 'annullata' WHEN stato='annullata' THEN 'programmata' ELSE stato END,
   data_visita=coalesce(istante_google,data_visita),
   google_titolo=CASE WHEN eliminato THEN google_titolo ELSE nuovo->>'title' END,
   google_note=CASE WHEN eliminato THEN google_note ELSE nuovo->>'notes' END,
   google_fine=CASE WHEN eliminato THEN google_fine ELSE fine END,
   google_giornata_intera=CASE WHEN eliminato THEN google_giornata_intera ELSE giorno END
  WHERE id=o.fonte_id;
 END IF;
 UPDATE temacase_test.crm_google_ritorni SET remoto=nuovo,locale=temacase_test.crm27_locale(k),
  applicato_il=now(),errore=NULL,assente_il=NULL,lease=NULL,preso_il=NULL WHERE invio=k;
 RETURN CASE WHEN eliminato THEN 'annullato' ELSE 'aggiornato' END;
END $$;


REVOKE ALL ON FUNCTION temacase_test.crm31_traccia(text,text,jsonb,jsonb),temacase_test.crm31_personale_salva(uuid)
 FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
GRANT EXECUTE ON FUNCTION temacase_test.crm31_traccia(text,text,jsonb,jsonb),temacase_test.crm31_personale_salva(uuid) TO temacase_mcp_login;
REVOKE ALL ON FUNCTION temacase_test.crm27_locale(uuid) FROM PUBLIC,anon,authenticated,temacase_mcp,temacase_mcp_login;
COMMIT;
