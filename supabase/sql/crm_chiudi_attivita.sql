-- Chiude un'attivita dal bot. Non cancella la riga: imposta lo stato.
-- Dopo l'aggiornamento riallinea la foto locale del ritorno Google, cosi il
-- controllo del minuto successivo non segnala un conflitto.
CREATE OR REPLACE FUNCTION temacase_test.crm_chiudi_attivita(fonte text, fonte_id bigint, modo text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, temacase_test
AS $$
DECLARE
  u bigint := temacase_test.crm_google_v2_utente();
  attuale text;
  nuovo text;
  quante integer;
  invio_id uuid;
BEGIN
  IF u IS NULL
    OR modo NOT IN ('completa', 'elimina')
    OR fonte NOT IN ('notizia', 'personale', 'followup', 'visita') THEN
    RETURN 'non_valida';
  END IF;

  IF fonte = 'personale' THEN
    SELECT p.stato INTO attuale
    FROM temacase_test.crm_attivita_personali AS p
    WHERE p.id = fonte_id AND p.consulente_telegram_id = u;
    nuovo := CASE WHEN modo = 'completa' THEN 'completato' ELSE 'annullato' END;
  ELSIF fonte = 'notizia' THEN
    SELECT f.stato INTO attuale
    FROM temacase_test.followup_acquisizione AS f
    JOIN temacase_test.notizie_acquisizione AS nz ON nz.id = f.notizia_id
    WHERE f.id = fonte_id AND nz.consulente_telegram_id = u;
    nuovo := CASE WHEN modo = 'completa' THEN 'completato' ELSE 'annullato' END;
  ELSIF fonte = 'followup' THEN
    SELECT a.stato INTO attuale
    FROM temacase_test.crm_attivita_operative AS a
    WHERE a.id = fonte_id AND a.tipo = 'followup'
      AND EXISTS (
        SELECT 1 FROM temacase_test.crm_membri_agenzia AS m
        WHERE m.agenzia_id = a.agenzia_id
          AND m.consulente_telegram_id = u AND m.attivo
      );
    nuovo := CASE WHEN modo = 'completa' THEN 'concluso' ELSE 'annullato' END;
  ELSE
    SELECT v.stato INTO attuale
    FROM temacase_test.visite AS v
    WHERE v.id = fonte_id
      AND EXISTS (
        SELECT 1
        FROM temacase_test.crm_immobili_agenzia AS i
        JOIN temacase_test.crm_membri_agenzia AS m ON m.agenzia_id = i.agenzia_id
        WHERE i.immobile_id = v.immobile_id
          AND m.consulente_telegram_id = u AND m.attivo
      );
    nuovo := CASE WHEN modo = 'completa' THEN 'svolta' ELSE 'annullata' END;
  END IF;

  IF attuale IS NULL THEN RETURN 'assente'; END IF;
  IF attuale = nuovo THEN RETURN 'invariato'; END IF;
  IF modo = 'completa' AND attuale NOT IN ('aperto', 'programmata') THEN RETURN 'non_valida'; END IF;

  IF fonte = 'personale' THEN
    UPDATE temacase_test.crm_attivita_personali
    SET stato = nuovo
    WHERE id = fonte_id AND consulente_telegram_id = u AND stato = attuale;
  ELSIF fonte = 'notizia' THEN
    UPDATE temacase_test.followup_acquisizione AS f
    SET stato = nuovo
    FROM temacase_test.notizie_acquisizione AS nz
    WHERE f.id = fonte_id AND f.notizia_id = nz.id
      AND nz.consulente_telegram_id = u AND f.stato = attuale;
  ELSIF fonte = 'followup' THEN
    UPDATE temacase_test.crm_attivita_operative AS a
    SET stato = nuovo
    WHERE a.id = fonte_id AND a.tipo = 'followup' AND a.stato = attuale
      AND EXISTS (
        SELECT 1 FROM temacase_test.crm_membri_agenzia AS m
        WHERE m.agenzia_id = a.agenzia_id
          AND m.consulente_telegram_id = u AND m.attivo
      );
  ELSE
    UPDATE temacase_test.visite AS v
    SET stato = nuovo
    WHERE v.id = fonte_id AND v.stato = attuale
      AND EXISTS (
        SELECT 1
        FROM temacase_test.crm_immobili_agenzia AS i
        JOIN temacase_test.crm_membri_agenzia AS m ON m.agenzia_id = i.agenzia_id
        WHERE i.immobile_id = v.immobile_id
          AND m.consulente_telegram_id = u AND m.attivo
      );
  END IF;

  GET DIAGNOSTICS quante = ROW_COUNT;
  IF quante = 0 THEN RETURN 'assente'; END IF;

  SELECT o.id INTO invio_id
  FROM temacase_test.crm_google_invii AS o
  WHERE o.fonte = crm_chiudi_attivita.fonte
    AND o.fonte_id = crm_chiudi_attivita.fonte_id
    AND o.consulente_telegram_id = u
    AND o.stato = 'sincronizzato'
  ORDER BY o.creato_il DESC
  LIMIT 1;

  IF invio_id IS NOT NULL THEN
    UPDATE temacase_test.crm_google_ritorni
    SET locale = temacase_test.crm27_locale(invio_id),
        conflitto = false,
        errore = NULL,
        applicato_il = now()
    WHERE crm_google_ritorni.invio = invio_id;
  END IF;

  RETURN nuovo;
END;
$$;

REVOKE ALL ON FUNCTION temacase_test.crm_chiudi_attivita(text, bigint, text)
  FROM PUBLIC, anon, authenticated, temacase_mcp, temacase_mcp_login;
GRANT EXECUTE ON FUNCTION temacase_test.crm_chiudi_attivita(text, bigint, text)
  TO temacase_mcp_login;
