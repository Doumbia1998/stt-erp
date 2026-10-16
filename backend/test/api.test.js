// Tests de bout en bout sur un vrai PostgreSQL temporaire (embedded-postgres).
const { after, before, test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createApp } = require('../src/app');
const { createPool } = require('../src/db');
const { migrate } = require('../src/migrate');
const { ensureInitialAdmin } = require('../src/auth');
const { startTestPostgres } = require('./postgres');

const PORT = 55000 + Math.floor(Math.random() * 5000);
let postgres;
let pool;
let server;
let baseUrl;
let token;

before(async () => {
  postgres = await startTestPostgres(PORT);
  pool = createPool(postgres.url);
  process.env.ADMIN_INITIAL_PASSWORD = 'motdepasse-admin';
  await migrate(pool, () => {});
  await migrate(pool, () => {}); // idempotent
  await ensureInitialAdmin(pool, () => {});
  server = createApp({ pool, corsOrigins: 'https://erp.stt-ml.com' }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  baseUrl = `http://127.0.0.1:${server.address().port}/api/v1`;
});

after(async () => {
  server?.close();
  await pool?.end();
  await postgres?.stop();
});

async function call(method, route, body, auth = token) {
  const response = await fetch(`${baseUrl}${route}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(auth ? { Authorization: `Bearer ${auth}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}

const emptyInvoice = (dossierId, kind, prefix) => ({
  id: `${dossierId}-${kind}`,
  reference: `${prefix}-STT-1`,
  description: '',
  montant: 0,
  statut: 'Brouillon',
  dateEmission: '',
  lignes: [],
});

const dossierBody = (overrides = {}) => ({
  numDossier: 'STT-1',
  numBL: 'BL-1',
  numLB: '',
  clientId: 'client-1',
  nbConteneurs: 1,
  dateCreation: '09/10/2026',
  dateDebut: '09/10/2026',
  dateFin: '-',
  dateArriveeBateau: '',
  statut: 'Ouvert',
  prestataireId: 'provider-1',
  conteneurs: [{ numero: 'MSKU1234567', type: '40 pieds', marchandise: 'Riz' }],
  factures: {
    client: emptyInvoice('d1', 'client', 'FC'),
    provider: emptyInvoice('d1', 'provider', 'FP'),
    forwarder: emptyInvoice('d1', 'forwarder', 'FT'),
    carrier: emptyInvoice('d1', 'carrier', 'FTR'),
  },
  operations: [],
  depenses: [],
  ...overrides,
});

test('login rejects wrong credentials and protects data routes', async () => {
  assert.equal((await call('GET', '/donnees', undefined, null)).status, 401);
  const wrong = await call('POST', '/auth/connexion', {
    identifiant: 'admin',
    motDePasse: 'faux',
  });
  assert.equal(wrong.status, 401);
  const ok = await call('POST', '/auth/connexion', {
    identifiant: ' ADMIN ',
    motDePasse: 'motdepasse-admin',
  });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.utilisateur.role, 'Administrateur');
  assert.equal(ok.body.utilisateur.modules.length, 7);
  token = ok.body.jeton;
});

test('referentials are saved and the account code cascades', async () => {
  for (const [id, code, nature] of [
    ['acc-1', '411001', 'Client'],
    ['acc-2', '401001', 'Fournisseur'],
    ['acc-3', '521001', 'Banque'],
  ]) {
    const saved = await call('PUT', `/comptes/${id}`, {
      code,
      libelle: `Compte ${code}`,
      nature,
    });
    assert.equal(saved.status, 200);
  }
  const duplicate = await call('PUT', '/comptes/acc-x', {
    code: '411001',
    libelle: 'Doublon',
    nature: 'Client',
  });
  assert.equal(duplicate.status, 409);

  assert.equal(
    (await call('PUT', '/clients/client-1', {
      nom: 'Client Test',
      telephone: '+223 70 00 00 00',
      soldeInitial: 0,
      assujettiTva: false,
      compteComptable: '411001',
    })).status,
    200,
  );
  assert.equal(
    (await call('PUT', '/prestataires/provider-1', {
      entreprise: 'Transport Dakar',
      type: 'Transporteur',
      pays: 'Sénégal',
      nombreVehicules: 3,
      soldeInitial: 0,
      compteComptable: '401001',
    })).status,
    200,
  );
  assert.equal(
    (await call('PUT', '/journaux/BQ', {
      code: 'BQ',
      intitule: 'Banque',
      type: 'Banque',
      compteTresorerie: '521001',
    })).status,
    200,
  );

  // Le compte client est rattaché au tiers et ne peut plus être supprimé.
  assert.equal((await call('DELETE', '/comptes/acc-1')).status, 409);

  // Renommer le code du compte met à jour le client qui l'utilise.
  await call('PUT', '/comptes/acc-1', {
    code: '411002',
    libelle: 'Client Test',
    nature: 'Client',
  });
  const data = await call('GET', '/donnees');
  assert.equal(data.body.clients[0].compteComptable, '411002');
  assert.equal(
    data.body.comptes.find((c) => c.id === 'acc-1').tiersId,
    'client-1',
  );
});

test('a dossier is saved with its invoices, movements and version', async () => {
  const created = await call('PUT', '/dossiers/d1', dossierBody());
  assert.equal(created.status, 200);
  assert.equal(created.body.version, 1);
  assert.equal(created.body.auteurSaisie, 'Administrateur');
  assert.ok(created.body.numero > 0);
  assert.match(created.body.dateSaisie, /^\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}$/);

  const factures = dossierBody().factures;
  factures.client = {
    ...factures.client,
    reference: 'FAC-STT-1026-0001',
    statut: 'Clôturée',
    montant: 100000,
    dateEmission: '10/10/2026',
    observations: 'Paiement à 30 jours',
    lignes: [{ description: 'Transport Bamako', quantite: 1, prixUnitaire: 100000 }],
  };
  const payment = {
    id: 'op-1',
    type: 'clientPayment',
    titre: 'Règlement client',
    montant: 100000,
    date: '10/10/2026 14:05',
    codeJournal: 'BQ',
    modePaiement: 'Chèque',
    numeroCheque: 'CHQ-001',
    observations: 'Solde',
  };
  const operations = [payment];
  const updated = await call(
    'PUT',
    '/dossiers/d1',
    dossierBody({ version: 1, factures, operations }),
  );
  assert.equal(updated.status, 200);
  assert.equal(updated.body.version, 2);

  // Version périmée : un autre utilisateur a modifié le dossier entre-temps.
  const stale = await call('PUT', '/dossiers/d1', dossierBody({ version: 1, factures, operations }));
  assert.equal(stale.status, 409);

  // Un règlement enregistré ne peut pas être modifié.
  const changed = await call(
    'PUT',
    '/dossiers/d1',
    dossierBody({ version: 2, factures, operations: [{ ...payment, montant: 1 }] }),
  );
  assert.equal(changed.status, 409);

  // Une facture déjà réglée ne peut plus être modifiée.
  const reopened = await call(
    'PUT',
    '/dossiers/d1',
    dossierBody({
      version: 2,
      operations,
      factures: { ...factures, client: { ...factures.client, montant: 1 } },
    }),
  );
  assert.equal(reopened.status, 409);

  let data = await call('GET', '/donnees');
  let dossier = data.body.dossiers[0];
  assert.equal(dossier.version, 2);
  assert.equal(dossier.dateFin, '-');
  assert.equal(dossier.conteneurs[0].numero, 'MSKU1234567');
  assert.equal(dossier.factures.client.reference, 'FAC-STT-1026-0001');
  assert.equal(dossier.factures.client.observations, 'Paiement à 30 jours');
  assert.equal(dossier.factures.client.dateEmission, '10/10/2026');
  assert.equal(dossier.factures.client.lignes[0].description, 'Transport Bamako');
  const { auteur, saisiLe, ...savedPayment } = dossier.operations[0];
  assert.deepEqual(savedPayment, { ...payment, categorie: '' });
  assert.equal(auteur, 'Administrateur');

  // Supprimer le règlement rend la facture de nouveau modifiable.
  const withoutPayment = await call('PUT', '/dossiers/d1', dossierBody({ version: 2, factures }));
  assert.equal(withoutPayment.status, 200);
  const corrected = await call(
    'PUT',
    '/dossiers/d1',
    dossierBody({
      version: 3,
      factures: { ...factures, client: { ...factures.client, montant: 90000 } },
    }),
  );
  assert.equal(corrected.status, 200);
  data = await call('GET', '/donnees');
  dossier = data.body.dossiers[0];
  assert.equal(dossier.operations.length, 0);
  assert.equal(dossier.factures.client.montant, 90000);

  // Un dossier facturé ne peut pas être supprimé ; un dossier vide, si.
  assert.equal((await call('DELETE', '/dossiers/d1')).status, 409);
  const emptyFactures = Object.fromEntries(
    Object.entries(dossierBody().factures).map(([kind, f]) => [
      kind,
      { ...f, id: `d3-${kind}`, reference: `${f.reference}-d3` },
    ]),
  );
  assert.equal(
    (await call('PUT', '/dossiers/d3', dossierBody({ numDossier: 'STT-3', factures: emptyFactures }))).status,
    200,
  );
  assert.equal((await call('DELETE', '/dossiers/d3')).status, 204);
  data = await call('GET', '/donnees');
  assert.equal(data.body.dossiers.length, 1);

  const invalidDate = await call(
    'PUT',
    '/dossiers/d2',
    dossierBody({ numDossier: 'STT-2', dateDebut: '31/02/2026' }),
  );
  assert.equal(invalidDate.status, 400);
});

