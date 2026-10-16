const express = require('express');
const { withTransaction } = require('../db');
const { badRequest } = require('../errors');
const { requireModule } = require('../auth');
const { frDateToSql, sqlDateToFr, list } = require('../format');

// Comptes par défaut (plan SYSCOHADA) quand un tiers n'a pas de compte propre.
const COMPTES = {
  clients: '411000',
  ventes: '706000',
  fournisseurs: '401000',
  achats: '601000',
  transitaires: '401200',
  fraisTransit: '601200',
  transport: '611000',
  avancesFournisseurs: '409000',
  charges: '638000',
  caisse: '571000',
};

// Journaux créés automatiquement s'ils n'existent pas encore.
const JOURNAUX = {
  ventes: { code: 'VEN', intitule: 'Journal des ventes', type: 'Ventes' },
  achats: { code: 'ACH', intitule: 'Journal des achats', type: 'Achats' },
  depenses: { code: 'CAD', intitule: 'Caisse dépenses', type: 'Caisse' },
  divers: { code: 'OD', intitule: 'Opérations diverses', type: 'Opérations diverses' },
};

const CATEGORIES = ['ventes', 'achats', 'reglements', 'depenses', 'transit', 'paie', 'avances'];

const PAYMENT_PARTNER = {
  'Règlement Transitaire': 'transitaire',
  'Règlement Transporteur': 'transporteur',
};

const round = (value) => Math.round(Number(value) * 100) / 100;

