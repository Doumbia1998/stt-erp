const crypto = require('node:crypto');
const express = require('express');
const { nextSubAccount } = require('../accounts');
const { withTransaction } = require('../db');
const { badRequest, conflict, notFound } = require('../errors');
const {
  ADMIN_ROLE,
  MODULES,
  MIN_PASSWORD_LENGTH,
  hashPassword,
  publicUser,
  requireAdmin,
  requireModule,
} = require('../auth');
const {
  text,
  optionalRef,
  amount,
  integer,
  bool,
  list,
  photo,
  frDateToSql,
  sqlDateToFr,
} = require('../format');

// --- Conversions ligne SQL -> JSON attendu par l'ERP ---

const clientJson = (r) => ({
  id: r.id,
  nom: r.nom,
  telephone: r.telephone,
  societe: r.societe,
  adresse: r.adresse,
  email: r.email,
  rccm: r.rccm,
  soldeInitial: r.solde_initial,
  assujettiTva: r.assujetti_tva,
  compteComptable: r.compte_comptable ?? '',
});

const vehiculeJson = (v) => ({
  id: v.id,
  plaque: v.plaque,
  chauffeur: v.chauffeur,
  telephone: v.telephone,
});

const prestataireJson = (r, vehicules = []) => ({
  vehicules: vehicules.map(vehiculeJson),
  id: r.id,
  entreprise: r.entreprise,
  type: r.type,
  pays: r.pays,
  villePort: r.ville_port,
  contact: r.contact,
  telephone: r.telephone,
  email: r.email,
  services: r.services,
  adresse: r.adresse,
  rccm: r.rccm,
  nombreVehicules: r.nombre_vehicules,
  soldeInitial: r.solde_initial,
  compteComptable: r.compte_comptable ?? '',
});

const compteJson = (r) => ({
  id: r.id,
  code: r.code,
  libelle: r.libelle,
  nature: r.nature,
  tiersId: r.tiers_id,
  soldeInitial: r.solde_initial,
  assujettiTva: r.assujetti_tva,
});

const journalJson = (r) => ({
  code: r.code,
  intitule: r.intitule,
  type: r.type,
  compteTresorerie: r.compte_tresorerie ?? '',
});

const modeReglementJson = (r) => ({
  id: r.id,
  intitule: r.intitule,
  type: r.type,
  journalClient: r.journal_client ?? '',
  journalFournisseur: r.journal_fournisseur ?? '',
  compteTresorerie: r.compte_tresorerie ?? '',
});

const typeFraisJson = (r) => ({
  id: r.id,
  numero: Number(r.numero),
  libelle: r.libelle,
  montant: r.montant,
  compteGeneral: r.compte_general ?? '',
  compte: r.compte ?? '',
});

const voyageJson = (r) => ({
  id: r.id,
  dossierId: r.dossier_id,
  plaque: r.plaque,
  chauffeur: r.chauffeur,
  origine: r.origine,
  destination: r.destination,
  depart: sqlDateToFr(r.depart),
  arriveePrevue: sqlDateToFr(r.arrivee_prevue),
  statut: r.statut,
});

const id = (req) => text(req.params, 'id', { required: true, max: 100 });

// Rattache le compte comptable au tiers (et détache l'ancien compte s'il a changé).
async function linkTiersAccount(client, tiersId, previousCode, newCode) {
  if (previousCode && previousCode !== newCode) {
    await client.query(
      'UPDATE plan_comptable SET tiers_id = NULL WHERE code = $1 AND tiers_id = $2',
      [previousCode, tiersId],
    );
  }
  if (newCode) {
    await client.query(
      'UPDATE plan_comptable SET tiers_id = $2 WHERE code = $1 AND tiers_id IS NULL',
      [newCode, tiersId],
    );
  }
}