test('voyages are saved with French dates', async () => {
  const saved = await call('PUT', '/voyages/v1', {
    dossierId: 'd1',
    plaque: 'AB 1234 MD',
    chauffeur: 'Chauffeur Test',
    origine: 'Dakar',
    destination: 'Bamako',
    depart: '12/10/2026',
    arriveePrevue: '15/10/2026',
    statut: 'Planifié',
  });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.arriveePrevue, '15/10/2026');
});

test('users are managed by the administrator with hashed passwords', async () => {
  const tooShort = await call('PUT', '/utilisateurs/u1', {
    nom: 'Comptable',
    identifiant: 'compta',
    role: 'Comptable',
    modules: ['Comptabilité'],
    motDePasse: 'court',
  });
  assert.equal(tooShort.status, 400);
  const created = await call('PUT', '/utilisateurs/u1', {
    nom: 'Comptable',
    identifiant: 'compta',
    role: 'Comptable',
    modules: ['Comptabilité'],
    motDePasse: 'compta-2026',
  });
  assert.equal(created.status, 200);
  assert.equal(created.body.motDePasse, undefined);

  const { rows } = await pool.query(
    "SELECT mot_de_passe_hash FROM utilisateurs WHERE id = 'u1'",
  );
  assert.notEqual(rows[0].mot_de_passe_hash, 'compta-2026');

  const login = await call('POST', '/auth/connexion', {
    identifiant: 'compta',
    motDePasse: 'compta-2026',
  });
  assert.equal(login.status, 200);
  const comptaToken = login.body.jeton;

  // Le comptable n'a pas accès au module Transport ni à la gestion des utilisateurs.
  assert.equal(
    (await call('PUT', '/voyages/v2', { dossierId: 'd1' }, comptaToken)).status,
    403,
  );
  assert.equal(
    (await call('PUT', '/utilisateurs/u1', { nom: 'x', identifiant: 'x', role: 'Administrateur' }, comptaToken)).status,
    403,
  );
  const data = await call('GET', '/donnees', undefined, comptaToken);
  assert.equal(data.body.utilisateurs.length, 0);

  // Photo de profil : chacun peut changer la sienne ; une image invalide est refusée.
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]).toString('base64');
  const ownPhoto = await call('PUT', '/moi/photo', { photo: jpeg }, comptaToken);
  assert.equal(ownPhoto.status, 200);
  assert.equal(ownPhoto.body.photo, jpeg);
  assert.equal(
    (await call('PUT', '/moi/photo', { photo: 'pas-une-image' }, comptaToken)).status,
    400,
  );
  assert.equal(
    (await call('PUT', '/moi/photo', { photo: Buffer.from('GIF89a').toString('base64') }, comptaToken)).status,
    400,
  );
  const me = await call('GET', '/donnees', undefined, comptaToken);
  assert.equal(me.body.utilisateur.photo, jpeg);

  // Modifier sans mot de passe conserve l'ancien.
  await call('PUT', '/utilisateurs/u1', {
    nom: 'Comptable principal',
    identifiant: 'compta',
    role: 'Comptable',
    modules: ['Comptabilité', 'Recouvrement'],
  });
  assert.equal(
    (await call('POST', '/auth/connexion', { identifiant: 'compta', motDePasse: 'compta-2026' })).status,
    200,
  );
  let users = await call('GET', '/donnees');
  assert.equal(users.body.utilisateurs.find((u) => u.id === 'u1').photo, jpeg);

  // L'administrateur peut retirer la photo d'un membre.
  const removed = await call('PUT', '/utilisateurs/u1', {
    nom: 'Comptable principal',
    identifiant: 'compta',
    role: 'Recouvreur',
    modules: ['Recouvrement'],
    photo: null,
  });
  assert.equal(removed.status, 200);
  assert.equal(removed.body.photo, null);
  assert.equal(removed.body.role, 'Recouvreur');

  // Le dernier administrateur ne peut pas perdre son rôle.
  const demote = await call('PUT', '/utilisateurs/admin', {
    nom: 'Administrateur',
    identifiant: 'admin',
    role: 'Comptable',
    modules: [],
  });
  assert.equal(demote.status, 409);

  assert.equal((await call('POST', '/auth/deconnexion', undefined, comptaToken)).status, 204);
  assert.equal((await call('GET', '/donnees', undefined, comptaToken)).status, 401);
});