// Construit les écritures d'une période à partir des documents de gestion.
async function buildEntries(client, du, au, categories) {
  const wanted = new Set(categories);
  const entries = [];
  const ignored = [];
  const push = (entry) => {
    const lines = entry.lines.filter((l) => l.debit > 0 || l.credit > 0);
    const debit = round(lines.reduce((s, l) => s + l.debit, 0));
    const credit = round(lines.reduce((s, l) => s + l.credit, 0));
    if (lines.length === 0 || debit === 0) return;
    if (debit !== credit) throw new Error(`Écriture déséquilibrée : ${entry.source}`);
    entries.push({ ...entry, lines });
  };

  const journals = new Map(
    (await client.query('SELECT code, compte_tresorerie FROM journaux')).rows.map((j) => [
      j.code,
      j.compte_tresorerie,
    ]),
  );
  const treasuryOf = (code) => journals.get(code) || COMPTES.caisse;

  const { rows: dossiers } = await client.query(
    `SELECT d.id, d.num_dossier,
       c.nom AS client_nom, c.compte_comptable AS client_compte,
       p.entreprise AS presta_nom, p.compte_comptable AS presta_compte,
       t.entreprise AS transit_nom, t.compte_comptable AS transit_compte,
       r.entreprise AS transp_nom, r.compte_comptable AS transp_compte
     FROM dossiers d
     JOIN clients c ON c.id = d.client_id
     LEFT JOIN prestataires p ON p.id = d.prestataire_id
     LEFT JOIN prestataires t ON t.id = d.transitaire_affecte_id
     LEFT JOIN prestataires r ON r.id = d.transporteur_affecte_id`,
  );
  const byId = new Map(dossiers.map((d) => [d.id, d]));
  const partner = (d, which) => {
    if (which === 'transitaire' && d.transit_nom) {
      return { nom: d.transit_nom, compte: d.transit_compte || COMPTES.transitaires };
    }
    if (which === 'transporteur' && d.transp_nom) {
      return { nom: d.transp_nom, compte: d.transp_compte || COMPTES.fournisseurs };
    }
    return {
      nom: d.presta_nom || d.transit_nom || d.transp_nom || 'Fournisseur',
      compte:
        d.presta_compte ||
        (which === 'transitaire' ? COMPTES.transitaires : COMPTES.fournisseurs),
    };
  };

  // Factures validées.
  const { rows: invoices } = await client.query(
    `SELECT id, dossier_id, type, reference, montant, date_emission
     FROM factures
     WHERE statut = 'Clôturée' AND montant > 0 AND date_emission BETWEEN $1 AND $2`,
    [du, au],
  );
  for (const f of invoices) {
    const d = byId.get(f.dossier_id);
    const amount = round(f.montant);
    if (f.type === 'client' && wanted.has('ventes')) {
      push({
        journal: JOURNAUX.ventes.code,
        categorie: 'ventes',
        date: f.date_emission,
        piece: f.reference,
        libelle: `Facture ${f.reference} • ${d.client_nom}`,
        source: `facture:${f.id}`,
        lines: [
          { compte: d.client_compte || COMPTES.clients, libelle: d.client_nom, debit: amount, credit: 0 },
          { compte: COMPTES.ventes, libelle: `Dossier ${d.num_dossier}`, debit: 0, credit: amount },
        ],
      });
    } else if (f.type === 'forwarder' && wanted.has('transit')) {
      const t = partner(d, 'transitaire');
      push({
        journal: JOURNAUX.achats.code,
        categorie: 'transit',
        date: f.date_emission,
        piece: f.reference,
        libelle: `Frais de transit ${f.reference} • ${t.nom}`,
        source: `facture:${f.id}`,
        lines: [
          { compte: COMPTES.fraisTransit, libelle: `Dossier ${d.num_dossier}`, debit: amount, credit: 0 },
          { compte: t.compte, libelle: t.nom, debit: 0, credit: amount },
        ],
      });
    } else if ((f.type === 'provider' || f.type === 'carrier') && wanted.has('achats')) {
      const p = partner(d, f.type === 'carrier' ? 'transporteur' : 'prestataire');
      push({
        journal: JOURNAUX.achats.code,
        categorie: 'achats',
        date: f.date_emission,
        piece: f.reference,
        libelle: `Facture fournisseur ${f.reference} • ${p.nom}`,
        source: `facture:${f.id}`,
        lines: [
          { compte: COMPTES.achats, libelle: `Dossier ${d.num_dossier}`, debit: amount, credit: 0 },
          { compte: p.compte, libelle: p.nom, debit: 0, credit: amount },
        ],
      });
    }
  }

  // Factures transitaire (plusieurs BL / dossiers) et leurs règlements.
  const { rows: transitInvoices } = await client.query(
    `SELECT f.id, f.reference, f.montant, f.date_emission, p.entreprise, p.compte_comptable
     FROM factures_transitaire f LEFT JOIN prestataires p ON p.id = f.transitaire_id
     WHERE f.montant > 0 AND f.date_emission BETWEEN $1 AND $2`,
    [du, au],
  );
  if (wanted.has('transit')) {
    for (const f of transitInvoices) {
      const amount = round(f.montant);
      const nom = f.entreprise || 'Transitaire';
      push({
        journal: JOURNAUX.achats.code,
        categorie: 'transit',
        date: f.date_emission,
        piece: f.reference,
        libelle: `Frais de transit ${f.reference} • ${nom}`,
        source: `facture-transitaire:${f.id}`,
        lines: [
          { compte: COMPTES.fraisTransit, libelle: f.reference, debit: amount, credit: 0 },
          { compte: f.compte_comptable || COMPTES.transitaires, libelle: nom, debit: 0, credit: amount },
        ],
      });
    }
  }
  if (wanted.has('reglements')) {
    const { rows: transitPayments } = await client.query(
      `SELECT r.facture_id, r.uid, r.montant, r.date::date AS jour, r.code_journal,
         f.reference, p.entreprise, p.compte_comptable
       FROM facture_transitaire_reglements r
       JOIN factures_transitaire f ON f.id = r.facture_id
       LEFT JOIN prestataires p ON p.id = f.transitaire_id
       WHERE r.date::date BETWEEN $1 AND $2`,
      [du, au],
    );
    for (const r of transitPayments) {
      if (!r.code_journal) {
        ignored.push(`Règlement transitaire sans caisse (${r.reference})`);
        continue;
      }
      const amount = round(r.montant);
      const nom = r.entreprise || 'Transitaire';
      push({
        journal: r.code_journal,
        categorie: 'reglements',
        date: r.jour,
        piece: r.reference,
        libelle: `Règlement ${nom} • ${r.reference}`,
        source: `reglement-transitaire:${r.facture_id}:${r.uid}`,
        lines: [
          { compte: r.compte_comptable || COMPTES.transitaires, libelle: nom, debit: amount, credit: 0 },
          { compte: treasuryOf(r.code_journal), libelle: r.reference, debit: 0, credit: amount },
        ],
      });
    }
  }

  // Factures transporteur, avances camion et règlements des transporteurs.
  const { rows: carrierInvoices } = await client.query(
    `SELECT f.id, f.reference, f.montant, f.avance, f.journal_avance, f.plaque,
       f.date_emission, p.entreprise, p.compte_comptable
     FROM factures_transporteur f LEFT JOIN prestataires p ON p.id = f.transporteur_id
     WHERE f.montant > 0 AND f.date_emission BETWEEN $1 AND $2`,
    [du, au],
  );
  for (const f of carrierInvoices) {
    const nom = f.entreprise || 'Transporteur';
    const compte = f.compte_comptable || COMPTES.fournisseurs;
    if (wanted.has('achats')) {
      const amount = round(f.montant);
      push({
        journal: JOURNAUX.achats.code,
        categorie: 'achats',
        date: f.date_emission,
        piece: f.reference,
        libelle: `Transport ${f.reference} • ${nom}${f.plaque ? ` (${f.plaque})` : ''}`,
        source: `facture-transporteur:${f.id}`,
        lines: [
          { compte: COMPTES.transport, libelle: f.reference, debit: amount, credit: 0 },
          { compte, libelle: nom, debit: 0, credit: amount },
        ],
      });
    }
    if (wanted.has('avances') && f.avance > 0) {
      if (!f.journal_avance) {
        ignored.push(`Avance camion sans caisse (${f.reference})`);
      } else {
        const amount = round(f.avance);
        push({
          journal: f.journal_avance,
          categorie: 'avances',
          date: f.date_emission,
          piece: f.reference,
          libelle: `Avance camion ${f.plaque || ''} • ${nom}`,
          source: `avance-transporteur:${f.id}`,
          lines: [
            { compte, libelle: nom, debit: amount, credit: 0 },
            { compte: treasuryOf(f.journal_avance), libelle: f.reference, debit: 0, credit: amount },
          ],
        });
      }
    }
  }
  if (wanted.has('reglements')) {
    const { rows: carrierPayments } = await client.query(
      `SELECT r.facture_id, r.uid, r.montant, r.date::date AS jour, r.code_journal,
         f.reference, p.entreprise, p.compte_comptable
       FROM facture_transporteur_reglements r
       JOIN factures_transporteur f ON f.id = r.facture_id
       LEFT JOIN prestataires p ON p.id = f.transporteur_id
       WHERE r.date::date BETWEEN $1 AND $2`,
      [du, au],
    );
    for (const r of carrierPayments) {
      if (!r.code_journal) {
        ignored.push(`Règlement transporteur sans caisse (${r.reference})`);
        continue;
      }
      const amount = round(r.montant);
      const nom = r.entreprise || 'Transporteur';
      push({
        journal: r.code_journal,
        categorie: 'reglements',
        date: r.jour,
        piece: r.reference,
        libelle: `Règlement ${nom} • ${r.reference}`,
        source: `reglement-transporteur:${r.facture_id}:${r.uid}`,
        lines: [
          { compte: r.compte_comptable || COMPTES.fournisseurs, libelle: nom, debit: amount, credit: 0 },
          { compte: treasuryOf(r.code_journal), libelle: r.reference, debit: 0, credit: amount },
        ],
      });
    }
  }

  // Mouvements des dossiers (règlements, avances, factures complémentaires).
  const { rows: operations } = await client.query(
    `SELECT dossier_id, uid, type, titre, categorie, montant, date::date AS jour, code_journal
     FROM dossier_operations
     WHERE date::date BETWEEN $1 AND $2 AND montant > 0`,
    [du, au],
  );
  for (const o of operations) {
    const d = byId.get(o.dossier_id);
    const amount = round(o.montant);
    const source = `operation:${o.dossier_id}:${o.uid}`;
    const base = { date: o.jour, piece: d.num_dossier, source };
    if (o.type === 'clientPayment' && wanted.has('reglements')) {
      if (!o.code_journal) {
        ignored.push(`Règlement client sans caisse (${d.num_dossier})`);
        continue;
      }
      push({
        ...base,
        journal: o.code_journal,
        categorie: 'reglements',
        libelle: `Règlement ${d.client_nom} • ${o.titre}`,
        lines: [
          { compte: treasuryOf(o.code_journal), libelle: o.titre, debit: amount, credit: 0 },
          { compte: d.client_compte || COMPTES.clients, libelle: d.client_nom, debit: 0, credit: amount },
        ],
      });
    } else if (o.type === 'providerPayment' && wanted.has('reglements')) {
      if (!o.code_journal) {
        ignored.push(`Règlement fournisseur sans caisse (${d.num_dossier})`);
        continue;
      }
      const p = partner(d, PAYMENT_PARTNER[o.categorie] ?? 'prestataire');
      push({
        ...base,
        journal: o.code_journal,
        categorie: 'reglements',
        libelle: `Règlement ${p.nom} • ${o.titre}`,
        lines: [
          { compte: p.compte, libelle: p.nom, debit: amount, credit: 0 },
          { compte: treasuryOf(o.code_journal), libelle: o.titre, debit: 0, credit: amount },
        ],
      });
    } else if (o.type === 'providerAdvance' && wanted.has('avances')) {
      const journal = o.code_journal || JOURNAUX.divers.code;
      const p = partner(d, PAYMENT_PARTNER[o.categorie] ?? 'prestataire');
      push({
        ...base,
        journal,
        categorie: 'avances',
        libelle: `Avance ${p.nom} • ${o.titre}`,
        lines: [
          { compte: COMPTES.avancesFournisseurs, libelle: p.nom, debit: amount, credit: 0 },
          { compte: treasuryOf(journal), libelle: o.titre, debit: 0, credit: amount },
        ],
      });
    } else if (o.type === 'clientInvoice' && wanted.has('ventes')) {
      push({
        ...base,
        journal: JOURNAUX.ventes.code,
        categorie: 'ventes',
        libelle: `${o.titre} • ${d.client_nom}`,
        lines: [
          { compte: d.client_compte || COMPTES.clients, libelle: d.client_nom, debit: amount, credit: 0 },
          { compte: COMPTES.ventes, libelle: o.titre, debit: 0, credit: amount },
        ],
      });
    } else if (o.type === 'providerInvoice' && wanted.has('achats')) {
      const p = partner(d, 'prestataire');
      push({
        ...base,
        journal: JOURNAUX.achats.code,
        categorie: 'achats',
        libelle: `${o.titre} • ${p.nom}`,
        lines: [
          { compte: COMPTES.achats, libelle: o.titre, debit: amount, credit: 0 },
          { compte: p.compte, libelle: p.nom, debit: 0, credit: amount },
        ],
      });
    }
  }

  // Frais et dépenses des dossiers.
  if (wanted.has('depenses')) {
    const { rows: types } = await client.query(
      'SELECT lower(libelle) AS libelle, compte FROM types_frais WHERE compte IS NOT NULL',
    );
    const chargeOf = new Map(types.map((t) => [t.libelle, t.compte]));
    const { rows: expenses } = await client.query(
      `SELECT dossier_id, position, titre, categorie, montant, date::date AS jour
       FROM dossier_depenses WHERE date::date BETWEEN $1 AND $2 AND montant > 0`,
      [du, au],
    );
    for (const e of expenses) {
      const d = byId.get(e.dossier_id);
      const amount = round(e.montant);
      push({
        journal: JOURNAUX.depenses.code,
        categorie: 'depenses',
        date: e.jour,
        piece: d.num_dossier,
        libelle: `${e.titre}${e.categorie ? ` (${e.categorie})` : ''}`,
        source: `depense:${e.dossier_id}:${e.position}`,
        lines: [
          {
            compte: chargeOf.get((e.categorie || '').toLowerCase()) ?? COMPTES.charges,
            libelle: e.titre,
            debit: amount,
            credit: 0,
          },
          { compte: treasuryOf(JOURNAUX.depenses.code), libelle: e.titre, debit: 0, credit: amount },
        ],
      });
    }
  }

  if (wanted.has('paie')) ignored.push('Salaires / Paie : aucune donnée de paie dans la gestion.');
  return { entries, ignored };
}

