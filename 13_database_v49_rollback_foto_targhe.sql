-- Solo se occorre tornare alla v48. Conserva i dati se sono gia state acquisite fotografie.
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM temacase_test.crm_foto_palazzi_amministratori LIMIT 1) THEN
  RAISE EXCEPTION 'Tabella targhe non vuota: esportare e conservare le fotografie prima del rollback';
 END IF;
END $$;
DROP TABLE IF EXISTS temacase_test.crm_foto_palazzi_amministratori;