test('repeated failures lock the login temporarily', async () => {
  for (let i = 0; i < 5; i++) {
    await call('POST', '/auth/connexion', { identifiant: 'bloque', motDePasse: 'x' });
  }
  const locked = await call('POST', '/auth/connexion', {
    identifiant: 'bloque',
    motDePasse: 'x',
  });
  assert.equal(locked.status, 429);
});

test('payment modes are linked to journals', async () => {
  const saved = await call('PUT', '/modes-reglement/mode-1', {
    intitule: 'VIREMENT BIM',
    type: 'Virement bancaire',
    journalClient: 'BQ',
    journalFournisseur: 'BQ',
    compteTresorerie: '521001',
  });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.journalFournisseur, 'BQ');
  const duplicate = await call('PUT', '/modes-reglement/mode-2', {
    intitule: 'virement bim',
    type: 'Virement bancaire',
  });
  assert.equal(duplicate.status, 409);
  const data = await call('GET', '/donnees');
  assert.equal(data.body.modesReglement[0].intitule, 'VIREMENT BIM');
  assert.equal((await call('DELETE', '/modes-reglement/mode-1')).status, 204);
});

test('the accounting update posts balanced entries without duplicates', async () => {
  const factures = Object.fromEntries(
    Object.entries(dossierBody().factures).map(([kind, f]) => [
      kind,
      { ...f, id: `d5-${kind}`, reference: `${f.reference}-d5` },
    ]),
  );
  factures.client = {
    ...factures.client,
    reference: 'FAC-STT-1026-0005',
    statut: 'Clôturée',
    montant: 120000,
    dateEmission: '12/10/2026',
    lignes: [{ description: 'Conteneur', quantite: 1, prixUnitaire: 120000 }],
  };
  factures.forwarder = {
    ...factures.forwarder,
    reference: 'FAC-TRS-1026-0005',
    statut: 'Clôturée',
    montant: 50000,
    dateEmission: '12/10/2026',
    lignes: [{ description: 'Transit', quantite: 1, prixUnitaire: 50000, fraisTransit: 50000 }],
  };
  const created = await call(
    'PUT',
    '/dossiers/d5',
    dossierBody({
      numDossier: 'STT-5',
      factures,
      operations: [
        {
          id: 'op-d5-1',
          type: 'clientPayment',
          titre: 'Règlement client',
          montant: 70000,
          date: '13/10/2026 09:00',
          codeJournal: 'BQ',
        },
        {
          id: 'op-d5-2',
          type: 'providerPayment',
          titre: 'Règlement transitaire',
          categorie: 'Règlement Transitaire',
          montant: 50000,
          date: '13/10/2026 10:00',
          codeJournal: 'BQ',
        },
      ],
      depenses: [
        { titre: 'Péage', categorie: 'Route', montant: 5000, date: '13/10/2026 11:00' },
      ],
    }),
  );
  assert.equal(created.status, 200);

  const body = {
    du: '01/10/2026',
    au: '31/10/2026',
    categories: ['ventes', 'achats', 'reglements', 'depenses', 'transit', 'paie', 'avances'],
  };
  const first = await call('POST', '/comptabilite/mise-a-jour', body);
  assert.equal(first.status, 200);
  assert.equal(first.body.categories.ventes.montant >= 120000, true);
  assert.equal(first.body.categories.reglements.ecritures, 2);
  assert.equal(first.body.categories.depenses.montant, 5000);
  assert.equal(first.body.categories.transit.montant, 50000);
  assert.ok(first.body.ignores.some((m) => m.includes('Paie')));

  const again = await call('POST', '/comptabilite/mise-a-jour', body);
  assert.equal(again.body.ecritures, first.body.ecritures);

  const journals = await call('GET', '/comptabilite/journaux?annee=2026');
  const ven = journals.body.periodes.find((p) => p.journal === 'VEN' && p.mois === '2026-10');
  assert.ok(ven);
  assert.equal(ven.debit, ven.credit);
  for (const periode of journals.body.periodes) assert.equal(periode.debit, periode.credit);
  assert.equal(journals.body.derniereMiseAJour.au, '31/10/2026');

  const sales = await call('GET', '/comptabilite/ecritures?journal=VEN&mois=2026-10');
  const invoiceLines = sales.body.filter((l) => l.piece === 'FAC-STT-1026-0005');
  assert.deepEqual(
    invoiceLines.map((l) => [l.compte, l.debit, l.credit]),
    [['411002', 120000, 0], ['706000', 0, 120000]],
  );
  const bank = await call('GET', '/comptabilite/ecritures?journal=BQ&mois=2026-10');
  // Encaissement client : débit du compte de trésorerie du journal BQ (521001).
  assert.ok(bank.body.some((l) => l.compte === '521001' && l.debit === 70000));
  // Sans transitaire affecté, le règlement va au compte du prestataire du dossier.
  assert.ok(bank.body.some((l) => l.compte === '401001' && l.debit === 50000));
});

