-- Photo de profil des utilisateurs (JPEG compressé côté ERP, encodé en base64).
ALTER TABLE utilisateurs ADD COLUMN photo TEXT;
