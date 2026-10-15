-- Modes de règlement liés aux codes journaux, et écritures comptables générées depuis la gestion.

CREATE TABLE modes_reglement (
  id TEXT PRIMARY KEY,
  intitule TEXT NOT NULL,
  type TEXT NOT NULL,
  journal_client TEXT REFERENCES journaux (code) ON UPDATE CASCADE,
  journal_fournisseur TEXT REFERENCES journaux (code) ON UPDATE CASCADE,
  compte_tresorerie TEXT REFERENCES plan_comptable (code) ON UPDATE CASCADE,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX modes_reglement_intitule_unique ON modes_reglement (lower(intitule));

-- Une écriture = une pièce équilibrée (somme des débits = somme des crédits).
CREATE TABLE ecritures (
  id BIGSERIAL PRIMARY KEY,
  journal_code TEXT NOT NULL,
  date DATE NOT NULL,
  piece TEXT NOT NULL DEFAULT '',
  libelle TEXT NOT NULL DEFAULT '',
  -- 'gestion' : générée par la mise à jour comptable (régénérable).
  origine TEXT NOT NULL DEFAULT 'gestion',
  categorie TEXT NOT NULL,
  -- Document de gestion à l'origine de l'écriture (évite les doublons).
  source TEXT,
  auteur TEXT NOT NULL DEFAULT '',
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ecritures_source_unique ON ecritures (source) WHERE source IS NOT NULL;
CREATE INDEX ecritures_journal_date ON ecritures (journal_code, date);

CREATE TABLE ecriture_lignes (
  id BIGSERIAL PRIMARY KEY,
  ecriture_id BIGINT NOT NULL REFERENCES ecritures (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  compte TEXT NOT NULL,
  libelle TEXT NOT NULL DEFAULT '',
  debit NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (credit >= 0)
);
CREATE INDEX ecriture_lignes_ecriture ON ecriture_lignes (ecriture_id);
CREATE INDEX ecriture_lignes_compte ON ecriture_lignes (compte);

-- Historique des mises à jour comptables lancées depuis l'ERP.
CREATE TABLE mises_a_jour_comptables (
  id BIGSERIAL PRIMARY KEY,
  du DATE NOT NULL,
  au DATE NOT NULL,
  categories TEXT[] NOT NULL,
  ecritures INTEGER NOT NULL,
  auteur TEXT NOT NULL DEFAULT '',
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