test('fee types create their sub-account under the general account', async () => {
  assert.equal(
    (await call('PUT', '/comptes/acc-6588', {
      code: '65880000',
      libelle: 'Autres charges diverses',
      nature: 'Charge',
    })).status,
    200,
  );
  const amende = await call('PUT', '/types-frais/frais-1', {
    libelle: 'amende',
    montant: 0,
    compteGeneral: '65880000',
  });
  assert.equal(amende.status, 200);
  assert.equal(amende.body.type.libelle, 'AMENDE');
  assert.equal(amende.body.type.compte, '65880001');
  assert.equal(amende.body.compteCree.code, '65880001');
  assert.equal(amende.body.compteCree.nature, 'Charge');

  const douane = await call('PUT', '/types-frais/frais-2', {
    libelle: 'Droit de douane',
    montant: 25000,
    compteGeneral: '65880000',
  });
  assert.equal(douane.body.type.compte, '65880002');

  // Renommer sans changer de compte général garde le même sous-compte.
  const renamed = await call('PUT', '/types-frais/frais-1', {
    libelle: 'Amende police',
    montant: 0,
    compteGeneral: '65880000',
  });
  assert.equal(renamed.body.type.compte, '65880001');
  assert.equal(renamed.body.compteCree, null);
  assert.equal(
    (await call('PUT', '/types-frais/frais-3', { libelle: 'amende police', montant: 0 })).status,
    409,
  );

  const data = await call('GET', '/donnees');
  assert.equal(data.body.typesFrais.length, 2);
  assert.equal(
    data.body.comptes.find((c) => c.code === '65880001').libelle,
    'AMENDE POLICE',
  );

  // Une dépense de ce type est imputée sur son sous-compte.
  const dossier = (await call('GET', '/donnees')).body.dossiers.find((d) => d.id === 'd5');
  const saved = await call('PUT', '/dossiers/d5', {
    ...dossier,
    depenses: [
      ...dossier.depenses,
      { titre: 'Amende route', categorie: 'AMENDE POLICE', montant: 15000, date: '14/10/2026 08:00' },
    ],
  });
  assert.equal(saved.status, 200);
  await call('POST', '/comptabilite/mise-a-jour', {
    du: '01/10/2026',
    au: '31/10/2026',
    categories: ['depenses'],
  });
  const cad = await call('GET', '/comptabilite/ecritures?journal=CAD&mois=2026-10');
  assert.ok(cad.body.some((l) => l.compte === '65880001' && l.debit === 15000));
  assert.ok(cad.body.some((l) => l.compte === '638000' && l.debit === 5000));
});

