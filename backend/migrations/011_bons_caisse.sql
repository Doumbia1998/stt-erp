-- Bons de caisse numérotés : frais des camions (transporteurs et flotte STT)
-- et dépenses administratives (PDG, DG…), chacun relié à un compte comptable.

CREATE TABLE bons_caisse (
  id TEXT PRIMARY KEY,
  numero BIGSERIAL UNIQUE,
  categorie TEXT NOT NULL CHECK (categorie IN ('Frais camion', 'Dépense administrative')),
  date DATE NOT NULL,
  code_journal TEXT REFERENCES journaux (code) ON UPDATE CASCADE,
  beneficiaire TEXT NOT NULL DEFAULT '',
  motif TEXT NOT NULL DEFAULT '',
  -- Numéro du bon papier quand le bon a été fait à la main.
  reference_manuelle TEXT NOT NULL DEFAULT '',
  observations TEXT NOT NULL DEFAULT '',
  montant NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (montant >= 0),
  auteur TEXT NOT NULL DEFAULT '',
  version INTEGER NOT NULL DEFAULT 1,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE bon_caisse_lignes (
  id BIGSERIAL PRIMARY KEY,
  bon_id TEXT NOT NULL REFERENCES bons_caisse (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  dossier_id TEXT REFERENCES dossiers (id) ON DELETE SET NULL,
  plaque TEXT NOT NULL DEFAULT '',
  -- « Transporteur » (camion d'un transporteur) ou « STT » (nos camions).
  proprietaire TEXT NOT NULL DEFAULT '',
  transporteur_id TEXT REFERENCES prestataires (id) ON DELETE SET NULL,
  chauffeur TEXT NOT NULL DEFAULT '',
  telephone TEXT NOT NULL DEFAULT '',
  type_frais_id TEXT REFERENCES types_frais (id) ON DELETE SET NULL,
  compte TEXT REFERENCES plan_comptable (code) ON UPDATE CASCADE,
  libelle TEXT NOT NULL DEFAULT '',
  montant NUMERIC(15, 2) NOT NULL CHECK (montant > 0)
);
CREATE INDEX bon_caisse_lignes_bon ON bon_caisse_lignes (bon_id, position);

-- Nouveau module « Dépenses & Frais » dans la barre du haut : ouvert aux administrateurs.
UPDATE utilisateurs
SET modules = modules || ARRAY['Dépenses & Frais']
WHERE role = 'Administrateur' AND NOT ('Dépenses & Frais' = ANY (modules));