async function runUpdate(client, { du, au, categories }, user) {
  for (const journal of Object.values(JOURNAUX)) {
    await client.query(
      `INSERT INTO journaux (code, intitule, type) VALUES ($1, $2, $3)
       ON CONFLICT (code) DO NOTHING`,
      [journal.code, journal.intitule, journal.type],
    );
  }
  // Remplace les écritures générées de la période pour les catégories choisies.
  await client.query(
    `DELETE FROM ecritures
     WHERE origine = 'gestion' AND date BETWEEN $1 AND $2 AND categorie = ANY($3)`,
    [du, au, categories],
  );
  const { entries, ignored } = await buildEntries(client, du, au, categories);
  for (const entry of entries) {
    // Une écriture déjà générée hors période (document redaté) est remplacée.
    await client.query(`DELETE FROM ecritures WHERE source = $1 AND origine = 'gestion'`, [
      entry.source,
    ]);
    const { rows } = await client.query(
      `INSERT INTO ecritures (journal_code, date, piece, libelle, categorie, source, auteur)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
      [entry.journal, entry.date, entry.piece, entry.libelle, entry.categorie, entry.source, user.nom],
    );
    for (const [position, line] of entry.lines.entries()) {
      await client.query(
        `INSERT INTO ecriture_lignes (ecriture_id, position, compte, libelle, debit, credit)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [rows[0].id, position, line.compte, line.libelle, line.debit, line.credit],
      );
    }
  }
  await client.query(
    `INSERT INTO mises_a_jour_comptables (du, au, categories, ecritures, auteur)
     VALUES ($1, $2, $3, $4, $5)`,
    [du, au, categories, entries.length, user.nom],
  );
  const summary = Object.fromEntries(
    categories.map((c) => {
      const selected = entries.filter((e) => e.categorie === c);
      return [
        c,
        {
          ecritures: selected.length,
          montant: round(selected.reduce((s, e) => s + e.lines.reduce((t, l) => t + l.debit, 0), 0)),
        },
      ];
    }),
  );
  return { ecritures: entries.length, categories: summary, ignores: ignored };
}

