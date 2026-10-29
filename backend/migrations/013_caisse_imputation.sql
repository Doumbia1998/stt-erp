-- Imputation des encaissements de la caisse par la comptabilité : la caissière
-- pointe le règlement, le comptable le répartit sur les factures du client.
ALTER TABLE caisse_mouvements
  ADD COLUMN impute_le DATE,
  ADD COLUMN impute_par TEXT NOT NULL DEFAULT '',
  ADD COLUMN imputations JSONB NOT NULL DEFAULT '[]';
