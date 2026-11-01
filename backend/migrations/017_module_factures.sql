-- Le module « Prestation » (factures clients, prestataires, transitaires,
-- transporteurs) est renommé « Factures » : les accès des utilisateurs suivent.
UPDATE utilisateurs
SET modules = array_replace(modules, 'Prestation', 'Factures')
WHERE 'Prestation' = ANY (modules);