test('carriers own trucks and transit invoices group several dossiers', async () => {
  const carrier = await call('PUT', '/prestataires/transp-1', {
    entreprise: 'SOSAF',
    type: 'Transporteur',
    vehicules: [
      { id: 'veh-1', plaque: 'ab 1234 md', chauffeur: 'Moussa', telephone: '70 00 00 01' },
      { id: 'veh-2', plaque: 'AC 5678 MD', chauffeur: 'Issa', telephone: '70 00 00 02' },
    ],
  });
  assert.equal(carrier.status, 200);
  assert.deepEqual(carrier.body.vehicules.map((v) => v.plaque), ['AB 1234 MD', 'AC 5678 MD']);
  const stolen = await call('PUT', '/prestataires/transp-2', {
    entreprise: 'STL',
    type: 'Transporteur',
    vehicules: [{ id: 'veh-3', plaque: 'AB1234MD' }],
  });
  assert.equal(stolen.status, 409);

  assert.equal(
    (await call('PUT', '/prestataires/transit-1', { entreprise: 'EAT - BOUARE', type: 'Transitaire' })).status,
    200,
  );
  const line = (dossierId, numero, transit) => ({
    dossierId,
    bl: 'BL-1',
    numeroConteneur: numero,
    marchandise: 'Riz',
    typeConteneur: '40 pieds',
    dateDepart: '15/10/2026',
    transporteurId: 'transp-1',
    plaque: 'AB 1234 MD',
    telephoneChauffeur: '70 00 00 01',
    fraisTransit: transit,
    fraisPeage: 5000,
    montantTransport: 300000,
    avanceCamion: 100000,
  });
  const invoice = {
    reference: 'FAC-TRS-1026-0101',
    transitaireId: 'transit-1',
    dateEmission: '16/10/2026',
    observations: 'Deux BL',
    lignes: [line('d1', 'MSKU1234567', 45000), line('d5', 'MSKU1234567', 50000)],
    reglements: [],
  };
  const created = await call('PUT', '/factures-transitaire/ft-1', invoice);
  assert.equal(created.status, 200);
  assert.equal(created.body.montant, 105000);
  assert.equal(created.body.version, 1);

  // Le même conteneur d'un dossier ne peut pas être facturé deux fois.
  const twice = await call('PUT', '/factures-transitaire/ft-2', {
    ...invoice,
    reference: 'FAC-TRS-1026-0102',
    lignes: [line('d1', 'msku1234567', 1000)],
  });
  assert.equal(twice.status, 409);

  const payment = {
    id: 'reg-1',
    date: '16/10/2026 15:00',
    montant: 60000,
    codeJournal: 'BQ',
    modePaiement: 'VIREMENT BIM',
  };
  const paid = await call('PUT', '/factures-transitaire/ft-1', {
    ...invoice,
    version: 1,
    reglements: [payment],
  });
  assert.equal(paid.status, 200);
  assert.equal(paid.body.version, 2);
  const changed = await call('PUT', '/factures-transitaire/ft-1', {
    ...invoice,
    version: 2,
    lignes: [line('d1', 'MSKU1234567', 1)],
    reglements: [payment],
  });
  assert.equal(changed.status, 409);
  const overpaid = await call('PUT', '/factures-transitaire/ft-1', {
    ...invoice,
    version: 2,
    reglements: [payment, { ...payment, id: 'reg-2', montant: 50000 }],
  });
  assert.equal(overpaid.status, 400);
  assert.equal((await call('DELETE', '/factures-transitaire/ft-1')).status, 409);

  const data = await call('GET', '/donnees');
  const saved = data.body.facturesTransitaire.find((f) => f.id === 'ft-1');
  assert.equal(saved.lignes.length, 2);
  assert.equal(saved.lignes[0].plaque, 'AB 1234 MD');
  assert.equal(saved.lignes[1].dossierId, 'd5');
  assert.equal(saved.reglements[0].montant, 60000);
  assert.equal(
    data.body.prestataires.find((p) => p.id === 'transp-1').vehicules[1].chauffeur,
    'Issa',
  );

  await call('POST', '/comptabilite/mise-a-jour', {
    du: '01/10/2026',
    au: '31/10/2026',
    categories: ['transit', 'reglements'],
  });
  const purchases = await call('GET', '/comptabilite/ecritures?journal=ACH&mois=2026-10');
  assert.ok(purchases.body.some((l) => l.piece === 'FAC-TRS-1026-0101' && l.debit === 105000));
  const bank = await call('GET', '/comptabilite/ecritures?journal=BQ&mois=2026-10');
  assert.ok(bank.body.some((l) => l.piece === 'FAC-TRS-1026-0101' && l.credit === 60000));
});

