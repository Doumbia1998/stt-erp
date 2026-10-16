-- Factures transporteur : un camion d'un transporteur, les conteneurs qu'il a transportés.

CREATE TABLE factures_transporteur (
  id TEXT PRIMARY KEY,
  numero BIGSERIAL UNIQUE,
  reference TEXT NOT NULL UNIQUE,
  transporteur_id TEXT REFERENCES prestataires (id),
  plaque TEXT NOT NULL DEFAULT '',
  date_emission DATE NOT NULL,
  observations TEXT NOT NULL DEFAULT '',
  montant NUMERIC(15, 2) NOT NULL DEFAULT 0,
  -- Avance déjà versée au camion, déduite du net à payer.
  avance NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (avance >= 0),
  -- Caisse ou banque qui a versé l'avance (pour la comptabilité).
  journal_avance TEXT REFERENCES journaux (code) ON UPDATE CASCADE,
  version INTEGER NOT NULL DEFAULT 1,
  auteur TEXT NOT NULL DEFAULT '',
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now(),
  modifie_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX factures_transporteur_transporteur ON factures_transporteur (transporteur_id);

CREATE TABLE facture_transporteur_lignes (
  id BIGSERIAL PRIMARY KEY,
  facture_id TEXT NOT NULL REFERENCES factures_transporteur (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  dossier_id TEXT REFERENCES dossiers (id),
  bl TEXT NOT NULL DEFAULT '',
  numero_conteneur TEXT NOT NULL DEFAULT '',
  montant NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (montant >= 0)
);
CREATE INDEX facture_transporteur_lignes_facture ON facture_transporteur_lignes (facture_id);
-- Un conteneur d'un dossier n'est facturé qu'une fois par les transporteurs.
CREATE UNIQUE INDEX facture_transporteur_lignes_conteneur
  ON facture_transporteur_lignes (dossier_id, upper(numero_conteneur))
  WHERE numero_conteneur <> '';

CREATE TABLE facture_transporteur_reglements (
  id BIGSERIAL PRIMARY KEY,
  facture_id TEXT NOT NULL REFERENCES factures_transporteur (id) ON DELETE CASCADE,
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

-- Reprise des factures transporteur créées par dossier avec l'ancien écran.
INSERT INTO factures_transporteur (id, reference, transporteur_id, plaque, date_emission,
  observations, montant, avance)
SELECT f.id, f.reference, COALESCE(d.transporteur_affecte_id, d.prestataire_id),
  COALESCE((SELECT l.plaque_vehicule FROM facture_lignes l WHERE l.facture_id = f.id
            AND l.plaque_vehicule <> '' ORDER BY l.position LIMIT 1), ''),
  COALESCE(f.date_emission, CURRENT_DATE), f.observations,
  COALESCE((SELECT sum(l.frais_transit + l.volume_poids + l.surestaries_magasinage
            + l.frais_peage + l.autres_frais) FROM facture_lignes l WHERE l.facture_id = f.id), f.montant),
  COALESCE((SELECT sum(l.avance_camion) FROM facture_lignes l WHERE l.facture_id = f.id), 0)
FROM factures f JOIN dossiers d ON d.id = f.dossier_id
WHERE f.type = 'carrier' AND f.statut <> 'Brouillon';

INSERT INTO facture_transporteur_lignes (facture_id, position, dossier_id, bl, numero_conteneur, montant)
SELECT l.facture_id, l.position, f.dossier_id, l.bl, l.numero_conteneur,
  l.frais_transit + l.volume_poids + l.surestaries_magasinage + l.frais_peage + l.autres_frais
FROM facture_lignes l JOIN factures f ON f.id = l.facture_id
WHERE f.type = 'carrier' AND f.statut <> 'Brouillon'
ON CONFLICT DO NOTHING;

INSERT INTO facture_transporteur_reglements (facture_id, uid, date, montant, code_journal,
  mode_paiement, numero_cheque, observations, auteur, saisi_le)
SELECT f.id, o.uid, o.date, o.montant, o.code_journal, o.mode_paiement, o.numero_cheque,
  o.observations, o.auteur, o.saisi_le
FROM dossier_operations o
JOIN factures f ON f.dossier_id = o.dossier_id AND f.type = 'carrier' AND f.statut <> 'Brouillon'
WHERE o.categorie = 'Règlement Transporteur' AND o.type IN ('providerPayment', 'providerAdvance')
  AND o.montant > 0;

DELETE FROM dossier_operations o USING factures f
WHERE f.dossier_id = o.dossier_id AND f.type = 'carrier' AND f.statut <> 'Brouillon'
  AND o.categorie = 'Règlement Transporteur' AND o.type IN ('providerPayment', 'providerAdvance');

DELETE FROM facture_lignes l USING factures f
WHERE f.id = l.facture_id AND f.type = 'carrier';

UPDATE factures SET statut = 'Brouillon', montant = 0, date_emission = NULL,
  reference = 'FTR-OLD-' || id, description = '', observations = ''
WHERE type = 'carrier';
