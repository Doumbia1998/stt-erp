const express = require('express');
const { withTransaction } = require('../db');
const { badRequest, conflict, notFound } = require('../errors');
const { requireModule } = require('../auth');
const {
  text,
  optionalRef,
  amount,
  integer,
  list,
  frDateToSql,
  sqlDateToFr,
} = require('../format');

const CATEGORIES = ['Frais camion', 'Dépense administrative'];
const PROPRIETAIRES = ['', 'Transporteur', 'STT'];
const MODULES = ['Dépenses & Frais', 'Transport', 'Comptabilité'];
const round = (value) => Math.round(value * 100) / 100;
const saisieSql = (column) =>
  `to_char(${column} AT TIME ZONE 'UTC', 'DD/MM/YYYY HH24:MI')`;

async function loadBonsCaisse(db) {
  const [bons, lignes] = await Promise.all([
    db.query(`SELECT *, ${saisieSql('cree_le')} AS saisie FROM bons_caisse ORDER BY numero`),
    db.query('SELECT * FROM bon_caisse_lignes ORDER BY bon_id, position'),
  ]);
  const lignesBy = new Map();
  for (const l of lignes.rows) {
    if (!lignesBy.has(l.bon_id)) lignesBy.set(l.bon_id, []);
    lignesBy.get(l.bon_id).push(l);
  }
  return bons.rows.map((b) => ({
    id: b.id,
    numero: Number(b.numero),
    categorie: b.categorie,
    date: sqlDateToFr(b.date),
    codeJournal: b.code_journal ?? '',
    beneficiaire: b.beneficiaire,
    motif: b.motif,
    referenceManuelle: b.reference_manuelle,
    observations: b.observations,
    montant: b.montant,
    auteur: b.auteur,
    dateSaisie: b.saisie,
    version: b.version,
    lignes: (lignesBy.get(b.id) ?? []).map((l) => ({
      dossierId: l.dossier_id ?? '',
      plaque: l.plaque,
      proprietaire: l.proprietaire,
      transporteurId: l.transporteur_id ?? '',
      chauffeur: l.chauffeur,
      telephone: l.telephone,
      typeFraisId: l.type_frais_id ?? '',
      compte: l.compte ?? '',
      libelle: l.libelle,
      montant: l.montant,
    })),
  }));
}

function parseBon(b) {
  const categorie = text(b, 'categorie', { required: true });
  if (!CATEGORIES.includes(categorie)) throw badRequest('Catégorie de bon de caisse inconnue.');
  const date = frDateToSql(b.date, 'date');
  if (!date) throw badRequest('La date du bon de caisse est obligatoire.');
  const lignes = list(b, 'lignes', { max: 500 }).map((l) => {
    const proprietaire = text(l, 'proprietaire');
    if (!PROPRIETAIRES.includes(proprietaire)) throw badRequest('Propriétaire du camion inconnu.');
    return {
      dossierId: optionalRef(l, 'dossierId'),
      plaque: text(l, 'plaque', { max: 30 }).toUpperCase(),
      proprietaire,
      transporteurId: optionalRef(l, 'transporteurId'),
      chauffeur: text(l, 'chauffeur'),
      telephone: text(l, 'telephone'),
      typeFraisId: optionalRef(l, 'typeFraisId'),
      compte: optionalRef(l, 'compte'),
      libelle: text(l, 'libelle', { max: 500 }),
      montant: amount(l, 'montant', { min: 0.01 }),
    };
  });
  if (lignes.length === 0) throw badRequest('Le bon de caisse doit contenir au moins une ligne.');
  const motif = text(b, 'motif', { max: 2000 });
  if (categorie === 'Dépense administrative') {
    if (!motif) throw badRequest('Le motif de la dépense est obligatoire.');
    if (lignes.some((l) => !l.compte)) {
      throw badRequest('Chaque dépense administrative doit être reliée à un compte comptable.');
    }
  } else if (lignes.some((l) => !l.typeFraisId && !l.libelle)) {
    throw badRequest('Chaque frais doit avoir un type de frais.');
  }
  return {
    categorie,
    date,
    codeJournal: optionalRef(b, 'codeJournal'),
    beneficiaire: text(b, 'beneficiaire', { max: 500 }),
    motif,
    referenceManuelle: text(b, 'referenceManuelle', { max: 120 }),
    observations: text(b, 'observations', { max: 5000 }),
    version: b.version === undefined || b.version === null ? 0 : integer(b, 'version'),
    lignes,
    montant: round(lignes.reduce((s, l) => s + l.montant, 0)),
  };
}

