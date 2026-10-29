-- Saisie des journaux : lignes saisies à la main par le comptable, avec N° de
-- facture, référence et compte tiers (nom du client ou du fournisseur).
ALTER TABLE ecritures
  ADD COLUMN numero_facture TEXT NOT NULL DEFAULT '',
  ADD COLUMN reference TEXT NOT NULL DEFAULT '';
ALTER TABLE ecriture_lignes
  ADD COLUMN tiers TEXT NOT NULL DEFAULT '';
