-- Types de frais (AMENDE, DROIT DE DOUANE…) rattachés à un compte général et à leur sous-compte.
CREATE TABLE types_frais (
  id TEXT PRIMARY KEY,
  libelle TEXT NOT NULL,
  montant NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (montant >= 0),
  compte_general TEXT REFERENCES plan_comptable (code) ON UPDATE CASCADE,
  compte TEXT REFERENCES plan_comptable (code) ON UPDATE CASCADE,
  numero BIGSERIAL UNIQUE,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX types_frais_libelle_unique ON types_frais (lower(libelle));
