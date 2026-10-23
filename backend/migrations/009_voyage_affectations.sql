-- Affectation des voyages aux modules Frontière, Bureau DD et Enquête,
-- avec les frais saisis par chaque agent.

CREATE TABLE voyage_affectations (
  id TEXT PRIMARY KEY,
  -- Voyage = camion + date de départ (plaque normalisée|jj/mm/aaaa).
  voyage_cle TEXT NOT NULL,
  module TEXT NOT NULL CHECK (module IN ('Frontière', 'Bureau DD', 'Enquête')),
  agent_id TEXT REFERENCES utilisateurs (id) ON DELETE SET NULL,
  -- Copie des informations du voyage au moment de l'affectation.
  date_depart DATE,
  plaque TEXT NOT NULL DEFAULT '',
  transporteur TEXT NOT NULL DEFAULT '',
  chauffeur TEXT NOT NULL DEFAULT '',
  telephone TEXT NOT NULL DEFAULT '',
  dossiers TEXT NOT NULL DEFAULT '',
  clients TEXT NOT NULL DEFAULT '',
  transitaire TEXT NOT NULL DEFAULT '',
  conteneurs TEXT NOT NULL DEFAULT '',
  frais JSONB NOT NULL DEFAULT '{}',
  total NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (total >= 0),
  observations TEXT NOT NULL DEFAULT '',
  assigne_par TEXT NOT NULL DEFAULT '',
  saisi_par TEXT NOT NULL DEFAULT '',
  saisi_le TIMESTAMPTZ,
  version INTEGER NOT NULL DEFAULT 1,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (voyage_cle, module)
);

-- Les administrateurs voient les nouveaux modules.
UPDATE utilisateurs
SET modules = modules || ARRAY['Frontière', 'Bureau DD', 'Enquête']
WHERE role = 'Administrateur' AND NOT ('Frontière' = ANY (modules));
