-- Richieste di ricerca collegate a un contatto. Non modificano anagrafica ne ruoli.
CREATE TABLE IF NOT EXISTS temacase_test.crm_richieste (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  contatto_id bigint NOT NULL REFERENCES temacase_test.crm_contatti(id),
  agenzia_id uuid NOT NULL,
  consulente_telegram_id bigint NOT NULL,
  operazione text NOT NULL CHECK (operazione IN ('acquisto','locazione')),
  stato text NOT NULL DEFAULT 'aperta' CHECK (stato IN ('aperta','sospesa','soddisfatta','annullata')),
  tipologia text CHECK (tipologia IS NULL OR length(btrim(tipologia)) BETWEEN 1 AND 80),
  mq_min integer CHECK (mq_min IS NULL OR mq_min BETWEEN 1 AND 100000),
  mq_max integer CHECK (mq_max IS NULL OR mq_max BETWEEN 1 AND 100000),
  tipo_stabile text CHECK (tipo_stabile IS NULL OR tipo_stabile IN ('ringhiera','civile','signorile','economico','altro')),
  budget_max numeric(14,2) CHECK (budget_max IS NULL OR budget_max >= 0),
  note text CHECK (note IS NULL OR length(note) <= 1000),
  creato_il timestamptz NOT NULL DEFAULT now(),
  CHECK (mq_min IS NULL OR mq_max IS NULL OR mq_min <= mq_max),
  FOREIGN KEY (agenzia_id, consulente_telegram_id)
    REFERENCES temacase_test.crm_membri_agenzia(agenzia_id, consulente_telegram_id)
);

CREATE TABLE IF NOT EXISTS temacase_test.crm_richieste_zone (
  richiesta_id bigint NOT NULL REFERENCES temacase_test.crm_richieste(id) ON DELETE CASCADE,
  zona text NOT NULL CHECK (length(btrim(zona)) BETWEEN 1 AND 80),
  PRIMARY KEY (richiesta_id, zona)
);

CREATE TABLE IF NOT EXISTS temacase_test.crm_richieste_immobili (
  richiesta_id bigint NOT NULL REFERENCES temacase_test.crm_richieste(id) ON DELETE CASCADE,
  immobile_id bigint NOT NULL REFERENCES temacase_test.immobili(id),
  esito text NOT NULL CHECK (esito IN ('proposto','visto','scartato','trattativa')),
  nota text CHECK (nota IS NULL OR length(nota) <= 300),
  aggiornato_il timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (richiesta_id, immobile_id)
);

CREATE INDEX IF NOT EXISTS crm_richieste_contatto_idx
  ON temacase_test.crm_richieste (contatto_id, stato);

ALTER TABLE temacase_test.crm_richieste ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_richieste FORCE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_richieste_zone ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_richieste_zone FORCE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_richieste_immobili ENABLE ROW LEVEL SECURITY;
ALTER TABLE temacase_test.crm_richieste_immobili FORCE ROW LEVEL SECURITY;

REVOKE ALL ON temacase_test.crm_richieste, temacase_test.crm_richieste_zone, temacase_test.crm_richieste_immobili
  FROM PUBLIC, anon, authenticated, temacase_mcp;
GRANT SELECT, INSERT, UPDATE ON temacase_test.crm_richieste, temacase_test.crm_richieste_zone, temacase_test.crm_richieste_immobili
  TO temacase_mcp_login;
GRANT USAGE, SELECT ON SEQUENCE temacase_test.crm_richieste_id_seq TO temacase_mcp_login;

DROP POLICY IF EXISTS crm_richieste_leggi ON temacase_test.crm_richieste;
CREATE POLICY crm_richieste_leggi ON temacase_test.crm_richieste
  FOR SELECT TO temacase_mcp_login
  USING (EXISTS (
    SELECT 1 FROM temacase_test.crm_contatti c
    WHERE c.id = crm_richieste.contatto_id
      AND (
        c.consulente_telegram_id = nullif(current_setting('temacase.telegram_user_id', true), '')::bigint
        OR (
          c.visibilita = 'agenzia'
          AND EXISTS (
            SELECT 1 FROM temacase_test.crm_membri_agenzia m
            WHERE m.agenzia_id = c.agenzia_id
              AND m.consulente_telegram_id = nullif(current_setting('temacase.telegram_user_id', true), '')::bigint
              AND m.attivo
          )
        )
      )
  ));

