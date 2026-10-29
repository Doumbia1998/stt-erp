-- Module Caisse : caisse principale (encaissements des clients) et caisse des
-- dépenses (paiement des bons de caisse), virements entre les deux et clôtures.

-- Journal comptable de chaque caisse (choisi par la Direction).
CREATE TABLE caisses (
  code TEXT PRIMARY KEY CHECK (code IN ('Principale', 'Dépenses')),
  journal_code TEXT REFERENCES journaux (code) ON UPDATE CASCADE ON DELETE SET NULL,
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO caisses (code, journal_code) VALUES
  ('Principale', NULL),
  ('Dépenses', (SELECT code FROM journaux WHERE code = 'CAD'));

-- Numéros des reçus de caisse (RC-00001…), propres aux encaissements.
CREATE SEQUENCE recus_caisse_seq;

CREATE TABLE caisse_mouvements (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('Encaissement', 'Paiement bon', 'Approvisionnement', 'Reversement')),
  date DATE NOT NULL,
  montant NUMERIC(15, 2) NOT NULL CHECK (montant > 0),
  recu_numero BIGINT UNIQUE,
  -- Encaissement : dossier et règlement client créé dans le dossier.
  dossier_id TEXT REFERENCES dossiers (id) ON DELETE CASCADE,
  operation_uid TEXT,
  -- « Payé » (solde de la facture) ou « Commencement » (paiement partiel).
  statut_reglement TEXT NOT NULL DEFAULT '',
  mode_paiement TEXT NOT NULL DEFAULT '',
  bon_id TEXT UNIQUE REFERENCES bons_caisse (id),
  -- Virements : réception par la caisse de destination.
  receptionne_le DATE,
  receptionne_par TEXT NOT NULL DEFAULT '',
  observations TEXT NOT NULL DEFAULT '',
  auteur TEXT NOT NULL DEFAULT '',
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX caisse_mouvements_date ON caisse_mouvements (date);

-- Clôture journalière : plus aucun mouvement de cette caisse à cette date.
CREATE TABLE caisse_clotures (
  caisse TEXT NOT NULL CHECK (caisse IN ('Principale', 'Dépenses')),
  date DATE NOT NULL,
  recettes NUMERIC(15, 2) NOT NULL DEFAULT 0,
  depenses NUMERIC(15, 2) NOT NULL DEFAULT 0,
  solde NUMERIC(15, 2) NOT NULL DEFAULT 0,
  auteur TEXT NOT NULL DEFAULT '',
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (caisse, date)
);

-- Nouveau module « Caisse » dans la barre du haut : ouvert aux administrateurs.
UPDATE utilisateurs
SET modules = modules || ARRAY['Caisse']
WHERE role = 'Administrateur' AND NOT ('Caisse' = ANY (modules));
