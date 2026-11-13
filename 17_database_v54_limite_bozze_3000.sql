-- Temacase CRM: allineamento CHECK bozza Notizia al limite applicativo di 3000 caratteri.
-- Eseguire nel SQL Editor del progetto Supabase corretto.
-- Non modifica o elimina righe esistenti.
BEGIN;

DO $migrazione$
DECLARE
  vincolo_attuale text;
BEGIN
  SELECT pg_get_constraintdef(c.oid)
    INTO vincolo_attuale
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'temacase_test'
    AND t.relname = 'bozze_notizie_telegram'
    AND c.conname = 'bozze_notizie_telegram_testo_check'
    AND c.contype = 'c';

  IF vincolo_attuale IS NULL THEN
    RAISE EXCEPTION 'Vincolo atteso non trovato: bozze_notizie_telegram_testo_check. Nessuna modifica.';
  END IF;

  -- Permette la migrazione solo dal limite di 500 caratteri, gia' verificato.
  IF vincolo_attuale NOT LIKE '%500%' OR vincolo_attuale NOT LIKE '%char_length%' THEN
    RAISE EXCEPTION 'Definizione del vincolo diversa da quella attesa: %. Nessuna modifica.', vincolo_attuale;
  END IF;
END;
$migrazione$;

ALTER TABLE temacase_test.bozze_notizie_telegram
  DROP CONSTRAINT bozze_notizie_telegram_testo_check;

ALTER TABLE temacase_test.bozze_notizie_telegram
  ADD CONSTRAINT bozze_notizie_telegram_testo_check
  CHECK (char_length(btrim(testo)) >= 1 AND char_length(btrim(testo)) <= 3000);

COMMIT;

SELECT c.conname AS nome_vincolo, pg_get_constraintdef(c.oid) AS definizione,
       pg_get_constraintdef(c.oid) LIKE '%3000%' AS limite_3000_attivo
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'temacase_test'
  AND t.relname = 'bozze_notizie_telegram'
  AND c.conname = 'bozze_notizie_telegram_testo_check';