DROP POLICY IF EXISTS crm_richieste_scrivi ON temacase_test.crm_richieste;
CREATE POLICY crm_richieste_scrivi ON temacase_test.crm_richieste
  FOR INSERT TO temacase_mcp_login
  WITH CHECK (
    consulente_telegram_id = nullif(current_setting('temacase.telegram_user_id', true), '')::bigint
    AND EXISTS (
      SELECT 1 FROM temacase_test.crm_contatti c
      WHERE c.id = contatto_id
        AND c.consulente_telegram_id = consulente_telegram_id
        AND c.agenzia_id = crm_richieste.agenzia_id
    )
  );

DROP POLICY IF EXISTS crm_richieste_aggiorna ON temacase_test.crm_richieste;
CREATE POLICY crm_richieste_aggiorna ON temacase_test.crm_richieste
  FOR UPDATE TO temacase_mcp_login
  USING (consulente_telegram_id = nullif(current_setting('temacase.telegram_user_id', true), '')::bigint)
  WITH CHECK (consulente_telegram_id = nullif(current_setting('temacase.telegram_user_id', true), '')::bigint);

DROP POLICY IF EXISTS crm_richieste_zone_leggi ON temacase_test.crm_richieste_zone;
CREATE POLICY crm_richieste_zone_leggi ON temacase_test.crm_richieste_zone
  FOR SELECT TO temacase_mcp_login
  USING (EXISTS (
    SELECT 1 FROM temacase_test.crm_richieste r
    WHERE r.id = crm_richieste_zone.richiesta_id
  ));

DROP POLICY IF EXISTS crm_richieste_zone_scrivi ON temacase_test.crm_richieste_zone;
CREATE POLICY crm_richieste_zone_scrivi ON temacase_test.crm_richieste_zone
  FOR INSERT TO temacase_mcp_login
  WITH CHECK (EXISTS (
    SELECT 1 FROM temacase_test.crm_richieste r
    WHERE r.id = richiesta_id
      AND r.consulente_telegram_id = nullif(current_setting('temacase.telegram_user_id', true), '')::bigint
  ));

DROP POLICY IF EXISTS crm_richieste_immobili_leggi ON temacase_test.crm_richieste_immobili;
CREATE POLICY crm_richieste_immobili_leggi ON temacase_test.crm_richieste_immobili
  FOR SELECT TO temacase_mcp_login
  USING (EXISTS (
    SELECT 1 FROM temacase_test.crm_richieste r
    WHERE r.id = crm_richieste_immobili.richiesta_id
  ));

DROP POLICY IF EXISTS crm_richieste_immobili_scrivi ON temacase_test.crm_richieste_immobili;
CREATE POLICY crm_richieste_immobili_scrivi ON temacase_test.crm_richieste_immobili
  FOR INSERT TO temacase_mcp_login
  WITH CHECK (EXISTS (
    SELECT 1 FROM temacase_test.crm_richieste r
    JOIN temacase_test.crm_immobili_agenzia a ON a.immobile_id = crm_richieste_immobili.immobile_id
    JOIN temacase_test.crm_membri_agenzia m ON m.agenzia_id = a.agenzia_id
      AND m.consulente_telegram_id = r.consulente_telegram_id AND m.attivo
    WHERE r.id = richiesta_id
      AND r.consulente_telegram_id = nullif(current_setting('temacase.telegram_user_id', true), '')::bigint
  ));

DROP POLICY IF EXISTS crm_richieste_immobili_aggiorna ON temacase_test.crm_richieste_immobili;
CREATE POLICY crm_richieste_immobili_aggiorna ON temacase_test.crm_richieste_immobili
  FOR UPDATE TO temacase_mcp_login
  USING (EXISTS (
    SELECT 1 FROM temacase_test.crm_richieste r
    WHERE r.id = crm_richieste_immobili.richiesta_id
      AND r.consulente_telegram_id = nullif(current_setting('temacase.telegram_user_id', true), '')::bigint
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM temacase_test.crm_richieste r
    WHERE r.id = richiesta_id
      AND r.consulente_telegram_id = nullif(current_setting('temacase.telegram_user_id', true), '')::bigint
  ));
