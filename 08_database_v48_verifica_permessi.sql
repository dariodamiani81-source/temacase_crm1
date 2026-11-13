-- Temacase CRM v48 - diagnosi di sola lettura.
-- Non contiene credenziali e non modifica dati o autorizzazioni.
WITH ruoli AS (
  SELECT r.rolname, r.rolcanlogin,
         has_schema_privilege(r.oid, 'temacase_test', 'USAGE') AS schema_accessibile,
         has_table_privilege(r.oid, 'temacase_test.amministratori', 'SELECT') AS puo_leggere_amministratori,
         has_table_privilege(r.oid, 'temacase_test.crm_sessioni_telegram', 'INSERT') AS puo_creare_sessioni,
         has_table_privilege(r.oid, 'temacase_test.crm_amministratori_archivio', 'SELECT') AS puo_leggere_archivio,
         has_table_privilege(r.oid, 'temacase_test.crm_amministratori_archivio', 'INSERT') AS puo_archiviare,
         has_table_privilege(r.oid, 'temacase_test.crm_amministratori_archivio', 'DELETE') AS puo_ripristinare
  FROM pg_roles r
  WHERE r.rolcanlogin OR r.rolname IN ('authenticated', 'service_role')
)
SELECT rolname AS ruolo, rolcanlogin AS accesso_db, schema_accessibile,
       puo_leggere_amministratori, puo_creare_sessioni,
       puo_leggere_archivio, puo_archiviare, puo_ripristinare,
       CASE WHEN schema_accessibile AND puo_leggere_amministratori AND puo_creare_sessioni
                    AND NOT puo_leggere_archivio
            THEN 'ATTENZIONE: possibile ruolo del bot senza permessi sulla tabella v48'
            WHEN schema_accessibile AND puo_leggere_amministratori AND puo_creare_sessioni
            THEN 'Controllare anche il log della funzione'
            ELSE '' END AS diagnosi
FROM ruoli
WHERE schema_accessibile AND (puo_leggere_amministratori OR puo_creare_sessioni)
ORDER BY puo_creare_sessioni DESC, puo_leggere_amministratori DESC, rolname;

SELECT schemaname, tablename, policyname, cmd, roles::text AS ruoli_policy,
       qual AS condizione_lettura, with_check AS condizione_scrittura
FROM pg_policies
WHERE schemaname='temacase_test' AND tablename='crm_amministratori_archivio';
