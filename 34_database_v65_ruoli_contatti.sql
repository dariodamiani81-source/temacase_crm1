-- TEMACASE v65: modifica controllata di un ruolo per Notizia o Immobile.
-- Nessun cambiamento ai record esistenti durante la migrazione.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION temacase_test.crm65_ruolo_contatto(
  p_kind text,p_contatto bigint,p_target bigint,p_ruolo text,p_remove boolean DEFAULT false
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog,temacase_test
AS $$
DECLARE u bigint; c record; v_ag uuid;
BEGIN
  u:=NULLIF(current_setting('temacase.telegram_user_id',true),'')::bigint;
  IF u IS NULL OR p_contatto<=0 OR p_target<=0 OR p_kind NOT IN ('n','i') THEN
    RAISE EXCEPTION 'Parametri o identita non validi' USING ERRCODE='42501';
  END IF;
  SELECT id,agenzia_id,consulente_telegram_id,visibilita INTO c
  FROM temacase_test.crm_contatti
  WHERE id=p_contatto AND consulente_telegram_id=u FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Contatto non appartenente all utente' USING ERRCODE='42501'; END IF;
  IF p_kind='n' THEN
    PERFORM 1 FROM temacase_test.notizie_acquisizione WHERE id=p_target AND consulente_telegram_id=u;
    IF NOT FOUND THEN RAISE EXCEPTION 'Notizia non appartenente all utente' USING ERRCODE='42501'; END IF;
    IF NOT p_remove AND p_ruolo NOT IN ('proprietario','venditore','comproprietario','acquirente','interessato','locatore','conduttore') THEN
      RAISE EXCEPTION 'Ruolo non valido' USING ERRCODE='22023';
    END IF;
    DELETE FROM temacase_test.crm_notizie_contatti WHERE notizia_id=p_target AND contatto_id=p_contatto;
    IF NOT p_remove THEN
      INSERT INTO temacase_test.crm_notizie_contatti(notizia_id,contatto_id,ruolo)
      VALUES(p_target,p_contatto,p_ruolo);
    END IF;
  ELSE
    SELECT a.agenzia_id INTO v_ag FROM temacase_test.crm_immobili_agenzia a
    JOIN temacase_test.crm_membri_agenzia m ON m.agenzia_id=a.agenzia_id
     AND m.consulente_telegram_id=u AND m.attivo
    WHERE a.immobile_id=p_target AND a.agenzia_id=c.agenzia_id LIMIT 1;
    IF v_ag IS NULL THEN RAISE EXCEPTION 'Immobile non abilitato per l utente' USING ERRCODE='42501'; END IF;
    IF NOT p_remove AND p_ruolo NOT IN ('venditore','comproprietario','acquirente','interessato','locatore','conduttore') THEN
      RAISE EXCEPTION 'Ruolo non valido' USING ERRCODE='22023';
    END IF;
    DELETE FROM temacase_test.crm_immobili_contatti
      WHERE agenzia_id=v_ag AND immobile_id=p_target AND contatto_id=p_contatto;
    IF NOT p_remove THEN
      -- Un ruolo operativo di agenzia rende visibile il contatto ai membri abilitati,
      -- scelta esplicitata nell'anteprima Telegram prima della conferma.
      UPDATE temacase_test.crm_contatti SET visibilita='agenzia'
      WHERE id=p_contatto AND consulente_telegram_id=u AND visibilita='privato';
      INSERT INTO temacase_test.crm_immobili_contatti(agenzia_id,immobile_id,contatto_id,ruolo)
      VALUES(v_ag,p_target,p_contatto,p_ruolo);
    END IF;
  END IF;
  RETURN CASE WHEN p_remove THEN 'scollegato' ELSE 'collegato' END;
END $$;
REVOKE ALL ON FUNCTION temacase_test.crm65_ruolo_contatto(text,bigint,bigint,text,boolean) FROM PUBLIC,anon,authenticated,temacase_mcp;
GRANT EXECUTE ON FUNCTION temacase_test.crm65_ruolo_contatto(text,bigint,bigint,text,boolean) TO temacase_mcp_login;
SELECT has_function_privilege('temacase_mcp_login','temacase_test.crm65_ruolo_contatto(text,bigint,bigint,text,boolean)','EXECUTE') AS funzione_ruoli_disponibile;
COMMIT;
