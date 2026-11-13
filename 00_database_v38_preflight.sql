-- TEMACASE CRM v38 - Diagnostica SOLO LETTURA, prima di modificare Supabase.
SELECT column_name,data_type,column_default,is_nullable
FROM information_schema.columns
WHERE table_schema='temacase_test' AND table_name='notizie_acquisizione'
  AND column_name IN ('data_segnalazione','venditore_nome','venditore_cognome','venditore_telefono','proprietario_contattato','stato_notizia')
ORDER BY column_name;

SELECT c.conname,pg_get_constraintdef(c.oid) AS definizione
FROM pg_constraint c
WHERE c.conrelid='temacase_test.crm_notizie_contatti'::regclass
  AND c.contype='c'
ORDER BY c.conname;

SELECT count(*) AS notizie_con_dati_legacy
FROM temacase_test.notizie_acquisizione n
WHERE coalesce(nullif(btrim(to_jsonb(n)->>'venditore_nome'),''),
               nullif(btrim(to_jsonb(n)->>'venditore_cognome'),''),
               nullif(btrim(to_jsonb(n)->>'venditore_telefono'),'')) IS NOT NULL
   OR to_jsonb(n)->>'proprietario_contattato' IS NOT NULL;