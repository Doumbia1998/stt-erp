-- L'avance camion versée par le transitaire fait partie de sa facture :
-- montant = frais (transit, surestaries, volume, autres, péage) + avances camion.
UPDATE factures_transitaire f
SET montant = f.montant + a.avances
FROM (
  SELECT facture_id, SUM(avance_camion) AS avances
  FROM facture_transitaire_lignes
  GROUP BY facture_id
) a
WHERE a.facture_id = f.id AND a.avances > 0;
