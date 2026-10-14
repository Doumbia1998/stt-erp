-- Schéma initial de Sylla Transit ERP.
-- Les montants sont en FCFA (NUMERIC pour éviter les arrondis des flottants).

CREATE TABLE utilisateurs (
  id TEXT PRIMARY KEY,
  nom TEXT NOT NULL,
  identifiant TEXT NOT NULL,
  mot_de_passe_hash TEXT NOT NULL,
  role TEXT NOT NULL,
  modules TEXT[] NOT NULL DEFAULT '{}',
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX utilisateurs_identifiant_unique ON utilisateurs (lower(identifiant));

CREATE TABLE sessions (
  jeton_hash TEXT PRIMARY KEY,
  utilisateur_id TEXT NOT NULL REFERENCES utilisateurs (id) ON DELETE CASCADE,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  expire_le TIMESTAMPTZ NOT NULL
);
CREATE INDEX sessions_utilisateur ON sessions (utilisateur_id);

CREATE TABLE plan_comptable (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  libelle TEXT NOT NULL,
  nature TEXT NOT NULL,
  tiers_id TEXT,
  solde_initial NUMERIC(15, 2) NOT NULL DEFAULT 0,
  assujetti_tva BOOLEAN NOT NULL DEFAULT FALSE,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE clients (
  id TEXT PRIMARY KEY,
  nom TEXT NOT NULL,
  telephone TEXT NOT NULL DEFAULT '',
  societe TEXT NOT NULL DEFAULT '',
  adresse TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  rccm TEXT NOT NULL DEFAULT '',
  solde_initial NUMERIC(15, 2) NOT NULL DEFAULT 0,
  assujetti_tva BOOLEAN NOT NULL DEFAULT FALSE,
  compte_comptable TEXT REFERENCES plan_comptable (code) ON UPDATE CASCADE,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE prestataires (
  id TEXT PRIMARY KEY,
  entreprise TEXT NOT NULL,
  type TEXT NOT NULL,
  pays TEXT NOT NULL DEFAULT '',
  ville_port TEXT NOT NULL DEFAULT '',
  contact TEXT NOT NULL DEFAULT '',
  telephone TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  services TEXT NOT NULL DEFAULT '',
  adresse TEXT NOT NULL DEFAULT '',
  rccm TEXT NOT NULL DEFAULT '',
  nombre_vehicules INTEGER NOT NULL DEFAULT 0 CHECK (nombre_vehicules >= 0),
  solde_initial NUMERIC(15, 2) NOT NULL DEFAULT 0,
  compte_comptable TEXT REFERENCES plan_comptable (code) ON UPDATE CASCADE,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE journaux (
  code TEXT PRIMARY KEY,
  intitule TEXT NOT NULL,
  type TEXT NOT NULL,
  compte_tresorerie TEXT REFERENCES plan_comptable (code) ON UPDATE CASCADE,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE dossiers (
  id TEXT PRIMARY KEY,
  num_dossier TEXT NOT NULL UNIQUE,
  num_bl TEXT NOT NULL DEFAULT '',
  num_lb TEXT NOT NULL DEFAULT '',
  client_id TEXT NOT NULL REFERENCES clients (id),
  nb_conteneurs INTEGER NOT NULL DEFAULT 0,
  transitaire TEXT NOT NULL DEFAULT '',
  date_creation DATE,
  type_facturation TEXT NOT NULL DEFAULT '',
  priorite TEXT NOT NULL DEFAULT '',
  type_marchandise TEXT NOT NULL DEFAULT '',
  lieu_marchandise TEXT NOT NULL DEFAULT '',
  lieu_livraison TEXT NOT NULL DEFAULT '',
  date_arrivee_bateau DATE,
  description TEXT NOT NULL DEFAULT '',
  prestataire_id TEXT REFERENCES prestataires (id),
  transitaire_affecte_id TEXT REFERENCES prestataires (id),
  transporteur_affecte_id TEXT REFERENCES prestataires (id),
  date_debut DATE,
  date_fin DATE,
  statut TEXT NOT NULL DEFAULT 'Ouvert' CHECK (statut IN ('Ouvert', 'Clôturé')),
  version INTEGER NOT NULL DEFAULT 1,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX dossiers_client ON dossiers (client_id);

CREATE TABLE dossier_conteneurs (
  id BIGSERIAL PRIMARY KEY,
  dossier_id TEXT NOT NULL REFERENCES dossiers (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  numero TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL DEFAULT '',
  marchandise TEXT NOT NULL DEFAULT ''
);
CREATE INDEX dossier_conteneurs_dossier ON dossier_conteneurs (dossier_id);

CREATE TABLE factures (
  id TEXT PRIMARY KEY,
  dossier_id TEXT NOT NULL REFERENCES dossiers (id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('client', 'provider', 'forwarder', 'carrier')),
  reference TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  montant NUMERIC(15, 2) NOT NULL DEFAULT 0,
  statut TEXT NOT NULL DEFAULT 'Brouillon' CHECK (statut IN ('Brouillon', 'En cours', 'Clôturée')),
  date_emission DATE,
  UNIQUE (dossier_id, type)
);

CREATE TABLE facture_lignes (
  id BIGSERIAL PRIMARY KEY,
  facture_id TEXT NOT NULL REFERENCES factures (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  quantite NUMERIC(15, 3) NOT NULL DEFAULT 0,
  prix_unitaire NUMERIC(15, 2) NOT NULL DEFAULT 0,
  numero_conteneur TEXT NOT NULL DEFAULT '',
  bl TEXT NOT NULL DEFAULT '',
  marchandise TEXT NOT NULL DEFAULT '',
  type_conteneur TEXT NOT NULL DEFAULT '',
  frais_transit NUMERIC(15, 2) NOT NULL DEFAULT 0,
  volume_poids NUMERIC(15, 2) NOT NULL DEFAULT 0,
  surestaries_magasinage NUMERIC(15, 2) NOT NULL DEFAULT 0,
  frais_peage NUMERIC(15, 2) NOT NULL DEFAULT 0,
  autres_frais NUMERIC(15, 2) NOT NULL DEFAULT 0,
  avance_camion NUMERIC(15, 2) NOT NULL DEFAULT 0,
  plaque_vehicule TEXT NOT NULL DEFAULT ''
);
CREATE INDEX facture_lignes_facture ON facture_lignes (facture_id);

CREATE TABLE dossier_operations (
  id BIGSERIAL PRIMARY KEY,
  dossier_id TEXT NOT NULL REFERENCES dossiers (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  type TEXT NOT NULL CHECK (type IN (
    'expense', 'clientInvoice', 'clientPayment',
    'providerInvoice', 'providerAdvance', 'providerPayment'
  )),
  titre TEXT NOT NULL,
  categorie TEXT NOT NULL DEFAULT '',
  montant NUMERIC(15, 2) NOT NULL,
  date TIMESTAMP NOT NULL,
  code_journal TEXT REFERENCES journaux (code) ON UPDATE CASCADE
);
CREATE INDEX dossier_operations_dossier ON dossier_operations (dossier_id);

CREATE TABLE dossier_depenses (
  id BIGSERIAL PRIMARY KEY,
  dossier_id TEXT NOT NULL REFERENCES dossiers (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  titre TEXT NOT NULL,
  categorie TEXT NOT NULL DEFAULT '',
  montant NUMERIC(15, 2) NOT NULL,
  date TIMESTAMP NOT NULL
);
CREATE INDEX dossier_depenses_dossier ON dossier_depenses (dossier_id);

CREATE TABLE voyages (
  id TEXT PRIMARY KEY,
  dossier_id TEXT NOT NULL REFERENCES dossiers (id),
  plaque TEXT NOT NULL,
  chauffeur TEXT NOT NULL,
  origine TEXT NOT NULL,
  destination TEXT NOT NULL,
  depart DATE,
  arrivee_prevue DATE,
  statut TEXT NOT NULL,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX voyages_dossier ON voyages (dossier_id);