// Un bon payé par la caisse des dépenses ne peut plus être modifié ni supprimé.
async function refuserSiPaye(db, id) {
  const { rows } = await db.query('SELECT 1 FROM caisse_mouvements WHERE bon_id = $1', [id]);
  if (rows.length > 0) {
    throw conflict('Ce bon de caisse est déjà payé par la caisse : il ne peut plus être modifié ni supprimé.');
  }
}

async function saveBon(client, id, bon, user) {
  const { rows } = await client.query('SELECT version FROM bons_caisse WHERE id = $1 FOR UPDATE', [id]);
  const existing = rows[0];
  if (existing) await refuserSiPaye(client, id);
  if (existing && existing.version !== bon.version) {
    throw conflict('Ce bon de caisse a été modifié par un autre utilisateur. Rechargez la page.');
  }
  // Le compte d'une ligne de frais vient de son type de frais quand il n'est pas saisi.
  const typeIds = [...new Set(bon.lignes.map((l) => l.typeFraisId).filter(Boolean))];
  const { rows: types } = await client.query(
    'SELECT id, libelle, compte FROM types_frais WHERE id = ANY($1::text[])',
    [typeIds],
  );
  const typeById = new Map(types.map((t) => [t.id, t]));
  for (const l of bon.lignes) {
    const type = l.typeFraisId ? typeById.get(l.typeFraisId) : null;
    if (l.typeFraisId && !type) throw badRequest('Type de frais introuvable.');
    if (!l.compte && type?.compte) l.compte = type.compte;
    if (!l.libelle && type) l.libelle = type.libelle;
  }
  let saved;
  if (existing) {
    ({ rows: [saved] } = await client.query(
      `UPDATE bons_caisse SET categorie = $2, date = $3, code_journal = $4, beneficiaire = $5,
         motif = $6, reference_manuelle = $7, observations = $8, montant = $9,
         version = version + 1, modifie_le = now()
       WHERE id = $1 RETURNING version, numero`,
      [id, bon.categorie, bon.date, bon.codeJournal, bon.beneficiaire, bon.motif,
        bon.referenceManuelle, bon.observations, bon.montant],
    ));
    await client.query('DELETE FROM bon_caisse_lignes WHERE bon_id = $1', [id]);
  } else {
    ({ rows: [saved] } = await client.query(
      `INSERT INTO bons_caisse (id, categorie, date, code_journal, beneficiaire, motif,
         reference_manuelle, observations, montant, auteur)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING version, numero`,
      [id, bon.categorie, bon.date, bon.codeJournal, bon.beneficiaire, bon.motif,
        bon.referenceManuelle, bon.observations, bon.montant, user.nom],
    ));
  }
  for (const [position, l] of bon.lignes.entries()) {
    await client.query(
      `INSERT INTO bon_caisse_lignes (bon_id, position, dossier_id, plaque, proprietaire,
         transporteur_id, chauffeur, telephone, type_frais_id, compte, libelle, montant)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
      [id, position, l.dossierId, l.plaque, l.proprietaire, l.transporteurId, l.chauffeur,
        l.telephone, l.typeFraisId, l.compte, l.libelle, l.montant],
    );
  }
  return {
    id,
    version: saved.version,
    numero: Number(saved.numero),
    montant: bon.montant,
    lignes: bon.lignes.map((l) => ({ compte: l.compte ?? '', libelle: l.libelle })),
  };
}

function bonsCaisseRouter(pool) {
  const router = express.Router();

  router.put('/bons-caisse/:id', requireModule(...MODULES), async (req, res, next) => {
    try {
      const id = text(req.params, 'id', { required: true, max: 120 });
      const bon = parseBon(req.body ?? {});
      res.json(await withTransaction(pool, (client) => saveBon(client, id, bon, req.user)));
    } catch (error) {
      next(error);
    }
  });

  router.delete('/bons-caisse/:id', requireModule(...MODULES), async (req, res, next) => {
    try {
      const id = text(req.params, 'id', { required: true, max: 120 });
      await refuserSiPaye(pool, id);
      const { rowCount } = await pool.query('DELETE FROM bons_caisse WHERE id = $1', [id]);
      if (rowCount === 0) throw notFound('Bon de caisse introuvable.');
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = { bonsCaisseRouter, loadBonsCaisse };
