// Accès aux données de l'ERP : l'API PostgreSQL en production, une version en mémoire pour les tests.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'models_json.dart';

class ErpBackendException implements Exception {
  final String message;
  final int? status;

  const ErpBackendException(this.message, {this.status});

  @override
  String toString() => message;
}

// Tout ce qui est chargé après la connexion.
class ErpData {
  final ErpUser user;
  final List<ErpUser> users;
  final List<Client> clients;
  final List<Prestataire> prestataires;
  final List<PlanAccount> comptes;
  final List<JournalCode> journaux;
  final List<Voyage> voyages;
  final List<TransitDossier> dossiers;
  final List<ModeReglement> modesReglement;
  final List<TypeFrais> typesFrais;
  final List<FactureTransitaire> facturesTransitaire;
  final List<FactureTransporteur> facturesTransporteur;

  const ErpData({
    required this.user,
    required this.users,
    required this.clients,
    required this.prestataires,
    required this.comptes,
    required this.journaux,
    required this.voyages,
    required this.dossiers,
    this.modesReglement = const [],
    this.typesFrais = const [],
    this.facturesTransitaire = const [],
    this.facturesTransporteur = const [],
  });
}

// Synthèse d'un journal comptable pour un mois.
class JournalPeriode {
  final String journal;
  // « AAAA-MM »
  final String mois;
  final int ecritures;
  final double debit;
  final double credit;

  const JournalPeriode({
    required this.journal,
    required this.mois,
    required this.ecritures,
    required this.debit,
    required this.credit,
  });
}

class JournauxSynthese {
  final List<JournalPeriode> periodes;
  final String derniereMiseAJour;

  const JournauxSynthese(this.periodes, this.derniereMiseAJour);
}

// Ligne de la balance des comptes.
class BalanceLigne {
  final String compte;
  final String intitule;
  final double debit;
  final double credit;
  final double solde;

  const BalanceLigne({
    required this.compte,
    required this.intitule,
    required this.debit,
    required this.credit,
    required this.solde,
  });
}

// Ligne d'écriture comptable.
class EcritureLigne {
  final int ecriture;
  final String date;
  final String piece;
  final String libelle;
  final String compte;
  final String libelleLigne;
  final double debit;
  final double credit;

  const EcritureLigne({
    required this.ecriture,
    required this.date,
    required this.piece,
    required this.libelle,
    required this.compte,
    required this.libelleLigne,
    required this.debit,
    required this.credit,
  });
}

// Résultat d'une mise à jour comptable : nombre d'écritures et montant par catégorie.
class MiseAJourResultat {
  final int ecritures;
  final Map<String, (int, double)> categories;
  final List<String> ignores;

  const MiseAJourResultat(this.ecritures, this.categories, this.ignores);
}

abstract class ErpBackend {
  // Vérifie l'identifiant et le mot de passe, puis charge toutes les données.
  Future<ErpData> login(String identifiant, String motDePasse);
  // Recharge toutes les données (bouton « Actualiser »).
  Future<ErpData> reload();
  Future<void> logout();

  Future<void> saveUser(ErpUser user);
  // Change la photo de l'utilisateur connecté (null pour la retirer).
  Future<void> saveMyPhoto(String? photo);
  Future<void> saveClient(Client client);
  Future<void> savePrestataire(Prestataire prestataire);
  Future<void> saveAccount(PlanAccount account);
  Future<void> deleteAccount(PlanAccount account);
  // [previousCode] : code actuel du journal s'il est renommé.
  Future<void> saveJournal(JournalCode journal, {String? previousCode});
  Future<void> saveVoyage(Voyage voyage);
  Future<void> saveModeReglement(ModeReglement mode);
  Future<void> deleteModeReglement(ModeReglement mode);
  // Enregistre le type de frais ; renvoie le sous-compte créé (ou null).
  Future<PlanAccount?> saveTypeFrais(TypeFrais type);
  Future<void> deleteTypeFrais(TypeFrais type);
  // Met à jour la version et le numéro de la facture après l'enregistrement.
  Future<void> saveFactureTransitaire(FactureTransitaire facture);
  Future<void> deleteFactureTransitaire(FactureTransitaire facture);
  Future<void> saveFactureTransporteur(FactureTransporteur facture);
  Future<void> deleteFactureTransporteur(FactureTransporteur facture);

