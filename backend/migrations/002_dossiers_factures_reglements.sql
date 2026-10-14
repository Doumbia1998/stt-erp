-- Grille des dossiers, facturation et règlements détaillés.

-- Identifiant numérique affiché dans les grilles (colonne « ID »).
ALTER TABLE dossiers ADD COLUMN numero BIGSERIAL;
ALTER TABLE dossiers ADD CONSTRAINT dossiers_numero_key UNIQUE (numero);
ALTER TABLE dossiers ADD COLUMN auteur_saisie TEXT NOT NULL DEFAULT '';
ALTER TABLE dossiers ADD COLUMN date_livraison_souhaitee DATE;

ALTER TABLE dossier_conteneurs ADD COLUMN observation TEXT NOT NULL DEFAULT '';

ALTER TABLE factures ADD COLUMN numero BIGSERIAL;
ALTER TABLE factures ADD CONSTRAINT factures_numero_key UNIQUE (numero);
ALTER TABLE factures ADD COLUMN observations TEXT NOT NULL DEFAULT '';

ALTER TABLE facture_lignes ADD COLUMN telephone_chauffeur TEXT NOT NULL DEFAULT '';

-- Identifiant stable des mouvements : permet de supprimer un règlement précis.
ALTER TABLE dossier_operations ADD COLUMN uid TEXT;
UPDATE dossier_operations SET uid = 'op-' || id;
ALTER TABLE dossier_operations ALTER COLUMN uid SET NOT NULL;
ALTER TABLE dossier_operations ADD CONSTRAINT dossier_operations_uid_key UNIQUE (dossier_id, uid);
ALTER TABLE dossier_operations
  ADD COLUMN mode_paiement TEXT NOT NULL DEFAULT '',
  ADD COLUMN numero_cheque TEXT NOT NULL DEFAULT '',
  ADD COLUMN observations TEXT NOT NULL DEFAULT '',
  ADD COLUMN auteur TEXT NOT NULL DEFAULT '',
  ADD COLUMN saisi_le TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE dossier_depenses
  ADD COLUMN auteur TEXT NOT NULL DEFAULT '',
  ADD COLUMN saisi_le TIMESTAMPTZ NOT NULL DEFAULT now();
