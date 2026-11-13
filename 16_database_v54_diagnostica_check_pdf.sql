-- TEMACASE v54 - Diagnostica PDF 23514, SOLO LETTURA
-- Una sola SELECT: mostra vincoli CHECK e trigger sulle tabelle del flusso importazione PDF.
WITH nomi(tabella) AS (
 VALUES ('bozze_notizie_telegram'), ('crm_sessioni_telegram'),
        ('notizie_acquisizione'), ('palazzi')
), oggetti AS (
 SELECT n.tabella, c.oid AS oid_tabella
 FROM nomi n LEFT JOIN pg_class c ON c.oid=to_regclass(format('temacase_test.%I',n.tabella))
), righe AS (
 SELECT o.tabella, 'CHECK'::text AS tipo, co.conname::text AS nome,
        pg_get_constraintdef(co.oid, true) AS definizione
 FROM oggetti o JOIN pg_constraint co ON co.conrelid=o.oid_tabella AND co.contype='c'
 UNION ALL
 SELECT o.tabella, 'TRIGGER'::text, tr.tgname::text, pg_get_triggerdef(tr.oid,true)
 FROM oggetti o JOIN pg_trigger tr ON tr.tgrelid=o.oid_tabella AND NOT tr.tgisinternal
)
SELECT tabella, tipo, nome, definizione FROM righe ORDER BY tabella,tipo,nome;
