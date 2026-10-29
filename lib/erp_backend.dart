// Accès aux données de l'ERP : l'API PostgreSQL en production, une version en mémoire pour les tests.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

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
  final List<AffectationVoyage> affectationsVoyage;
  final List<AgentVoyage> agentsVoyage;
  final List<FactureAgent> facturesAgent;
  final List<BonCaisse> bonsCaisse;
  final List<CaisseMouvement> caisseMouvements;
  final List<CaisseCloture> caisseClotures;
  final CaisseParametres? caisseParametres;

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
    this.affectationsVoyage = const [],
    this.agentsVoyage = const [],
    this.facturesAgent = const [],
    this.bonsCaisse = const [],
    this.caisseMouvements = const [],
    this.caisseClotures = const [],
    this.caisseParametres,
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

  // Voyages affectés aux modules Frontière, Bureau DD et Enquête.
  Future<void> saveAffectationVoyage(
    AffectationVoyage affectation, {
    bool valider = false,
  });
  Future<void> deleteAffectationVoyage(AffectationVoyage affectation);
  Future<String?> photoT1(AffectationVoyage affectation);
  Future<void> saveFactureAgent(FactureAgent facture);
  Future<void> deleteFactureAgent(FactureAgent facture);

  // Bons de caisse (frais des camions, dépenses administratives).
  Future<void> saveBonCaisse(BonCaisse bon);
  Future<void> deleteBonCaisse(BonCaisse bon);

  // Caisse : journaux des caisses (Direction), encaissements des clients,
  // paiement des bons, virements entre caisses et clôture du jour.
  Future<void> saveCaisseParametres(CaisseParametres parametres);
  // Ajoute le règlement client au dossier et renvoie le reçu de caisse.
  Future<CaisseMouvement> encaisser({
    required TransitDossier dossier,
    required String statut,
    required double montant,
    String modePaiement = '',
    String observations = '',
  });
  Future<CaisseMouvement> payerBonCaisse(BonCaisse bon);
  Future<CaisseMouvement> virementCaisse({
    required String type,
    required double montant,
    String observations = '',
  });
  Future<void> receptionnerVirement(CaisseMouvement virement);
  // Retire aussi le règlement client du dossier pour un encaissement.
  Future<void> annulerMouvementCaisse(
    CaisseMouvement mouvement, {
    TransitDossier? dossier,
  });
  Future<CaisseCloture> cloturerCaisse(String caisse);
  // Administrateur : rouvre la dernière clôture de la caisse.
  Future<void> rouvrirCaisse(String caisse);
  // Comptabilité : répartit un encaissement de la caisse sur les factures du client.
  Future<void> imputerEncaissement(
    CaisseMouvement mouvement, {
    required List<(TransitDossier, double)> imputations,
    required String codeJournal,
  });

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
      affectationsVoyage: ((json['affectationsVoyage'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(affectationVoyageFromJson)
          .toList(),
      agentsVoyage: ((json['agentsVoyage'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(agentVoyageFromJson)
          .toList(),
      facturesAgent: ((json['facturesAgent'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(factureAgentFromJson)
          .toList(),
      bonsCaisse: ((json['bonsCaisse'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(bonCaisseFromJson)
          .toList(),
      caisseMouvements:
          (((json['caisse'] as Map?)?['mouvements'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()
              .map(caisseMouvementFromJson)
              .toList(),
      caisseClotures:
          (((json['caisse'] as Map?)?['clotures'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()
              .map(caisseClotureFromJson)
              .toList(),
      caisseParametres: caisseParametresFromJson(
        (json['caisse'] as Map?)?['parametres'] as Map<String, dynamic>?,
      ),
      dossiers: _rememberDossiers([
        for (final dossier in rows('dossiers'))
          dossierFromJson(
            dossier,
            clients: clientsById,
            prestataires: prestatairesById,
          ),
      ]),
    );
  }

  List<TransitDossier> _rememberDossiers(List<TransitDossier> dossiers) {
    _dossiersById
      ..clear()
      ..addAll({for (final d in dossiers) d.id: d});
    return dossiers;
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
  Future<void> saveAffectationVoyage(
    AffectationVoyage affectation, {
    bool valider = false,
  }) async {
    final result = await _send(
      'PUT',
      '/voyage-affectations/${_segment(affectation.id)}',
      affectationVoyageToJson(affectation, valider: valider),
    );
    applyAffectationVoyageJson(affectation, result as Map<String, dynamic>);
  }

  @override
  Future<void> deleteAffectationVoyage(AffectationVoyage affectation) =>
      _send('DELETE', '/voyage-affectations/${_segment(affectation.id)}');

  @override
  Future<String?> photoT1(AffectationVoyage affectation) async {
    final result = await _send(
      'GET',
      '/voyage-affectations/${_segment(affectation.id)}/t1',
    );
    return (result as Map<String, dynamic>)['image'] as String?;
  }

  @override
  Future<void> saveFactureAgent(FactureAgent facture) async {
    final result = await _send(
      'PUT',
      '/factures-agent/${_segment(facture.id)}',
      factureAgentToJson(facture),
    );
    facture
      ..version = (result['version'] as num).toInt()
      ..numero = (result['numero'] as num?)?.toInt() ?? facture.numero
      ..montant = _numOf(result['montant'], facture.montant);
  }

  @override
  Future<void> deleteFactureAgent(FactureAgent facture) =>
      _send('DELETE', '/factures-agent/${_segment(facture.id)}');

  @override
  Future<void> saveBonCaisse(BonCaisse bon) async {
    final result =
        await _send(
              'PUT',
              '/bons-caisse/${_segment(bon.id)}',
              bonCaisseToJson(bon),
            )
            as Map<String, dynamic>;
    bon
      ..version = (result['version'] as num).toInt()
      ..numero = (result['numero'] as num?)?.toInt() ?? bon.numero;
    // Compte et libellé repris du type de frais par le serveur.
    final lines = (result['lignes'] as List?) ?? const [];
    for (final (i, l) in lines.indexed) {
      if (i >= bon.lignes.length) break;
      bon.lignes[i]
        ..compte = l['compte'] as String? ?? bon.lignes[i].compte
        ..libelle = l['libelle'] as String? ?? bon.lignes[i].libelle;
    }
  }

  @override
  Future<void> deleteBonCaisse(BonCaisse bon) =>
      _send('DELETE', '/bons-caisse/${_segment(bon.id)}');

  @override
  Future<void> saveCaisseParametres(CaisseParametres parametres) => _send(
    'PUT',
    '/caisse/parametres',
    {'principale': parametres.principale, 'depenses': parametres.depenses},
  );

  @override
  Future<CaisseMouvement> encaisser({
    required TransitDossier dossier,
    required String statut,
    required double montant,
    String modePaiement = '',
    String observations = '',
  }) async {
    final result =
        await _send('POST', '/caisse/encaissements', {
              'id': newLocalId('rc'),
              'dossierId': dossier.id,
              'statut': statut,
              'montant': montant,
              'modePaiement': modePaiement,
              'observations': observations,
            })
            as Map<String, dynamic>;
    dossier
      ..operations.add(
        dossierOperationFromJson(result['operation'] as Map<String, dynamic>),
      )
      ..version = (result['version'] as num).toInt();
    return caisseMouvementFromJson(result['mouvement'] as Map<String, dynamic>);
  }

  @override
  Future<CaisseMouvement> payerBonCaisse(BonCaisse bon) async {
    final result =
        await _send('POST', '/caisse/bons/${_segment(bon.id)}/paiement', {
              'id': newLocalId('pb'),
            })
            as Map<String, dynamic>;
    bon
      ..version = (result['version'] as num).toInt()
      ..codeJournal = result['codeJournal'] as String? ?? bon.codeJournal;
    return caisseMouvementFromJson(result['mouvement'] as Map<String, dynamic>);
  }

  @override
  Future<CaisseMouvement> virementCaisse({
    required String type,
    required double montant,
    String observations = '',
  }) async {
    final result =
        await _send('POST', '/caisse/virements', {
              'id': newLocalId('vir'),
              'type': type,
              'montant': montant,
              'observations': observations,
            })
            as Map<String, dynamic>;
    return caisseMouvementFromJson(result['mouvement'] as Map<String, dynamic>);
  }

  @override
  Future<void> receptionnerVirement(CaisseMouvement virement) async {
    final result =
        await _send(
              'POST',
              '/caisse/virements/${_segment(virement.id)}/reception',
            )
            as Map<String, dynamic>;
    final saved = caisseMouvementFromJson(
      result['mouvement'] as Map<String, dynamic>,
    );
    virement
      ..receptionneLe = saved.receptionneLe
      ..receptionnePar = saved.receptionnePar;
  }

  @override
  Future<void> annulerMouvementCaisse(
    CaisseMouvement mouvement, {
    TransitDossier? dossier,
  }) async {
    final result =
        await _send('DELETE', '/caisse/mouvements/${_segment(mouvement.id)}')
            as Map<String, dynamic>;
    if (dossier != null && result['version'] != null) {
      dossier
        ..operations.removeWhere((o) => o.id == mouvement.operationUid)
        ..version = (result['version'] as num).toInt();
    }
  }

  @override
  Future<void> rouvrirCaisse(String caisse) =>
      _send('POST', '/caisse/clotures/annulation', {'caisse': caisse});

  @override
  Future<void> imputerEncaissement(
    CaisseMouvement mouvement, {
    required List<(TransitDossier, double)> imputations,
    required String codeJournal,
  }) async {
    final result =
        await _send(
              'POST',
              '/caisse/encaissements/${_segment(mouvement.id)}/imputation',
              {
                'codeJournal': codeJournal,
                'imputations': [
                  for (final (d, montant) in imputations)
                    {'dossierId': d.id, 'montant': montant},
                ],
              },
            )
            as Map<String, dynamic>;
    final dossiers = {for (final (d, _) in imputations) d.id: d};
    final origine = _dossiersById[mouvement.dossierId];
    if (origine != null) dossiers[origine.id] = origine;
    origine?.operations.removeWhere((o) => o.id == mouvement.operationUid);
    for (final entry in (result['operations'] as List)) {
      dossiers[entry['dossierId']]?.operations.add(
        dossierOperationFromJson(entry['operation'] as Map<String, dynamic>),
      );
    }
    for (final entry in (result['dossiers'] as List)) {
      dossiers[entry['id']]?.version = (entry['version'] as num).toInt();
    }
    final saved = caisseMouvementFromJson(
      result['mouvement'] as Map<String, dynamic>,
    );
    mouvement
      ..imputeLe = saved.imputeLe
      ..imputePar = saved.imputePar;
  }

  // Dossiers chargés, pour mettre à jour ceux touchés par une imputation.
  final Map<String, TransitDossier> _dossiersById = {};

  @override
  Future<CaisseCloture> cloturerCaisse(String caisse) async =>
      caisseClotureFromJson(
        await _send('POST', '/caisse/clotures', {'caisse': caisse})
            as Map<String, dynamic>,
      );

  static double _numOf(Object? value, double fallback) =>
      (value as num?)?.toDouble() ?? fallback;

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
  final List<AffectationVoyage> affectationsVoyage = [];
  final List<AgentVoyage> agentsVoyage = [];
  final List<FactureAgent> facturesAgent = [];
  final List<BonCaisse> bonsCaisse = [];
  final List<CaisseMouvement> caisseMouvements = [];
  final List<CaisseCloture> caisseClotures = [];
  final CaisseParametres caisseParametres = CaisseParametres();
  final Map<String, String> photosT1 = {};
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
            'Frontière',
            'Bureau DD',
            'Enquête',
            'Dépenses & Frais',
            'Caisse',
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
      affectationsVoyage: [...affectationsVoyage],
      agentsVoyage: [...agentsVoyage],
      facturesAgent: [...facturesAgent],
      bonsCaisse: [...bonsCaisse],
      caisseMouvements: [...caisseMouvements],
      caisseClotures: [...caisseClotures],
      caisseParametres: CaisseParametres(
        principale: caisseParametres.principale,
        depenses: caisseParametres.depenses,
      ),
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
    } else if (!isGeneralAccountCode(type.compteGeneral)) {
      // Compte détaillé choisi : utilisé tel quel.
      type.compte = type.compteGeneral;
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

  @override
  Future<void> saveAffectationVoyage(
    AffectationVoyage affectation, {
    bool valider = false,
  }) async {
    if (affectationsVoyage.any(
      (a) =>
          a.id != affectation.id &&
          a.voyageCle == affectation.voyageCle &&
          a.module == affectation.module,
    )) {
      throw const ErpBackendException(
        'Ce voyage est déjà affecté à ce module.',
        status: 409,
      );
    }
    final stored = affectationsVoyage
        .where((a) => a.id == affectation.id)
        .firstOrNull;
    const previous = {'Bureau DD': 'Frontière', 'Enquête': 'Bureau DD'};
    final before = previous[affectation.module];
    if (stored == null &&
        before != null &&
        !affectationsVoyage.any(
          (a) =>
              a.voyageCle == affectation.voyageCle &&
              a.module == before &&
              a.estValide,
        )) {
      throw ErpBackendException(
        "Le voyage doit d'abord être validé par : $before.",
        status: 400,
      );
    }
    if (stored != null && stored.estValide && !identical(stored, affectation)) {
      throw const ErpBackendException(
        'Cette saisie est validée : elle ne peut plus être modifiée.',
        status: 409,
      );
    }
    final image = affectation.t1Image;
    if (image != null) {
      if (image.isEmpty) {
        photosT1.remove(affectation.id);
      } else {
        photosT1[affectation.id] = image;
      }
      affectation
        ..aT1 = image.isNotEmpty
        ..t1Image = null;
    }
    if (valider) {
      if (!affectation.estSaisi) {
        throw const ErpBackendException(
          'Saisissez au moins un frais avant de valider.',
          status: 400,
        );
      }
      affectation
        ..statut = 'Validé'
        ..validePar = _user?.name ?? ''
        ..valideLe = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    }
    affectation.version += 1;
    if (affectation.assignePar.isEmpty) {
      affectation.assignePar = _user?.name ?? '';
    }
    if (affectation.creeLe.isEmpty) {
      affectation.creeLe = DateFormat(
        'dd/MM/yyyy HH:mm',
      ).format(DateTime.now());
    }
    if (affectation.estSaisi && affectation.saisiPar.isEmpty) {
      affectation.saisiPar = _user?.name ?? '';
    }
    _upsert(affectationsVoyage, affectation, (a) => a.id == affectation.id);
  }

  @override
  Future<void> deleteAffectationVoyage(AffectationVoyage affectation) async =>
      affectationsVoyage.removeWhere((a) => a.id == affectation.id);

  @override
  Future<String?> photoT1(AffectationVoyage affectation) async =>
      photosT1[affectation.id];

  @override
  Future<void> saveFactureAgent(FactureAgent facture) async {
    final lines = affectationsVoyage
        .where((a) => facture.affectations.contains(a.id))
        .toList();
    if (lines.any((a) => a.factureId.isNotEmpty && a.factureId != facture.id)) {
      throw const ErpBackendException(
        'Une des saisies est déjà facturée dans une autre facture.',
        status: 409,
      );
    }
    for (final a in affectationsVoyage.where(
      (a) => a.factureId == facture.id,
    )) {
      a.factureId = '';
    }
    for (final a in lines) {
      a.factureId = facture.id;
    }
    facture
      ..montant = lines.fold(0, (s, a) => s + a.total)
      ..version += 1;
    if (facture.numero == 0) facture.numero = facturesAgent.length + 1;
    _upsert(facturesAgent, facture, (f) => f.id == facture.id);
  }

  @override
  Future<void> saveBonCaisse(BonCaisse bon) async {
    for (final l in bon.lignes) {
      final type = typesFrais.where((t) => t.id == l.typeFraisId).firstOrNull;
      if (type == null) continue;
      if (l.compte.isEmpty) l.compte = type.compte;
      if (l.libelle.isEmpty) l.libelle = type.libelle;
    }
    bon.version += 1;
    if (bon.numero == 0) {
      bon.numero = bonsCaisse.fold(0, (m, b) => math.max(m, b.numero)) + 1;
    }
    _upsert(bonsCaisse, bon, (b) => b.id == bon.id);
  }

  @override
  Future<void> deleteBonCaisse(BonCaisse bon) async {
    if (caisseMouvements.any((m) => m.bonId == bon.id)) {
      throw const ErpBackendException(
        'Ce bon de caisse est déjà payé par la caisse : il ne peut plus être modifié ni supprimé.',
        status: 409,
      );
    }
    bonsCaisse.removeWhere((b) => b.id == bon.id);
  }

  static String get _todayFr => DateFormat('dd/MM/yyyy').format(DateTime.now());

  void _verifierCaisse(String caisse) {
    if (caisseParametres.journalDe(caisse).isEmpty) {
      throw ErpBackendException(
        'Aucun journal n’est choisi pour la caisse ${caisse.toLowerCase()} : la Direction doit le définir dans « Paramètres des caisses ».',
        status: 409,
      );
    }
    if (caisseClotures.any((c) => c.caisse == caisse && c.date == _todayFr)) {
      throw ErpBackendException(
        'La caisse ${caisse.toLowerCase()} est clôturée aujourd’hui.',
        status: 409,
      );
    }
  }

  CaisseMouvement _mouvement(
    String type,
    double montant, {
    int recuNumero = 0,
    String dossierId = '',
    String operationUid = '',
    String statut = '',
    String modePaiement = '',
    String bonId = '',
    String observations = '',
  }) {
    final m = CaisseMouvement(
      id: newLocalId('cm'),
      type: type,
      date: _todayFr,
      montant: montant,
      recuNumero: recuNumero,
      dossierId: dossierId,
      operationUid: operationUid,
      statutReglement: statut,
      modePaiement: modePaiement,
      bonId: bonId,
      observations: observations,
      auteur: _user?.name ?? '',
    );
    caisseMouvements.add(m);
    return m;
  }

  @override
  Future<void> saveCaisseParametres(CaisseParametres parametres) async {
    caisseParametres
      ..principale = parametres.principale
      ..depenses = parametres.depenses;
  }

  @override
  Future<CaisseMouvement> encaisser({
    required TransitDossier dossier,
    required String statut,
    required double montant,
    String modePaiement = '',
    String observations = '',
  }) async {
    _verifierCaisse(caissePrincipale);
    final reste = dossier.soldeClient;
    if (!dossier.estFacture || reste <= 0) {
      throw const ErpBackendException('Facture non validée ou déjà soldée.');
    }
    final amount = statut == statutPaye ? reste : montant;
    if (amount <= 0 ||
        amount > reste ||
        (statut == statutCommencement && amount >= reste)) {
      throw const ErpBackendException('Montant invalide.', status: 400);
    }
    final numero =
        caisseMouvements.fold(0, (m, c) => math.max(m, c.recuNumero)) + 1;
    final recu = 'RC-${numero.toString().padLeft(5, '0')}';
    final operation = DossierOperation(
      type: DossierOperationType.clientPayment,
      titre: 'Reçu de caisse $recu',
      categorie: 'Règlement Client',
      montant: amount,
      date: DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      codeJournal: caisseParametres.principale,
      modePaiement: modePaiement,
      observations: '$statut • facture ${dossier.factureClient.reference}',
      auteur: _user?.name ?? '',
    );
    dossier
      ..operations.add(operation)
      ..version += 1;
    return _mouvement(
      CaisseMouvement.encaissement,
      amount,
      recuNumero: numero,
      dossierId: dossier.id,
      operationUid: operation.id,
      statut: statut,
      modePaiement: modePaiement,
      observations: observations,
    );
  }

  @override
  Future<CaisseMouvement> payerBonCaisse(BonCaisse bon) async {
    _verifierCaisse(caisseDepenses);
    if (caisseMouvements.any((m) => m.bonId == bon.id)) {
      throw ErpBackendException('Le bon ${bon.reference} est déjà payé.');
    }
    if (bon.montant > soldeCaisse(caisseDepenses, caisseMouvements)) {
      throw const ErpBackendException(
        'Solde insuffisant dans la caisse des dépenses.',
        status: 409,
      );
    }
    bon
      ..codeJournal = caisseParametres.depenses
      ..version += 1;
    return _mouvement(CaisseMouvement.paiementBon, bon.montant, bonId: bon.id);
  }

  @override
  Future<CaisseMouvement> virementCaisse({
    required String type,
    required double montant,
    String observations = '',
  }) async {
    final source = type == CaisseMouvement.approvisionnement
        ? caissePrincipale
        : caisseDepenses;
    _verifierCaisse(
      caissePrincipale == source ? caisseDepenses : caissePrincipale,
    );
    _verifierCaisse(source);
    if (montant <= 0 || montant > soldeCaisse(source, caisseMouvements)) {
      throw ErpBackendException(
        'Solde insuffisant dans la caisse ${source.toLowerCase()}.',
        status: 409,
      );
    }
    return _mouvement(type, montant, observations: observations);
  }

  @override
  Future<void> receptionnerVirement(CaisseMouvement virement) async {
    _verifierCaisse(virement.caisseDestination);
    virement
      ..receptionneLe = _todayFr
      ..receptionnePar = _user?.name ?? '';
  }

  @override
  Future<void> annulerMouvementCaisse(
    CaisseMouvement mouvement, {
    TransitDossier? dossier,
  }) async {
    final caisse = switch (mouvement.type) {
      CaisseMouvement.encaissement => caissePrincipale,
      CaisseMouvement.paiementBon => caisseDepenses,
      _ => mouvement.caisseSource,
    };
    if (mouvement.estReceptionne ||
        mouvement.estImpute ||
        caisseClotures.any(
          (c) => c.caisse == caisse && c.date == mouvement.date,
        )) {
      throw const ErpBackendException(
        'Ce mouvement ne peut plus être annulé.',
        status: 409,
      );
    }
    caisseMouvements.removeWhere((m) => m.id == mouvement.id);
    if (dossier != null) {
      dossier
        ..operations.removeWhere((o) => o.id == mouvement.operationUid)
        ..version += 1;
    }
  }

  @override
  Future<void> rouvrirCaisse(String caisse) async {
    if (_user?.role != 'Administrateur') {
      throw const ErpBackendException(
        'Seul l’administrateur peut déclôturer une caisse.',
        status: 403,
      );
    }
    final last = caisseClotures.where((c) => c.caisse == caisse).lastOrNull;
    if (last != null) caisseClotures.remove(last);
  }

  @override
  Future<void> imputerEncaissement(
    CaisseMouvement mouvement, {
    required List<(TransitDossier, double)> imputations,
    required String codeJournal,
  }) async {
    final total = imputations.fold<double>(0, (s, i) => s + i.$2);
    if (mouvement.estImpute || (total - mouvement.montant).abs() > 0.001) {
      throw const ErpBackendException('Imputation invalide.', status: 400);
    }
    final origine = dossiers
        .where((d) => d.id == mouvement.dossierId)
        .firstOrNull;
    final ancienne = origine?.operations
        .where((o) => o.id == mouvement.operationUid)
        .firstOrNull;
    origine?.operations.remove(ancienne);
    for (final (n, (d, montant)) in imputations.indexed) {
      d.operations.add(
        DossierOperation(
          id: '${mouvement.id}-i${n + 1}',
          type: DossierOperationType.clientPayment,
          titre: ancienne?.titre ?? 'Reçu de caisse ${mouvement.recu}',
          categorie: 'Règlement Client',
          montant: montant,
          date: ancienne?.date ?? mouvement.date,
          codeJournal: codeJournal,
          modePaiement: mouvement.modePaiement,
          observations: 'Imputé par ${_user?.name ?? ''}',
          auteur: mouvement.auteur,
        ),
      );
      d.version += 1;
    }
    mouvement
      ..imputeLe = _todayFr
      ..imputePar = _user?.name ?? '';
  }

  @override
  Future<CaisseCloture> cloturerCaisse(String caisse) async {
    final today = _todayFr;
    if (caisseClotures.any((c) => c.caisse == caisse && c.date == today)) {
      throw const ErpBackendException(
        'Caisse déjà clôturée aujourd’hui.',
        status: 409,
      );
    }
    final events = evenementsCaisse(caisse, caisseMouvements);
    final duJour = events.where((e) => e.date == today);
    final cloture = CaisseCloture(
      caisse: caisse,
      date: today,
      recettes: duJour.fold(0, (s, e) => s + e.recette),
      depenses: duJour.fold(0, (s, e) => s + e.depense),
      solde: soldeCaisse(caisse, caisseMouvements),
      auteur: _user?.name ?? '',
    );
    caisseClotures.add(cloture);
    return cloture;
  }

  @override
  Future<void> deleteFactureAgent(FactureAgent facture) async {
    for (final a in affectationsVoyage.where(
      (a) => a.factureId == facture.id,
    )) {
      a.factureId = '';
    }
    facturesAgent.removeWhere((f) => f.id == facture.id);
  }

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