function referentielsRouter(pool) {
  const router = express.Router();

  router.put('/clients/:id', requireModule('Transitaire', 'Transport'), async (req, res, next) => {
    try {
      const b = req.body;
      const values = [
        id(req),
        text(b, 'nom', { required: true }),
        text(b, 'telephone'),
        text(b, 'societe'),
        text(b, 'adresse'),
        text(b, 'email'),
        text(b, 'rccm'),
        amount(b, 'soldeInitial', { min: 0 }),
        bool(b, 'assujettiTva'),
        optionalRef(b, 'compteComptable'),
      ];
      const row = await withTransaction(pool, async (client) => {
        const previous = await client.query(
          'SELECT compte_comptable FROM clients WHERE id = $1 FOR UPDATE',
          [values[0]],
        );
        const { rows } = await client.query(
          `INSERT INTO clients (id, nom, telephone, societe, adresse, email, rccm,
             solde_initial, assujetti_tva, compte_comptable)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
           ON CONFLICT (id) DO UPDATE SET
             nom = EXCLUDED.nom, telephone = EXCLUDED.telephone,
             societe = EXCLUDED.societe, adresse = EXCLUDED.adresse,
             email = EXCLUDED.email, rccm = EXCLUDED.rccm,
             solde_initial = EXCLUDED.solde_initial,
             assujetti_tva = EXCLUDED.assujetti_tva,
             compte_comptable = EXCLUDED.compte_comptable,
             modifie_le = now()
           RETURNING *`,
          values,
        );
        await linkTiersAccount(
          client,
          values[0],
          previous.rows[0]?.compte_comptable,
          values[9],
        );
        return rows[0];
      });
      res.json(clientJson(row));
    } catch (error) {
      next(error);
    }
  });

  router.put('/prestataires/:id', requireModule('Prestation', 'Transitaire', 'Transport'), async (req, res, next) => {
    try {
      const b = req.body;
      const values = [
        id(req),
        text(b, 'entreprise', { required: true }),
        text(b, 'type', { required: true }),
        text(b, 'pays'),
        text(b, 'villePort'),
        text(b, 'contact'),
        text(b, 'telephone'),
        text(b, 'email'),
        text(b, 'services'),
        text(b, 'adresse'),
        text(b, 'rccm'),
        integer(b, 'nombreVehicules'),
        amount(b, 'soldeInitial', { min: 0 }),
        optionalRef(b, 'compteComptable'),
      ];
      const row = await withTransaction(pool, async (client) => {
        const previous = await client.query(
          'SELECT compte_comptable FROM prestataires WHERE id = $1 FOR UPDATE',
          [values[0]],
        );
        const { rows } = await client.query(
          `INSERT INTO prestataires (id, entreprise, type, pays, ville_port, contact,
             telephone, email, services, adresse, rccm, nombre_vehicules,
             solde_initial, compte_comptable)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
           ON CONFLICT (id) DO UPDATE SET
             entreprise = EXCLUDED.entreprise, type = EXCLUDED.type,
             pays = EXCLUDED.pays, ville_port = EXCLUDED.ville_port,
             contact = EXCLUDED.contact, telephone = EXCLUDED.telephone,
             email = EXCLUDED.email, services = EXCLUDED.services,
             adresse = EXCLUDED.adresse, rccm = EXCLUDED.rccm,
             nombre_vehicules = EXCLUDED.nombre_vehicules,
             solde_initial = EXCLUDED.solde_initial,
             compte_comptable = EXCLUDED.compte_comptable,
             modifie_le = now()
           RETURNING *`,
          values,
        );
        await linkTiersAccount(
          client,
          values[0],
          previous.rows[0]?.compte_comptable,
          values[13],
        );
        // Camions du transporteur (remplacés à chaque enregistrement de la fiche).
        await client.query('DELETE FROM vehicules WHERE transporteur_id = $1', [values[0]]);
        const vehicules = [];
        for (const [position, v] of list(b, 'vehicules', { max: 500 }).entries()) {
          const plaque = text(v, 'plaque', { required: true, max: 30 }).toUpperCase();
          const { rows: saved } = await client.query(
            `INSERT INTO vehicules (id, transporteur_id, position, plaque, chauffeur, telephone)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
            [
              text(v, 'id', { required: true, max: 120 }),
              values[0],
              position,
              plaque,
              text(v, 'chauffeur', { max: 120 }),
              text(v, 'telephone', { max: 40 }),
            ],
          );
          vehicules.push(saved[0]);
        }
        return { row: rows[0], vehicules };
      });
      res.json(prestataireJson(row.row, row.vehicules));
    } catch (error) {
      next(error);
    }
  });

  router.put('/comptes/:id', requireModule('Comptabilité'), async (req, res, next) => {
    try {
      const b = req.body;
      // Le rattachement au tiers (tiers_id) est géré par les fiches client / prestataire.
      const { rows } = await pool.query(
        `INSERT INTO plan_comptable (id, code, libelle, nature, tiers_id, solde_initial, assujetti_tva)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (id) DO UPDATE SET
           code = EXCLUDED.code, libelle = EXCLUDED.libelle,
           nature = EXCLUDED.nature, solde_initial = EXCLUDED.solde_initial,
           assujetti_tva = EXCLUDED.assujetti_tva, modifie_le = now()
         RETURNING *`,
        [
          id(req),
          text(b, 'code', { required: true, max: 30 }),
          text(b, 'libelle', { required: true }),
          text(b, 'nature', { required: true }),
          optionalRef(b, 'tiersId'),
          amount(b, 'soldeInitial'),
          bool(b, 'assujettiTva'),
        ],
      );
      res.json(compteJson(rows[0]));
    } catch (error) {
      next(error);
    }
  });

  router.delete('/comptes/:id', requireModule('Comptabilité'), async (req, res, next) => {
    try {
      const { rows } = await pool.query(
        'SELECT tiers_id FROM plan_comptable WHERE id = $1',
        [id(req)],
      );
      if (rows.length === 0) throw notFound('Compte introuvable.');
      if (rows[0].tiers_id) {
        throw conflict('Ce compte est rattaché à un tiers et ne peut pas être supprimé.');
      }
      await pool.query('DELETE FROM plan_comptable WHERE id = $1', [id(req)]);
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  // :code est le code actuel du journal (il peut être renommé via le corps de la requête).
  router.put('/journaux/:code', requireModule('Comptabilité'), async (req, res, next) => {
    try {
      const b = req.body;
      const currentCode = text(req.params, 'code', { required: true, max: 30 });
      const values = [
        text(b, 'code', { required: true, max: 30 }),
        text(b, 'intitule', { required: true }),
        text(b, 'type', { required: true }),
        optionalRef(b, 'compteTresorerie'),
        currentCode,
      ];
      let { rows } = await pool.query(
        `UPDATE journaux SET code = $1, intitule = $2, type = $3,
           compte_tresorerie = $4, modifie_le = now()
         WHERE code = $5 RETURNING *`,
        values,
      );
      if (rows.length === 0) {
        if (currentCode !== values[0]) throw notFound('Journal introuvable.');
        ({ rows } = await pool.query(
          `INSERT INTO journaux (code, intitule, type, compte_tresorerie)
           VALUES ($1, $2, $3, $4) RETURNING *`,
          values.slice(0, 4),
        ));
      }
      res.json(journalJson(rows[0]));
    } catch (error) {
      next(error);
    }
  });

  router.put('/voyages/:id', requireModule('Transport'), async (req, res, next) => {
    try {
      const b = req.body;
      const { rows } = await pool.query(
        `INSERT INTO voyages (id, dossier_id, plaque, chauffeur, origine, destination,
           depart, arrivee_prevue, statut)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (id) DO UPDATE SET
           dossier_id = EXCLUDED.dossier_id, plaque = EXCLUDED.plaque,
           chauffeur = EXCLUDED.chauffeur, origine = EXCLUDED.origine,
           destination = EXCLUDED.destination, depart = EXCLUDED.depart,
           arrivee_prevue = EXCLUDED.arrivee_prevue, statut = EXCLUDED.statut,
           modifie_le = now()
         RETURNING *`,
        [
          id(req),
          text(b, 'dossierId', { required: true }),
          text(b, 'plaque', { required: true }),
          text(b, 'chauffeur', { required: true }),
          text(b, 'origine', { required: true }),
          text(b, 'destination', { required: true }),
          frDateToSql(b.depart, 'depart'),
          frDateToSql(b.arriveePrevue, 'arriveePrevue'),
          text(b, 'statut', { required: true }),
        ],
      );
      res.json(voyageJson(rows[0]));
    } catch (error) {
      next(error);
    }
  });

  router.put('/utilisateurs/:id', requireAdmin, async (req, res, next) => {
    try {
      const b = req.body;
      const userId = id(req);
      const modules = list(b, 'modules', { max: MODULES.length });
      if (modules.some((m) => !MODULES.includes(m))) {
        throw badRequest('Module inconnu dans les droits d’accès.');
      }
      const password = typeof b.motDePasse === 'string' ? b.motDePasse : '';
      if (password && password.length < MIN_PASSWORD_LENGTH) {
        throw badRequest(
          `Le mot de passe doit contenir au moins ${MIN_PASSWORD_LENGTH} caractères.`,
        );
      }
      const passwordHash = password ? await hashPassword(password) : null;
      const newPhoto = photo(b);
      const row = await withTransaction(pool, async (client) => {
        const values = [
          userId,
          text(b, 'nom', { required: true }),
          text(b, 'identifiant', { required: true, max: 60 }),
          text(b, 'role', { required: true }),
          [...new Set(modules)],
        ];
        let { rows } = await client.query(
          `UPDATE utilisateurs SET nom = $2, identifiant = $3, role = $4, modules = $5,
             mot_de_passe_hash = COALESCE($6, mot_de_passe_hash), modifie_le = now()
           WHERE id = $1 RETURNING *`,
          [...values, passwordHash],
        );
        if (rows.length === 0) {
          if (!passwordHash) {
            throw badRequest('Un mot de passe est obligatoire pour un nouvel utilisateur.');
          }
          ({ rows } = await client.query(
            `INSERT INTO utilisateurs (id, nom, identifiant, role, modules, mot_de_passe_hash)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
            [...values, passwordHash],
          ));
        } else if (passwordHash) {
          // Nouveau mot de passe : on ferme les autres sessions de cet utilisateur.
          await client.query(
            'DELETE FROM sessions WHERE utilisateur_id = $1 AND jeton_hash <> $2',
            [userId, req.tokenHash],
          );
        }
        if (newPhoto !== undefined) {
          ({ rows } = await client.query(
            'UPDATE utilisateurs SET photo = $2 WHERE id = $1 RETURNING *',
            [userId, newPhoto],
          ));
        }
        const admins = await client.query(
          'SELECT count(*)::int AS n FROM utilisateurs WHERE role = $1',
          [ADMIN_ROLE],
        );
        if (admins.rows[0].n === 0) {
          throw conflict('Il doit rester au moins un administrateur.');
        }
        return rows[0];
      });
      res.json(publicUser(row));
    } catch (error) {
      next(error);
    }
  });

  router.put('/modes-reglement/:id', requireModule('Comptabilité'), async (req, res, next) => {
    try {
      const b = req.body;
      const { rows } = await pool.query(
        `INSERT INTO modes_reglement (id, intitule, type, journal_client,
           journal_fournisseur, compte_tresorerie)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (id) DO UPDATE SET
           intitule = EXCLUDED.intitule, type = EXCLUDED.type,
           journal_client = EXCLUDED.journal_client,
           journal_fournisseur = EXCLUDED.journal_fournisseur,
           compte_tresorerie = EXCLUDED.compte_tresorerie, modifie_le = now()
         RETURNING *`,
        [
          id(req),
          text(b, 'intitule', { required: true, max: 80 }),
          text(b, 'type', { required: true, max: 40 }),
          optionalRef(b, 'journalClient'),
          optionalRef(b, 'journalFournisseur'),
          optionalRef(b, 'compteTresorerie'),
        ],
      );
      res.json(modeReglementJson(rows[0]));
    } catch (error) {
      next(error);
    }
  });

  router.delete('/modes-reglement/:id', requireModule('Comptabilité'), async (req, res, next) => {
    try {
      const { rowCount } = await pool.query('DELETE FROM modes_reglement WHERE id = $1', [id(req)]);
      if (rowCount === 0) throw notFound('Mode de règlement introuvable.');
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  // Type de frais : un sous-compte est créé sous le compte général choisi.
  router.put('/types-frais/:id', requireModule('Comptabilité', 'Transport'), async (req, res, next) => {
    try {
      const b = req.body;
      const typeId = id(req);
      const libelle = text(b, 'libelle', { required: true, max: 120 }).toUpperCase();
      const montant = amount(b, 'montant', { min: 0 });
      const general = optionalRef(b, 'compteGeneral');
      const result = await withTransaction(pool, async (client) => {
        const { rows: current } = await client.query(
          'SELECT * FROM types_frais WHERE id = $1 FOR UPDATE',
          [typeId],
        );
        const existing = current[0];
        let compte = existing?.compte ?? null;
        let created = null;
        if (!general) {
          compte = null;
        } else if (existing?.compte_general !== general || !compte) {
          const { rows: parent } = await client.query(
            'SELECT nature FROM plan_comptable WHERE code = $1',
            [general],
          );
          if (parent.length === 0) throw notFound('Compte général introuvable.');
          // Verrou : deux créations simultanées n'obtiennent pas le même numéro.
          await client.query('SELECT pg_advisory_xact_lock(424243)');
          const { rows: codes } = await client.query('SELECT code FROM plan_comptable');
          compte = nextSubAccount(general, codes.map((c) => c.code));
          const { rows } = await client.query(
            `INSERT INTO plan_comptable (id, code, libelle, nature)
             VALUES ($1, $2, $3, $4) RETURNING *`,
            [`compte-${crypto.randomUUID()}`, compte, libelle, parent[0].nature],
          );
          created = rows[0];
        } else {
          await client.query(
            'UPDATE plan_comptable SET libelle = $2, modifie_le = now() WHERE code = $1',
            [compte, libelle],
          );
        }
        const { rows } = await client.query(
          `INSERT INTO types_frais (id, libelle, montant, compte_general, compte)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (id) DO UPDATE SET
             libelle = EXCLUDED.libelle, montant = EXCLUDED.montant,
             compte_general = EXCLUDED.compte_general, compte = EXCLUDED.compte,
             modifie_le = now()
           RETURNING *`,
          [typeId, libelle, montant, general, compte],
        );
        return { type: typeFraisJson(rows[0]), compteCree: created && compteJson(created) };
      });
      res.json(result);
    } catch (error) {
      next(error);
    }
  });

  router.delete('/types-frais/:id', requireModule('Comptabilité', 'Transport'), async (req, res, next) => {
    try {
      const { rowCount } = await pool.query('DELETE FROM types_frais WHERE id = $1', [id(req)]);
      if (rowCount === 0) throw notFound('Type de frais introuvable.');
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  // Chaque utilisateur peut changer sa propre photo.
  router.put('/moi/photo', async (req, res, next) => {
    try {
      const newPhoto = photo(req.body);
      if (newPhoto === undefined) throw badRequest('Photo manquante.');
      const { rows } = await pool.query(
        'UPDATE utilisateurs SET photo = $2, modifie_le = now() WHERE id = $1 RETURNING *',
        [req.user.id, newPhoto],
      );
      res.json(publicUser(rows[0]));
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = {
  referentielsRouter,
  vehiculeJson,
  clientJson,
  prestataireJson,
  compteJson,
  journalJson,
  voyageJson,
  modeReglementJson,
  typeFraisJson,
};
