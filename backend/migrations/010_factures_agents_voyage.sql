-- Frontière / Bureau DD / Enquête : validation des saisies, photo du T1,
-- factures des agents réglées par la Direction.

CREATE TABLE factures_agent (
  id TEXT PRIMARY KEY,
  numero BIGSERIAL UNIQUE,
  reference TEXT NOT NULL,
  module TEXT NOT NULL CHECK (module IN ('Frontière', 'Bureau DD', 'Enquête')),
  agent_id TEXT REFERENCES utilisateurs (id) ON DELETE SET NULL,
  agent_nom TEXT NOT NULL DEFAULT '',
  date_emission DATE NOT NULL,
  observations TEXT NOT NULL DEFAULT '',
  montant NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (montant >= 0),
  auteur TEXT NOT NULL DEFAULT '',
  version INTEGER NOT NULL DEFAULT 1,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX factures_agent_reference ON factures_agent (lower(reference));

CREATE TABLE facture_agent_reglements (
  id BIGSERIAL PRIMARY KEY,
  facture_id TEXT NOT NULL REFERENCES factures_agent (id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  date TIMESTAMP NOT NULL,
  montant NUMERIC(15, 2) NOT NULL CHECK (montant > 0),
  code_journal TEXT REFERENCES journaux (code) ON UPDATE CASCADE,
  mode_paiement TEXT NOT NULL DEFAULT '',
  numero_cheque TEXT NOT NULL DEFAULT '',
  observations TEXT NOT NULL DEFAULT '',
  auteur TEXT NOT NULL DEFAULT '',
  saisi_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (facture_id, uid)
);

ALTER TABLE voyage_affectations
  ADD COLUMN statut TEXT NOT NULL DEFAULT 'Brouillon' CHECK (statut IN ('Brouillon', 'Validé')),
  ADD COLUMN valide_par TEXT NOT NULL DEFAULT '',
  ADD COLUMN valide_le TIMESTAMPTZ,
  -- Photo du T1 (JPEG en base64), chargée à la demande.
  ADD COLUMN t1_image TEXT,
  ADD COLUMN facture_id TEXT REFERENCES factures_agent (id) ON DELETE SET NULL;

-- Le T1 devient une photo et « Client » n'est plus un frais de la Frontière.
UPDATE voyage_affectations
SET frais = frais - 'T1' - 'Client'
WHERE module = 'Frontière' AND (frais ? 'T1' OR frais ? 'Client');

UPDATE voyage_affectations a
SET total = COALESCE((SELECT SUM(value::numeric) FROM jsonb_each_text(a.frais)), 0)
WHERE module = 'Frontière';
