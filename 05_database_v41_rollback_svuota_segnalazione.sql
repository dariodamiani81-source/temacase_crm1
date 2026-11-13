-- TEMACASE CRM v41: rollback del solo vincolo testo non vuoto.
-- ATTENZIONE: prima di riattivarlo occorre valorizzare le segnalazioni svuotate.
-- Nessuna riga viene modificata automaticamente.
DO $rollback$
BEGIN
  IF EXISTS (
    SELECT 1 FROM temacase_test.notizie_acquisizione
    WHERE btrim(testo) = ''
  ) THEN
    RAISE EXCEPTION 'Rollback bloccato: esistono notizie con Segnalazione vuota. Valorizzale prima di ripristinare il vincolo.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'temacase_test.notizie_acquisizione'::regclass
      AND conname = 'notizie_acquisizione_testo_check'
  ) THEN
    ALTER TABLE temacase_test.notizie_acquisizione
      ADD CONSTRAINT notizie_acquisizione_testo_check
      CHECK (btrim(testo) <> '');
  END IF;
END;
$rollback$;
