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

  const ErpData({
    required this.user,
    required this.users,
    required this.clients,
    required this.prestataires,
    required this.comptes,
    required this.journaux,
    required this.voyages,
    required this.dossiers,
  });
}

abstract class ErpBackend {
  // Vérifie l'identifiant et le mot de passe, puis charge toutes les données.
  Future<ErpData> login(String identifiant, String motDePasse);
  // Recharge toutes les données (bouton « Actualiser »).
  Future<ErpData> reload();
  Future<void> logout();

  Future<void> saveUser(ErpUser user);
  Future<void> saveClient(Client client);
  Future<void> savePrestataire(Prestataire prestataire);
  Future<void> saveAccount(PlanAccount account);
  Future<void> deleteAccount(PlanAccount account);
  // [previousCode] : code actuel du journal s'il est renommé.
  Future<void> saveJournal(JournalCode journal, {String? previousCode});
  Future<void> saveVoyage(Voyage voyage);
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
