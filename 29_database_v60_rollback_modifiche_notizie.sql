-- ROLLBACK v60 di sicurezza. Il ripristino non cancella alcun dato.
-- ATTENZIONE: prima di eseguire un REVOKE su colonne già utilizzate da altre
-- versioni, confrontare i privilegi esistenti: un REVOKE non mirato potrebbe
-- rompere nuovamente modifiche precedentemente operative.
-- Questo script ripristina soltanto la policy aggiuntiva v60; i privilegi di
-- colonna vengono lasciati intatti per evitare regressioni.
BEGIN;
DROP POLICY IF EXISTS crm60_notizie_update_proprie ON temacase_test.notizie_acquisizione;
COMMIT;
SELECT 'Policy v60 rimossa; privilegi sulle colonne conservati per sicurezza' AS esito;
