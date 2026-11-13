-- TEMACASE CRM v48 - diagnostica UNICA, sola lettura.
-- Un solo SELECT: Supabase mostra direttamente il risultato necessario.
-- Nessuna modifica a tabelle, dati, ruoli o policy.
WITH privilegi AS (
  SELECT r.rolname AS ruolo,
         r.rolcanlogin AS accesso_db,
         has_schema_privilege(r.oid, 'temacase_test', 'USAGE') AS schema_accessibile,
         has_table_privilege(r.oid, 'temacase_test.amministratori', 'SELECT') AS puo_leggere_amministratori,
         has_table_privilege(r.oid, 'temacase_test.crm_sessioni_telegram', 'INSERT') AS puo_creare_sessioni,
         has_table_privilege(r.oid, 'temacase_test.crm_amministratori_archivio', 'SELECT') AS puo_leggere_archivio,
         has_table_privilege(r.oid, 'temacase_test.crm_amministratori_archivio', 'INSERT') AS puo_archiviare,
         has_table_privilege(r.oid, 'temacase_test.crm_amministratori_archivio', 'DELETE') AS puo_ripristinare
  FROM pg_roles r
  WHERE r.rolcanlogin OR r.rolname IN ('authenticated','service_role')
)
SELECT ruolo, accesso_db, schema_accessibile,
       puo_leggere_amministratori, puo_creare_sessioni,
       puo_leggere_archivio, puo_archiviare, puo_ripristinare,
       CASE WHEN schema_accessibile AND puo_leggere_amministratori AND puo_creare_sessioni AND NOT puo_leggere_archivio
            THEN 'POSSIBILE BLOCCO: manca SELECT sull archivio v48'
            WHEN schema_accessibile AND puo_leggere_amministratori AND puo_creare_sessioni
            THEN 'Privilegi compatibili: controllare il log se il bot fallisce'
            ELSE 'Ruolo non identificabile come usato dal bot con questi soli controlli'
       END AS diagnosi
FROM privilegi
WHERE schema_accessibile AND (puo_leggere_amministratori OR puo_creare_sessioni)
ORDER BY puo_creare_sessioni DESC, puo_leggere_amministratori DESC, ruolo;
