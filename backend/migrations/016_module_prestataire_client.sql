-- « Prestataire & Client » : nouveau module de la barre du haut qui regroupe les clients
-- (avant dans Transitaire) et les prestataires (avant dans Prestation).
UPDATE utilisateurs
SET modules = modules || ARRAY['Prestataire & Client']
WHERE (role = 'Administrateur' OR modules && ARRAY['Transitaire', 'Prestation'])
  AND NOT ('Prestataire & Client' = ANY (modules));
