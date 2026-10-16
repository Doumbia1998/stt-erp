-- Camions des transporteurs et factures transitaire regroupant plusieurs BL / dossiers.

CREATE TABLE vehicules (
  id TEXT PRIMARY KEY,
  transporteur_id TEXT NOT NULL REFERENCES prestataires (id) ON DELETE CASCADE,
  position INTEGER NOT NULL DEFAULT 0,
  plaque TEXT NOT NULL,
  chauffeur TEXT NOT NULL DEFAULT '',
  telephone TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX vehicules_plaque_unique ON vehicules (upper(replace(plaque, ' ', '')));
CREATE INDEX vehicules_transporteur ON vehicules (transporteur_id);

CREATE TABLE factures_transitaire (
  id TEXT PRIMARY KEY,
  numero BIGSERIAL UNIQUE,
  reference TEXT NOT NULL UNIQUE,
  transitaire_id TEXT REFERENCES prestataires (id),
  date_emission DATE NOT NULL,
  observations TEXT NOT NULL DEFAULT '',
  montant NUMERIC(15, 2) NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1,
  auteur TEXT NOT NULL DEFAULT '',
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX factures_transitaire_transitaire ON factures_transitaire (transitaire_id);

CREATE TABLE facture_transitaire_lignes (
  id BIGSERIAL PRIMARY KEY,
  facture_id TEXT NOT NULL REFERENCES factures_transitaire (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  dossier_id TEXT REFERENCES dossiers (id),
  bl TEXT NOT NULL DEFAULT '',
  numero_conteneur TEXT NOT NULL DEFAULT '',
  marchandise TEXT NOT NULL DEFAULT '',
  type_conteneur TEXT NOT NULL DEFAULT '',
  date_depart DATE,
  transporteur_id TEXT REFERENCES prestataires (id),
  plaque TEXT NOT NULL DEFAULT '',
  telephone_chauffeur TEXT NOT NULL DEFAULT '',
  frais_transit NUMERIC(15, 2) NOT NULL DEFAULT 0,
  surestaries_magasinage NUMERIC(15, 2) NOT NULL DEFAULT 0,
  volume_poids NUMERIC(15, 2) NOT NULL DEFAULT 0,
  autres_frais NUMERIC(15, 2) NOT NULL DEFAULT 0,
  frais_peage NUMERIC(15, 2) NOT NULL DEFAULT 0,
  montant_transport NUMERIC(15, 2) NOT NULL DEFAULT 0,
  avance_camion NUMERIC(15, 2) NOT NULL DEFAULT 0
);
CREATE INDEX facture_transitaire_lignes_facture ON facture_transitaire_lignes (facture_id);
-- Un conteneur d'un dossier n'est facturé qu'une seule fois.
CREATE UNIQUE INDEX facture_transitaire_lignes_conteneur
  ON facture_transitaire_lignes (dossier_id, upper(numero_conteneur))
  WHERE numero_conteneur <> '';

CREATE TABLE facture_transitaire_reglements (
  id BIGSERIAL PRIMARY KEY,
  facture_id TEXT NOT NULL REFERENCES factures_transitaire (id) ON DELETE CASCADE,
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

-- Reprise des factures transitaire existantes (une par dossier) dans le nouveau format.
INSERT INTO factures_transitaire (id, reference, transitaire_id, date_emission, observations, montant)
SELECT f.id, f.reference, COALESCE(d.transitaire_affecte_id, d.prestataire_id),
  COALESCE(f.date_emission, CURRENT_DATE), f.observations, f.montant
FROM factures f JOIN dossiers d ON d.id = f.dossier_id
WHERE f.type = 'forwarder' AND f.statut <> 'Brouillon';

INSERT INTO facture_transitaire_lignes (facture_id, position, dossier_id, bl, numero_conteneur,
  marchandise, type_conteneur, plaque, telephone_chauffeur, frais_transit,
  surestaries_magasinage, volume_poids, autres_frais, frais_peage, avance_camion)
SELECT l.facture_id, l.position, f.dossier_id, l.bl, l.numero_conteneur, l.marchandise,
  l.type_conteneur, l.plaque_vehicule, l.telephone_chauffeur, l.frais_transit,
  l.surestaries_magasinage, l.volume_poids, l.autres_frais, l.frais_peage, l.avance_camion
FROM facture_lignes l JOIN factures f ON f.id = l.facture_id
WHERE f.type = 'forwarder' AND f.statut <> 'Brouillon'
ON CONFLICT DO NOTHING;

INSERT INTO facture_transitaire_reglements (facture_id, uid, date, montant, code_journal,
  mode_paiement, numero_cheque, observations, auteur, saisi_le)
SELECT f.id, o.uid, o.date, o.montant, o.code_journal, o.mode_paiement, o.numero_cheque,
  o.observations, o.auteur, o.saisi_le
FROM dossier_operations o
JOIN factures f ON f.dossier_id = o.dossier_id AND f.type = 'forwarder' AND f.statut <> 'Brouillon'
WHERE o.categorie = 'Règlement Transitaire' AND o.type IN ('providerPayment', 'providerAdvance')
  AND o.montant > 0;

DELETE FROM dossier_operations o USING factures f
WHERE f.dossier_id = o.dossier_id AND f.type = 'forwarder' AND f.statut <> 'Brouillon'
  AND o.categorie = 'Règlement Transitaire' AND o.type IN ('providerPayment', 'providerAdvance');

DELETE FROM facture_lignes l USING factures f
WHERE f.id = l.facture_id AND f.type = 'forwarder';

UPDATE factures SET statut = 'Brouillon', montant = 0, date_emission = NULL,
  reference = 'FT-OLD-' || id, description = '', observations = ''
WHERE type = 'forwarder';
