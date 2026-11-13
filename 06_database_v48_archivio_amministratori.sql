-- TEMACASE CRM v48 - archivio personale amministratori
-- Non modifica anagrafiche o collegamenti esistenti.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS temacase_test.crm_amministratori_archivio (
  consulente_telegram_id bigint NOT NULL,
  amministratore_id bigint NOT NULL REFERENCES temacase_test.amministratori(id) ON DELETE CASCADE,
  archiviato_il timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT crm_amministratori_archivio_pk PRIMARY KEY (consulente_telegram_id, amministratore_id)
);

-- Isolamento degli archivi personali, anche per eventuali ruoli che non bypassano RLS.
ALTER TABLE temacase_test.crm_amministratori_archivio ENABLE ROW LEVEL SECURITY;
DO $policy$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname = 'temacase_test'
                  AND tablename = 'crm_amministratori_archivio'
                  AND policyname = 'crm_amministratori_archivio_personale') THEN
   CREATE POLICY crm_amministratori_archivio_personale
     ON temacase_test.crm_amministratori_archivio
     FOR ALL
     USING (consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id', true), '')::bigint)
     WITH CHECK (consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id', true), '')::bigint);
 END IF;
END
$policy$;

-- Accesso SQL soggetto alla policy RLS (la funzione Telegram usa il contesto dell'utente).
GRANT SELECT, INSERT, DELETE ON temacase_test.crm_amministratori_archivio TO authenticated, service_role;
COMMIT;

SELECT 'v48_archivio_disponibile' AS verifica,
       to_regclass('temacase_test.crm_amministratori_archivio') IS NOT NULL AS esito;
