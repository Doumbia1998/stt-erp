-- « Dossier » devient un module de la barre du haut (il était dans Transport) :
-- ouvert aux administrateurs et à ceux qui avaient le module Transport.
UPDATE utilisateurs
SET modules = modules || ARRAY['Dossier']
WHERE (role = 'Administrateur' OR 'Transport' = ANY (modules))
  AND NOT ('Dossier' = ANY (modules));
