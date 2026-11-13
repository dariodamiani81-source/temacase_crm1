-- Sola lettura. Diagnostica dei riferimenti all'amministratore #1.
SELECT 'amministratore_1' AS controllo,
 EXISTS(SELECT 1 FROM temacase_test.amministratori WHERE id=1) AS esiste,
 (SELECT count(*) FROM temacase_test.palazzi_amministratori WHERE amministratore_id=1) AS collegamenti_palazzi;

SELECT c.conname AS vincolo,
       c.conrelid::regclass::text AS tabella_referenziante,
       pg_get_constraintdef(c.oid) AS definizione
FROM pg_constraint c
WHERE c.contype = 'f'
 AND c.confrelid = 'temacase_test.amministratori'::regclass
ORDER BY c.conrelid::regclass::text,c.conname;