test('the trial balance sums each account and stays balanced', async () => {
  const balance = await call(
    'GET',
    '/comptabilite/balance?du=01/10/2026&au=31/10/2026',
  );
  assert.equal(balance.status, 200);
  assert.ok(balance.body.length > 0);
  const debit = balance.body.reduce((s, r) => s + r.debit, 0);
  const credit = balance.body.reduce((s, r) => s + r.credit, 0);
  assert.equal(Math.round(debit), Math.round(credit));
  const clients = balance.body.find((r) => r.compte === '411002');
  assert.equal(clients.intitule, 'Client Test');
  assert.equal(clients.solde, clients.debit - clients.credit);
  const only411 = await call(
    'GET',
    '/comptabilite/balance?du=01/10/2026&au=31/10/2026&compteDu=411&compteAu=411999',
  );
  assert.ok(only411.body.every((r) => r.compte.startsWith('411')));
  const onlyVen = await call(
    'GET',
    '/comptabilite/balance?du=01/10/2026&au=31/10/2026&journalDu=VEN&journalAu=VEN',
  );
  assert.ok(onlyVen.body.some((r) => r.compte === '706000'));
  assert.ok(onlyVen.body.every((r) => ['411002', '706000'].includes(r.compte)));
});

test('carrier invoices track the truck, the advance and payments', async () => {
  const invoice = {
    reference: 'FAC-TRP-1026-0001',
    transporteurId: 'transp-1',
    plaque: 'AB 1234 MD',
    dateEmission: '16/10/2026',
    observations: 'Voyage Dakar - Bamako',
    avance: 100000,
    journalAvance: 'BQ',
    lignes: [
      { dossierId: 'd1', bl: 'BL-1', numeroConteneur: 'MSKU1234567', montant: 300000 },
      { dossierId: 'd5', bl: 'BL-1', numeroConteneur: 'MSKU1234567', montant: 200000 },
    ],
    reglements: [],
  };
  const created = await call('PUT', '/factures-transporteur/ftp-1', invoice);
  assert.equal(created.status, 200);
  assert.equal(created.body.montant, 500000);
  const twice = await call('PUT', '/factures-transporteur/ftp-2', {
    ...invoice,
    reference: 'FAC-TRP-1026-0002',
    lignes: [invoice.lignes[0]],
  });
  assert.equal(twice.status, 409);
  const tooMuch = await call('PUT', '/factures-transporteur/ftp-1', {
    ...invoice,
    version: 1,
    reglements: [{ id: 'r1', date: '16/10/2026 16:00', montant: 450000, codeJournal: 'BQ' }],
  });
  assert.equal(tooMuch.status, 400);
  const paid = await call('PUT', '/factures-transporteur/ftp-1', {
    ...invoice,
    version: 1,
    reglements: [{ id: 'r1', date: '16/10/2026 16:00', montant: 400000, codeJournal: 'BQ' }],
  });
  assert.equal(paid.status, 200);
  const locked = await call('PUT', '/factures-transporteur/ftp-1', {
    ...invoice,
    version: 2,
    avance: 0,
    reglements: [{ id: 'r1', date: '16/10/2026 16:00', montant: 400000, codeJournal: 'BQ' }],
  });
  assert.equal(locked.status, 409);

  const data = await call('GET', '/donnees');
  const saved = data.body.facturesTransporteur.find((f) => f.id === 'ftp-1');
  assert.equal(saved.plaque, 'AB 1234 MD');
  assert.equal(saved.avance, 100000);
  assert.equal(saved.lignes.length, 2);
  assert.equal(saved.reglements[0].montant, 400000);

  await call('POST', '/comptabilite/mise-a-jour', {
    du: '01/10/2026',
    au: '31/10/2026',
    categories: ['achats', 'avances', 'reglements'],
  });
  const purchases = await call('GET', '/comptabilite/ecritures?journal=ACH&mois=2026-10');
  assert.ok(purchases.body.some((l) => l.compte === '611000' && l.debit === 500000));
  const bank = await call('GET', '/comptabilite/ecritures?journal=BQ&mois=2026-10');
  assert.ok(bank.body.some((l) => l.piece === 'FAC-TRP-1026-0001' && l.credit === 100000));
  assert.ok(bank.body.some((l) => l.piece === 'FAC-TRP-1026-0001' && l.credit === 400000));
});

test('a carrier invoice can carry an agreed total without containers', async () => {
  const created = await call('PUT', '/factures-transporteur/ftp-3', {
    reference: 'FAC-TRP-1026-0003',
    transporteurId: 'transp-1',
    plaque: 'AC 5678 MD',
    dateEmission: '16/10/2026',
    montant: 2400000,
    avance: 0,
    lignes: [],
    reglements: [],
  });
  assert.equal(created.status, 200);
  assert.equal(created.body.montant, 2400000);
  const empty = await call('PUT', '/factures-transporteur/ftp-4', {
    reference: 'FAC-TRP-1026-0004',
    transporteurId: 'transp-1',
    dateEmission: '16/10/2026',
    montant: 0,
    lignes: [],
  });
  assert.equal(empty.status, 400);
  const data = await call('GET', '/donnees');
  assert.equal(data.body.facturesTransporteur.find((f) => f.id === 'ftp-3').montant, 2400000);
});
