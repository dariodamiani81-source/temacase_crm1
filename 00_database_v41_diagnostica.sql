-- TEMACASE v41 - DIAGNOSTICA SOLA LETTURA, NON ALTERA DATI
-- Mostra eventuali vincoli che impediscono di svuotare la Segnalazione.
SELECT 'vincolo' AS tipo, con.conname AS nome, pg_get_constraintdef(con.oid) AS definizione
FROM pg_constraint con
WHERE con.conrelid='temacase_test.notizie_acquisizione'::regclass
  AND (pg_get_constraintdef(con.oid) ILIKE '%testo%' OR con.contype='c')
UNION ALL
SELECT 'colonna', a.attname, concat('NOT NULL: ',a.attnotnull::text, ', tipo: ',format_type(a.atttypid,a.atttypmod))
FROM pg_attribute a
WHERE a.attrelid='temacase_test.notizie_acquisizione'::regclass
  AND a.attname='testo'
ORDER BY tipo,nome;
