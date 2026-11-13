-- Ripristino v63: sicuro soltanto se non sono stati creati collegamenti.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM temacase_test.crm_personali_notizie) THEN
  RAISE EXCEPTION 'Sono presenti collegamenti Task/Notizia. Rollback interrotto per non perderli.';
 END IF;
END $$;
DO $v63$
DECLARE ddl text;old_fragment text;new_fragment text;
BEGIN
 ddl:=pg_get_functiondef('temacase_test.crm37_testo(uuid)'::regprocedure);
 old_fragment:='link:=''https://t.me/temacase_crm_bot?start=attivita'';';
 new_fragment:=old_fragment||E'\n'||
 $extra$  -- Il Task resta personale nel CRM ma eredita il contesto della Notizia esplicitamente associata.
  SELECT to_jsonb(z),z.id,z.palazzo_id INTO n,nid,pid
  FROM temacase_test.crm_personali_notizie l
  JOIN temacase_test.notizie_acquisizione z ON z.id=l.notizia_id
  WHERE l.personale_id=o.fonte_id AND l.consulente_telegram_id=u AND z.consulente_telegram_id=u;
  IF nid IS NOT NULL THEN link:='https://t.me/temacase_crm_bot?start=notizia_'||nid;END IF;
$extra$;
 IF strpos(ddl,new_fragment)=0 THEN RAISE EXCEPTION 'Definizione Google variata, ripristino bloccato.';END IF;
 EXECUTE replace(ddl,new_fragment,old_fragment);
END $v63$;
DROP TABLE temacase_test.crm_personali_notizie;
COMMIT;
