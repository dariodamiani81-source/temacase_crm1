-- Temacase v56: diagnostica di sola lettura. Non esegue alcun INSERT o DELETE.
WITH controlli AS (
 SELECT 'privilegio_tabella'::text AS categoria,'temacase_mcp_login'::text AS nome,
        jsonb_build_object('SELECT',has_table_privilege('temacase_mcp_login','temacase_test.notizie_acquisizione','SELECT'),
          'INSERT',has_table_privilege('temacase_mcp_login','temacase_test.notizie_acquisizione','INSERT'),
          'UPDATE',has_table_privilege('temacase_mcp_login','temacase_test.notizie_acquisizione','UPDATE')) AS dettagli
 UNION ALL
 SELECT 'privilegio_colonna',c.column_name,
        jsonb_build_object('INSERT',has_column_privilege('temacase_mcp_login','temacase_test.notizie_acquisizione',c.column_name,'INSERT'),
                           'SELECT',has_column_privilege('temacase_mcp_login','temacase_test.notizie_acquisizione',c.column_name,'SELECT'))
 FROM information_schema.columns c WHERE c.table_schema='temacase_test' AND c.table_name='notizie_acquisizione'
   AND c.column_name IN ('palazzo_id','consulente_telegram_id','testo','telegram_update_id','titolo','data_segnalazione','fonte','scala','piano','tipologia_immobile','numero_locali','operazione','prezzo_richiesto')
 UNION ALL
 SELECT 'vincolo',con.conname, jsonb_build_object('tipo',con.contype,'definizione',pg_get_constraintdef(con.oid))
 FROM pg_constraint con WHERE con.conrelid='temacase_test.notizie_acquisizione'::regclass
 UNION ALL
 SELECT 'trigger',tg.tgname,jsonb_build_object('definizione',pg_get_triggerdef(tg.oid))
 FROM pg_trigger tg WHERE tg.tgrelid='temacase_test.notizie_acquisizione'::regclass AND NOT tg.tgisinternal
 UNION ALL
 SELECT 'rls','notizie_acquisizione',jsonb_build_object('attiva',c.relrowsecurity,'forzata',c.relforcerowsecurity)
 FROM pg_class c WHERE c.oid='temacase_test.notizie_acquisizione'::regclass
)
SELECT categoria,nome,dettagli FROM controlli ORDER BY categoria,nome;
