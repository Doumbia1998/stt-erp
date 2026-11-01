const express = require('express');
const { withTransaction } = require('../db');
const { badRequest, notFound } = require('../errors');
const { requireAdmin } = require('../auth');
const { text } = require('../format');

// Suppression des données de test, un élément à la fois, réservée à
// l'administrateur : l'élément est supprimé avec ce qui en dépend, même s'il
// est verrouillé en temps normal (règlements, paiement en caisse…).

async function supprimerDossier(client, id) {
  await client.query('DELETE FROM voyages WHERE dossier_id = $1', [id]);
  await client.query('DELETE FROM facture_transitaire_lignes WHERE dossier_id = $1', [id]);
  await client.query('DELETE FROM facture_transporteur_lignes WHERE dossier_id = $1', [id]);
  // Factures, mouvements, frais, conteneurs et reçus de caisse suivent (ON DELETE CASCADE).
  return (await client.query('DELETE FROM dossiers WHERE id = $1', [id])).rowCount;
}

const SUPPRESSIONS = {
  dossier: supprimerDossier,

  async client(client, id) {
    const { rows } = await client.query('SELECT id FROM dossiers WHERE client_id = $1', [id]);
    for (const d of rows) await supprimerDossier(client, d.id);
    await client.query('UPDATE plan_comptable SET tiers_id = NULL WHERE tiers_id = $1', [id]);
    return (await client.query('DELETE FROM clients WHERE id = $1', [id])).rowCount;
  },

  async prestataire(client, id) {
    for (const column of ['prestataire_id', 'transitaire_affecte_id', 'transporteur_affecte_id']) {
      await client.query(`UPDATE dossiers SET ${column} = NULL WHERE ${column} = $1`, [id]);
    }
    await client.query('DELETE FROM factures_transitaire WHERE transitaire_id = $1', [id]);
    await client.query('UPDATE facture_transitaire_lignes SET transporteur_id = NULL WHERE transporteur_id = $1', [id]);
    await client.query('DELETE FROM factures_transporteur WHERE transporteur_id = $1', [id]);
    await client.query('UPDATE plan_comptable SET tiers_id = NULL WHERE tiers_id = $1', [id]);
    return (await client.query('DELETE FROM prestataires WHERE id = $1', [id])).rowCount;
  },

  async 'facture-transitaire'(client, id) {
    return (await client.query('DELETE FROM factures_transitaire WHERE id = $1', [id])).rowCount;
  },

  async 'facture-transporteur'(client, id) {
    return (await client.query('DELETE FROM factures_transporteur WHERE id = $1', [id])).rowCount;
  },

  async 'facture-agent'(client, id) {
    return (await client.query('DELETE FROM factures_agent WHERE id = $1', [id])).rowCount;
  },

  async 'bon-caisse'(client, id) {
    await client.query('DELETE FROM caisse_mouvements WHERE bon_id = $1', [id]);
    return (await client.query('DELETE FROM bons_caisse WHERE id = $1', [id])).rowCount;
  },

  async 'mouvement-caisse'(client, id) {
    const { rows: [m] } = await client.query(
      'SELECT type, dossier_id, operation_uid FROM caisse_mouvements WHERE id = $1',
      [id],
    );
    if (!m) return 0;
    if (m.type === 'Encaissement' && m.dossier_id) {
      // Le règlement client créé par l'encaissement, ou ses imputations sur
      // d'autres dossiers du client.
      const { rows: ops } = await client.query(
        `DELETE FROM dossier_operations
         WHERE (dossier_id = $1 AND uid = $2) OR uid LIKE $3
         RETURNING dossier_id`,
        [m.dossier_id, m.operation_uid, `${id}-i%`],
      );
      const touches = [...new Set([m.dossier_id, ...ops.map((o) => o.dossier_id)])];
      await client.query(
        'UPDATE dossiers SET version = version + 1 WHERE id = ANY($1::text[])',
        [touches],
      );
    }
    return (await client.query('DELETE FROM caisse_mouvements WHERE id = $1', [id])).rowCount;
  },
};

function administrationRouter(pool) {
  const router = express.Router();
  router.delete('/administration/elements/:type/:id', requireAdmin, async (req, res, next) => {
    try {
      const type = text(req.params, 'type', { required: true, max: 40 });
      const id = text(req.params, 'id', { required: true, max: 120 });
      const supprimer = SUPPRESSIONS[type];
      if (!supprimer) throw badRequest('Type de donnée inconnu.');
      const n = await withTransaction(pool, (client) => supprimer(client, id));
      if (n === 0) throw notFound('Élément introuvable : il a peut-être déjà été supprimé.');
      res.status(204).end();
    } catch (error) {
      next(error);
    }
  });
  return router;
}

module.exports = { administrationRouter };
