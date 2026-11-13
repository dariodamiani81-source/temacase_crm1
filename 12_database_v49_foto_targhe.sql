-- Temacase CRM v49 - documentazione fotografica targhe amministratori
-- Eseguire prima del deploy della Edge Function v49.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE TABLE IF NOT EXISTS temacase_test.crm_foto_palazzi_amministratori (
  id bigserial PRIMARY KEY,
  consulente_telegram_id bigint NOT NULL,
  palazzo_id bigint NOT NULL REFERENCES temacase_test.palazzi(id) ON DELETE RESTRICT,
  amministratore_id bigint NOT NULL REFERENCES temacase_test.amministratori(id) ON DELETE RESTRICT,
  telegram_file_id text NOT NULL,
  telegram_update_id bigint NOT NULL,
  acquisita_il timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT crm_foto_palazzi_amministratori_update_unique UNIQUE(consulente_telegram_id,telegram_update_id)
);
CREATE INDEX IF NOT EXISTS crm_foto_palazzi_amministratori_palazzo_idx
  ON temacase_test.crm_foto_palazzi_amministratori(consulente_telegram_id,palazzo_id,acquisita_il DESC);
ALTER TABLE temacase_test.crm_foto_palazzi_amministratori ENABLE ROW LEVEL SECURITY;
DO $p$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='temacase_test'
    AND tablename='crm_foto_palazzi_amministratori' AND policyname='foto_targhe_consulente') THEN
    CREATE POLICY foto_targhe_consulente ON temacase_test.crm_foto_palazzi_amministratori
      FOR ALL TO PUBLIC
      USING (consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id',true),'')::bigint)
      WITH CHECK (consulente_telegram_id = NULLIF(current_setting('temacase.telegram_user_id',true),'')::bigint);
  END IF;
END $p$;
GRANT SELECT, INSERT ON temacase_test.crm_foto_palazzi_amministratori TO authenticated,service_role,temacase_mcp_login;
GRANT USAGE, SELECT ON SEQUENCE temacase_test.crm_foto_palazzi_amministratori_id_seq TO authenticated,service_role,temacase_mcp_login;
COMMIT;
SELECT to_regclass('temacase_test.crm_foto_palazzi_amministratori') IS NOT NULL AS v49_foto_targhe_disponibili;
