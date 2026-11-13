-- Rollback protetto: ripristina il CHECK a 500 caratteri SOLO se nessuna bozza supera 500.
-- Da usare solo se necessario: il vecchio limite non e' compatibile con le importazioni lunghe.
BEGIN;

DO $rollback$
DECLARE
  numero_bozze_lunghe bigint;
  vincolo_attuale text;
BEGIN
  SELECT count(*) INTO numero_bozze_lunghe
  FROM temacase_test.bozze_notizie_telegram
  WHERE char_length(btrim(testo)) > 500;

  IF numero_bozze_lunghe > 0 THEN
    RAISE EXCEPTION 'Rollback bloccato: % bozze superano 500 caratteri. Nessun dato cancellato.', numero_bozze_lunghe;
  END IF;

  SELECT pg_get_constraintdef(c.oid) INTO vincolo_attuale
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'temacase_test'
    AND t.relname = 'bozze_notizie_telegram'
    AND c.conname = 'bozze_notizie_telegram_testo_check'
    AND c.contype = 'c';

  IF vincolo_attuale IS NULL OR vincolo_attuale NOT LIKE '%3000%' THEN
    RAISE EXCEPTION 'Il CHECK corrente non e'' quello v54 da 3000 caratteri: %. Nessuna modifica.', vincolo_attuale;
  END IF;
END;
$rollback$;

ALTER TABLE temacase_test.bozze_notizie_telegram
  DROP CONSTRAINT bozze_notizie_telegram_testo_check;

ALTER TABLE temacase_test.bozze_notizie_telegram
  ADD CONSTRAINT bozze_notizie_telegram_testo_check
  CHECK (char_length(btrim(testo)) >= 1 AND char_length(btrim(testo)) <= 500);

COMMIT;

SELECT pg_get_constraintdef(c.oid) AS definizione
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'temacase_test'
  AND t.relname = 'bozze_notizie_telegram'
  AND c.conname = 'bozze_notizie_telegram_testo_check';