function comptabiliteRouter(pool) {
  const router = express.Router();
  router.use('/comptabilite', requireModule('Comptabilité'));

  router.post('/comptabilite/mise-a-jour', async (req, res, next) => {
    try {
      const du = frDateToSql(req.body?.du, 'du');
      const au = frDateToSql(req.body?.au, 'au');
      if (!du || !au) throw badRequest('Indiquez la période à déverser.');
      if (du > au) throw badRequest('La date de début doit précéder la date de fin.');
      const categories = list(req.body, 'categories', { max: CATEGORIES.length });
      if (categories.length === 0 || categories.some((c) => !CATEGORIES.includes(c))) {
        throw badRequest('Sélectionnez au moins une catégorie valide.');
      }
      const result = await withTransaction(pool, (client) =>
        runUpdate(client, { du, au, categories: [...new Set(categories)] }, req.user),
      );
      res.json(result);
    } catch (error) {
      next(error);
    }
  });

  // Synthèse par journal et par mois.
  router.get('/comptabilite/journaux', async (req, res, next) => {
    try {
      const year = Number(req.query.annee) || new Date().getFullYear();
      const { rows } = await pool.query(
        `SELECT e.journal_code, to_char(e.date, 'YYYY-MM') AS mois,
           count(DISTINCT e.id)::int AS ecritures,
           COALESCE(sum(l.debit), 0) AS debit, COALESCE(sum(l.credit), 0) AS credit
         FROM ecritures e JOIN ecriture_lignes l ON l.ecriture_id = e.id
         WHERE extract(year FROM e.date) = $1
         GROUP BY e.journal_code, mois ORDER BY mois, e.journal_code`,
        [year],
      );
      const last = await pool.query(
        `SELECT du, au, ecritures, auteur, to_char(cree_le AT TIME ZONE 'UTC', 'DD/MM/YYYY HH24:MI') AS le
         FROM mises_a_jour_comptables ORDER BY id DESC LIMIT 1`,
      );
      res.json({
        annee: year,
        periodes: rows.map((r) => ({
          journal: r.journal_code,
          mois: r.mois,
          ecritures: r.ecritures,
          debit: r.debit,
          credit: r.credit,
        })),
        derniereMiseAJour: last.rows[0]
          ? {
              du: sqlDateToFr(last.rows[0].du),
              au: sqlDateToFr(last.rows[0].au),
              ecritures: last.rows[0].ecritures,
              auteur: last.rows[0].auteur,
              le: last.rows[0].le,
            }
          : null,
      });
    } catch (error) {
      next(error);
    }
  });

  // Balance des comptes : mouvements débit / crédit par compte sur une période.
  router.get('/comptabilite/balance', async (req, res, next) => {
    try {
      const du = frDateToSql(req.query.du, 'du');
      const au = frDateToSql(req.query.au, 'au');
      if (!du || !au) throw badRequest('Indiquez la période de la balance.');
      const clean = (value) => (typeof value === 'string' && value.trim() ? value.trim() : null);
      const { rows } = await pool.query(
        `SELECT l.compte, COALESCE(p.libelle, '') AS intitule,
           sum(l.debit) AS debit, sum(l.credit) AS credit
         FROM ecriture_lignes l
         JOIN ecritures e ON e.id = l.ecriture_id
         LEFT JOIN plan_comptable p ON p.code = l.compte
         WHERE e.date BETWEEN $1 AND $2
           AND ($3::text IS NULL OR l.compte >= $3)
           AND ($4::text IS NULL OR l.compte <= $4)
           AND ($5::text IS NULL OR e.journal_code >= $5)
           AND ($6::text IS NULL OR e.journal_code <= $6)
         GROUP BY l.compte, p.libelle
         ORDER BY l.compte`,
        [
          du,
          au,
          clean(req.query.compteDu),
          clean(req.query.compteAu),
          clean(req.query.journalDu),
          clean(req.query.journalAu),
        ],
      );
      res.json(
        rows.map((r) => ({
          compte: r.compte,
          intitule: r.intitule,
          debit: r.debit,
          credit: r.credit,
          solde: round(r.debit - r.credit),
        })),
      );
    } catch (error) {
      next(error);
    }
  });

  // Écritures d'un journal pour un mois (YYYY-MM).
  router.get('/comptabilite/ecritures', async (req, res, next) => {
    try {
      const journal = String(req.query.journal ?? '');
      const month = String(req.query.mois ?? '');
      if (!journal || !/^\d{4}-\d{2}$/.test(month)) {
        throw badRequest('Journal et mois (AAAA-MM) obligatoires.');
      }
      const { rows } = await pool.query(
        `SELECT e.id, e.date, e.piece, e.libelle, e.categorie,
           l.position, l.compte, l.libelle AS ligne_libelle, l.debit, l.credit
         FROM ecritures e JOIN ecriture_lignes l ON l.ecriture_id = e.id
         WHERE e.journal_code = $1 AND to_char(e.date, 'YYYY-MM') = $2
         ORDER BY e.date, e.id, l.position`,
        [journal, month],
      );
      res.json(
        rows.map((r) => ({
          ecriture: Number(r.id),
          date: sqlDateToFr(r.date),
          piece: r.piece,
          libelle: r.libelle,
          categorie: r.categorie,
          compte: r.compte,
          libelleLigne: r.ligne_libelle,
          debit: r.debit,
          credit: r.credit,
        })),
      );
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = { comptabiliteRouter, COMPTES, CATEGORIES };