  // Comptabilité générée depuis la gestion.
  Future<MiseAJourResultat> miseAJourComptable({
    required String du,
    required String au,
    required List<String> categories,
  });
  Future<JournauxSynthese> journauxComptables(int annee);
  Future<List<EcritureLigne>> ecritures(String journal, String mois);
  Future<List<BalanceLigne>> balanceComptes({
    required String du,
    required String au,
    String? compteDu,
    String? compteAu,
    String? journalDu,
    String? journalAu,
  });
  // Met à jour la version, l'ID et la saisie du dossier après l'enregistrement.
  Future<void> saveDossier(TransitDossier dossier);
  Future<void> deleteDossier(TransitDossier dossier);
}

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.stt-ml.com',
);

ErpBackend erpBackend = HttpErpBackend(_apiBaseUrl);

class HttpErpBackend implements ErpBackend {
  final String baseUrl;
  final http.Client _http;
  String? _token;

  HttpErpBackend(this.baseUrl, {http.Client? client})
    : _http = client ?? http.Client();

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final request = http.Request(method, Uri.parse('$baseUrl/api/v1$path'))
      ..headers['Content-Type'] = 'application/json';
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 30)),
      );
    } on TimeoutException {
      throw const ErpBackendException(
        'Le serveur ne répond pas. Vérifiez la connexion internet et réessayez.',
      );
    } catch (_) {
      throw const ErpBackendException(
        'Impossible de joindre le serveur. Vérifiez la connexion internet et réessayez.',
      );
    }
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 400) {
      final message = decoded is Map && decoded['error'] is String
          ? decoded['error'] as String
          : 'Erreur du serveur (${response.statusCode}).';
      throw ErpBackendException(message, status: response.statusCode);
    }
    return decoded;
  }

  String _segment(String value) => Uri.encodeComponent(value);

  @override
  Future<ErpData> login(String identifiant, String motDePasse) async {
    final session = await _send('POST', '/auth/connexion', {
      'identifiant': identifiant,
      'motDePasse': motDePasse,
    });
    _token = session['jeton'] as String;
    return reload();
  }

  @override
  Future<ErpData> reload() async {
    final json = await _send('GET', '/donnees') as Map<String, dynamic>;
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List).cast<Map<String, dynamic>>();

    final clients = rows('clients').map(clientFromJson).toList();
    final prestataires = rows('prestataires').map(prestataireFromJson).toList();
    final clientsById = {for (final c in clients) c.id: c};
    final prestatairesById = {for (final p in prestataires) p.id: p};
    return ErpData(
      user: erpUserFromJson(json['utilisateur'] as Map<String, dynamic>),
      users: rows('utilisateurs').map(erpUserFromJson).toList(),
      clients: clients,
      prestataires: prestataires,
      comptes: rows('comptes').map(planAccountFromJson).toList(),
      journaux: rows('journaux').map(journalFromJson).toList(),
      voyages: rows('voyages').map(voyageFromJson).toList(),
      modesReglement: ((json['modesReglement'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(modeReglementFromJson)
          .toList(),
      typesFrais: ((json['typesFrais'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(typeFraisFromJson)
          .toList(),
      facturesTransitaire: ((json['facturesTransitaire'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(factureTransitaireFromJson)
          .toList(),
      facturesTransporteur:
          ((json['facturesTransporteur'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()
              .map(factureTransporteurFromJson)
              .toList(),
      dossiers: [
        for (final dossier in rows('dossiers'))
          dossierFromJson(
            dossier,
            clients: clientsById,
            prestataires: prestatairesById,
          ),
      ],
    );
  }

  @override
  Future<void> logout() async {
    if (_token == null) return;
    try {
      await _send('POST', '/auth/deconnexion');
    } on ErpBackendException {
      // La session expirera d'elle-même côté serveur.
    } finally {
      _token = null;
    }
  }

  @override
  Future<void> saveUser(ErpUser user) =>
      _send('PUT', '/utilisateurs/${_segment(user.id)}', erpUserToJson(user));

  @override
  Future<void> saveMyPhoto(String? photo) =>
      _send('PUT', '/moi/photo', {'photo': photo});

  @override
  Future<void> saveClient(Client client) =>
      _send('PUT', '/clients/${_segment(client.id)}', clientToJson(client));

  @override
  Future<void> savePrestataire(Prestataire prestataire) => _send(
    'PUT',
    '/prestataires/${_segment(prestataire.id)}',
    prestataireToJson(prestataire),
  );

  @override
  Future<void> saveAccount(PlanAccount account) => _send(
    'PUT',
    '/comptes/${_segment(account.id)}',
    planAccountToJson(account),
  );

  @override
  Future<void> deleteAccount(PlanAccount account) =>
      _send('DELETE', '/comptes/${_segment(account.id)}');

  @override
  Future<void> saveJournal(JournalCode journal, {String? previousCode}) =>
      _send(
        'PUT',
        '/journaux/${_segment(previousCode ?? journal.code)}',
        journalToJson(journal),
      );

  @override
  Future<void> saveVoyage(Voyage voyage) =>
      _send('PUT', '/voyages/${_segment(voyage.id)}', voyageToJson(voyage));

  @override
  Future<void> saveModeReglement(ModeReglement mode) => _send(
    'PUT',
    '/modes-reglement/${_segment(mode.id)}',
    modeReglementToJson(mode),
  );

  @override
  Future<void> deleteModeReglement(ModeReglement mode) =>
      _send('DELETE', '/modes-reglement/${_segment(mode.id)}');

  @override
  Future<PlanAccount?> saveTypeFrais(TypeFrais type) async {
    final json =
        await _send(
              'PUT',
              '/types-frais/${_segment(type.id)}',
              typeFraisToJson(type),
            )
            as Map<String, dynamic>;
    final saved = typeFraisFromJson(json['type'] as Map<String, dynamic>);
    type
      ..numero = saved.numero
      ..libelle = saved.libelle
      ..compte = saved.compte;
    final created = json['compteCree'] as Map<String, dynamic>?;
    return created == null ? null : planAccountFromJson(created);
  }

  @override
  Future<void> deleteTypeFrais(TypeFrais type) =>
      _send('DELETE', '/types-frais/${_segment(type.id)}');

  @override
  Future<void> saveFactureTransitaire(FactureTransitaire facture) async {
    final result = await _send(
      'PUT',
      '/factures-transitaire/${_segment(facture.id)}',
      factureTransitaireToJson(facture),
    );
    facture
      ..version = (result['version'] as num).toInt()
      ..numero = (result['numero'] as num?)?.toInt() ?? facture.numero;
  }

  @override
  Future<void> deleteFactureTransitaire(FactureTransitaire facture) =>
      _send('DELETE', '/factures-transitaire/${_segment(facture.id)}');

  @override
  Future<void> saveFactureTransporteur(FactureTransporteur facture) async {
    final result = await _send(
      'PUT',
      '/factures-transporteur/${_segment(facture.id)}',
      factureTransporteurToJson(facture),
    );
    facture
      ..version = (result['version'] as num).toInt()
      ..numero = (result['numero'] as num?)?.toInt() ?? facture.numero;
  }

  @override
  Future<void> deleteFactureTransporteur(FactureTransporteur facture) =>
      _send('DELETE', '/factures-transporteur/${_segment(facture.id)}');

  @override
  Future<MiseAJourResultat> miseAJourComptable({
    required String du,
    required String au,
    required List<String> categories,
  }) async {
    final json =
        await _send('POST', '/comptabilite/mise-a-jour', {
              'du': du,
              'au': au,
              'categories': categories,
            })
            as Map<String, dynamic>;
    return MiseAJourResultat(
      (json['ecritures'] as num).toInt(),
      {
        for (final entry
            in (json['categories'] as Map<String, dynamic>).entries)
          entry.key: (
            ((entry.value as Map)['ecritures'] as num).toInt(),
            ((entry.value as Map)['montant'] as num).toDouble(),
          ),
      },
      ((json['ignores'] as List?) ?? const []).cast<String>(),
    );
  }

  @override
  Future<JournauxSynthese> journauxComptables(int annee) async {
    final json =
        await _send('GET', '/comptabilite/journaux?annee=$annee')
            as Map<String, dynamic>;
    final last = json['derniereMiseAJour'] as Map<String, dynamic>?;
    return JournauxSynthese(
      [
        for (final p in (json['periodes'] as List).cast<Map<String, dynamic>>())
          JournalPeriode(
            journal: p['journal'] as String,
            mois: p['mois'] as String,
            ecritures: (p['ecritures'] as num).toInt(),
            debit: (p['debit'] as num).toDouble(),
            credit: (p['credit'] as num).toDouble(),
          ),
      ],
      last == null
          ? ''
          : 'Dernière mise à jour le ${last['le']} par ${last['auteur']} '
                '(du ${last['du']} au ${last['au']}, ${last['ecritures']} écritures)',
    );
  }

  @override
  Future<List<BalanceLigne>> balanceComptes({
    required String du,
    required String au,
    String? compteDu,
    String? compteAu,
    String? journalDu,
    String? journalAu,
  }) async {
    final query = Uri(
      queryParameters: {
        'du': du,
        'au': au,
        'compteDu': ?compteDu,
        'compteAu': ?compteAu,
        'journalDu': ?journalDu,
        'journalAu': ?journalAu,
      },
    ).query;
    final rows = await _send('GET', '/comptabilite/balance?$query') as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        BalanceLigne(
          compte: r['compte'] as String? ?? '',
          intitule: r['intitule'] as String? ?? '',
          debit: (r['debit'] as num).toDouble(),
          credit: (r['credit'] as num).toDouble(),
          solde: (r['solde'] as num).toDouble(),
        ),
    ];
  }

  @override
  Future<List<EcritureLigne>> ecritures(String journal, String mois) async {
    final rows =
        await _send(
              'GET',
              '/comptabilite/ecritures?journal=${Uri.encodeQueryComponent(journal)}&mois=$mois',
            )
            as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        EcritureLigne(
          ecriture: (r['ecriture'] as num).toInt(),
          date: r['date'] as String? ?? '',
          piece: r['piece'] as String? ?? '',
          libelle: r['libelle'] as String? ?? '',
          compte: r['compte'] as String? ?? '',
          libelleLigne: r['libelleLigne'] as String? ?? '',
          debit: (r['debit'] as num).toDouble(),
          credit: (r['credit'] as num).toDouble(),
        ),
    ];
  }

  @override
  Future<void> saveDossier(TransitDossier dossier) async {
    final result = await _send(
      'PUT',
      '/dossiers/${_segment(dossier.id)}',
      dossierToJson(dossier),
    );
    dossier
      ..version = (result['version'] as num).toInt()
      ..numero = (result['numero'] as num?)?.toInt() ?? dossier.numero
      ..auteurSaisie = result['auteurSaisie'] as String? ?? dossier.auteurSaisie
      ..dateSaisie = result['dateSaisie'] as String? ?? dossier.dateSaisie;
  }

  @override
  Future<void> deleteDossier(TransitDossier dossier) =>
      _send('DELETE', '/dossiers/${_segment(dossier.id)}');
}

// Version sans serveur, utilisée par les tests automatiques.
class MemoryErpBackend implements ErpBackend {
  final List<ErpUser> users;
  final List<Client> clients = [];
  final List<Prestataire> prestataires = [];
  final List<PlanAccount> comptes = [];
  final List<JournalCode> journaux = [];
  final List<Voyage> voyages = [];
  final List<TransitDossier> dossiers = [];
  final List<ModeReglement> modesReglement = [];
  final List<TypeFrais> typesFrais = [];
  final List<FactureTransitaire> facturesTransitaire = [];
  final List<FactureTransporteur> facturesTransporteur = [];
  final Map<String, String> _passwords = {};

  MemoryErpBackend({String adminPassword = '1234'})
    : users = [
        ErpUser(
          id: 'admin',
          name: 'Administrateur',
          login: 'admin',
          password: '',
          role: 'Administrateur',
          accessModules: {
            'Gestion',
            'Prestation',
            'Recouvrement',
            'Transport',
            'Transitaire',
            'Comptabilité',
            'RH & Paie',
          },
        ),
      ] {
    _passwords['admin'] = adminPassword;
  }

  static void _upsert<T>(List<T> list, T item, bool Function(T) same) {
    final index = list.indexWhere(same);
    if (index < 0) {
      list.add(item);
    } else {
      list[index] = item;
    }
  }

  ErpUser? _user;

  @override
  Future<ErpData> login(String identifiant, String motDePasse) async {
    final key = identifiant.trim().toLowerCase();
    final user = users.where((u) => u.login.toLowerCase() == key).firstOrNull;
    if (user == null || _passwords[user.id] != motDePasse) {
      throw const ErpBackendException(
        'Identifiant ou mot de passe incorrect.',
        status: 401,
      );
    }
    _user = user;
    return reload();
  }

  @override
  Future<ErpData> reload() async {
    final user = _user!;
    return ErpData(
      user: user,
      users: user.role == 'Administrateur' ? [...users] : [],
      clients: [...clients],
      prestataires: [...prestataires],
      comptes: [...comptes],
      journaux: [...journaux],
      voyages: [...voyages],
      dossiers: [...dossiers],
      modesReglement: [...modesReglement],
      typesFrais: [...typesFrais],
      facturesTransitaire: [...facturesTransitaire],
      facturesTransporteur: [...facturesTransporteur],
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<void> saveUser(ErpUser user) async {
    if (user.password.isNotEmpty) _passwords[user.id] = user.password;
    _upsert(users, user, (u) => u.id == user.id);
  }

  @override
  Future<void> saveMyPhoto(String? photo) async {
    _user!.photo = photo;
  }

  @override
  Future<void> saveClient(Client client) async =>
      _upsert(clients, client, (c) => c.id == client.id);

  @override
  Future<void> savePrestataire(Prestataire prestataire) async =>
      _upsert(prestataires, prestataire, (p) => p.id == prestataire.id);

  @override
  Future<void> saveAccount(PlanAccount account) async =>
      _upsert(comptes, account, (a) => a.id == account.id);

  @override
  Future<void> deleteAccount(PlanAccount account) async =>
      comptes.removeWhere((a) => a.id == account.id);

  @override
  Future<void> saveJournal(JournalCode journal, {String? previousCode}) async =>
      _upsert(
        journaux,
        journal,
        (j) => j.code == (previousCode ?? journal.code),
      );

  @override
  Future<void> saveVoyage(Voyage voyage) async =>
      _upsert(voyages, voyage, (v) => v.id == voyage.id);

  @override
  Future<void> saveModeReglement(ModeReglement mode) async =>
      _upsert(modesReglement, mode, (m) => m.id == mode.id);

  @override
  Future<void> deleteModeReglement(ModeReglement mode) async =>
      modesReglement.removeWhere((m) => m.id == mode.id);

  @override
  Future<PlanAccount?> saveTypeFrais(TypeFrais type) async {
    type.libelle = type.libelle.toUpperCase();
    PlanAccount? created;
    final previous = typesFrais.where((t) => t.id == type.id).firstOrNull;
    if (type.compteGeneral.isEmpty) {
      type.compte = '';
    } else if (previous?.compteGeneral != type.compteGeneral ||
        type.compte.isEmpty) {
      type.compte = nextSubAccountCode(type.compteGeneral, [
        ...comptes.map((c) => c.code),
      ]);
      created = PlanAccount(
        id: newLocalId('compte'),
        code: type.compte,
        libelle: type.libelle,
        nature: 'Charge',
      );
      comptes.add(created);
    }
    if (type.numero == 0) type.numero = typesFrais.length + 1;
    _upsert(typesFrais, type, (t) => t.id == type.id);
    return created;
  }

  @override
  Future<void> deleteTypeFrais(TypeFrais type) async =>
      typesFrais.removeWhere((t) => t.id == type.id);

  @override
  Future<void> saveFactureTransitaire(FactureTransitaire facture) async {
    final taken = {
      for (final f in facturesTransitaire)
        if (f.id != facture.id)
          for (final l in f.lignes)
            if (l.numeroConteneur.isNotEmpty) l.cleConteneur,
    };
    if (facture.lignes.any((l) => taken.contains(l.cleConteneur))) {
      throw const ErpBackendException(
        'Un des conteneurs est déjà facturé dans une autre facture transitaire.',
        status: 409,
      );
    }
    facture.version += 1;
    if (facture.numero == 0) facture.numero = facturesTransitaire.length + 1;
    _upsert(facturesTransitaire, facture, (f) => f.id == facture.id);
  }

  @override
  Future<void> deleteFactureTransitaire(FactureTransitaire facture) async =>
      facturesTransitaire.removeWhere((f) => f.id == facture.id);

  @override
  Future<void> saveFactureTransporteur(FactureTransporteur facture) async {
    final taken = {
      for (final f in facturesTransporteur)
        if (f.id != facture.id)
          for (final l in f.lignes)
            if (l.numeroConteneur.isNotEmpty) l.cleConteneur,
    };
    if (facture.lignes.any((l) => taken.contains(l.cleConteneur))) {
      throw const ErpBackendException(
        'Un des conteneurs est déjà facturé dans une autre facture transporteur.',
        status: 409,
      );
    }
    facture.version += 1;
    if (facture.numero == 0) facture.numero = facturesTransporteur.length + 1;
    _upsert(facturesTransporteur, facture, (f) => f.id == facture.id);
  }

  @override
  Future<void> deleteFactureTransporteur(FactureTransporteur facture) async =>
      facturesTransporteur.removeWhere((f) => f.id == facture.id);

  // La version en mémoire n'a pas de comptabilité : rien à déverser.
  @override
  Future<MiseAJourResultat> miseAJourComptable({
    required String du,
    required String au,
    required List<String> categories,
  }) async => MiseAJourResultat(0, {for (final c in categories) c: (0, 0)}, []);

  @override
  Future<JournauxSynthese> journauxComptables(int annee) async =>
      const JournauxSynthese([], '');

  @override
  Future<List<EcritureLigne>> ecritures(String journal, String mois) async =>
      const [];

  @override
  Future<List<BalanceLigne>> balanceComptes({
    required String du,
    required String au,
    String? compteDu,
    String? compteAu,
    String? journalDu,
    String? journalAu,
  }) async => const [];

  @override
  Future<void> saveDossier(TransitDossier dossier) async {
    dossier.version += 1;
    if (dossier.numero == 0) {
      dossier
        ..numero = dossiers.length + 1
        ..auteurSaisie = 'Administrateur';
    }
    _upsert(dossiers, dossier, (d) => d.id == dossier.id);
  }

  @override
  Future<void> deleteDossier(TransitDossier dossier) async =>
      dossiers.removeWhere((d) => d.id == dossier.id);
}
