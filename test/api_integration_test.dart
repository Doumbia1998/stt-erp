// Test de bout en bout contre une vraie API (ignoré sans adresse) :
// flutter test test/api_integration_test.dart --dart-define=API_TEST_URL=http://127.0.0.1:3099 --dart-define=API_TEST_PASSWORD=...
import 'package:flutter_test/flutter_test.dart';
import 'package:stt/erp_backend.dart';
import 'package:stt/models.dart';

const _url = String.fromEnvironment('API_TEST_URL');
const _password = String.fromEnvironment('API_TEST_PASSWORD');

void main() {
  test(
    'Data saved through the API is found again after a new login',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final backend = HttpErpBackend(_url);
      await backend.login('admin', _password);

      final account = PlanAccount(
        id: 'acc-$suffix',
        code: '411$suffix',
        libelle: 'Client intégration',
        nature: 'Client',
      );
      await backend.saveAccount(account);
      final journalAccount = PlanAccount(
        id: 'acc-bq-$suffix',
        code: '521$suffix',
        libelle: 'Banque intégration',
        nature: 'Banque',
      );
      await backend.saveAccount(journalAccount);
      await backend.saveJournal(
        JournalCode(
          code: 'BQ$suffix',
          intitule: 'Banque',
          type: 'Banque',
          compteTresorerie: journalAccount.code,
        ),
      );
      final client = Client(
        id: 'client-$suffix',
        nom: 'Client intégration $suffix',
        telephone: '+223 70 00 00 00',
        compteComptable: account.code,
      );
      await backend.saveClient(client);

      final dossier = TransitDossier(
        id: 'dossier-$suffix',
        numDossier: 'STT-$suffix',
        numBL: 'BL-1',
        numLB: '',
        client: client,
        nbConteneurs: 1,
        dateDebut: '09/10/2026',
        dateCreation: '09/10/2026',
        conteneurs: const [
          TransitContainer(
            numero: 'MSKU1234567',
            type: '40 pieds',
            marchandise: 'Riz',
          ),
        ],
      );
      await backend.saveDossier(dossier);
      expect(dossier.version, 1);

      dossier.factureClient
        ..lignes = const [
          InvoiceLine(
            description: 'Transport Bamako',
            quantite: 1,
            prixUnitaire: 75000,
          ),
        ]
        ..montant = 75000
        ..statut = 'Clôturée'
        ..dateEmission = '10/10/2026';
      dossier.operations.add(
        DossierOperation(
          type: DossierOperationType.clientPayment,
          titre: 'Règlement espèces',
          montant: 75000,
          date: '10/10/2026 14:05',
          codeJournal: 'BQ$suffix',
        ),
      );
      await backend.saveDossier(dossier);
      expect(dossier.version, 2);

      // Une seconde session (autre poste) retrouve tout.
      final data = await HttpErpBackend(_url).login('admin', _password);
      final reloaded = data.dossiers.singleWhere((d) => d.id == dossier.id);
      expect(reloaded.client.nom, client.nom);
      expect(reloaded.version, 2);
      expect(reloaded.conteneurs.single.numero, 'MSKU1234567');
      expect(reloaded.factureClient.statut, 'Clôturée');
      expect(
        reloaded.factureClient.lignes.single.description,
        'Transport Bamako',
      );
      expect(reloaded.operations.single.date, '10/10/2026 14:05');
      expect(reloaded.soldeClient, 0);
      expect(
        data.comptes.singleWhere((a) => a.id == account.id).tiersId,
        client.id,
      );

      // Une modification depuis une version périmée est refusée.
      final stale = data.dossiers.singleWhere((d) => d.id == dossier.id)
        ..version = 1;
      await expectLater(
        HttpErpBackend(
          _url,
        ).login('admin', _password).then((_) => backend.saveDossier(stale)),
        throwsA(
          isA<ErpBackendException>().having((e) => e.status, 'status', 409),
        ),
      );
      await backend.logout();
    },
    skip: _url.isEmpty ? 'API_TEST_URL non défini' : null,
  );
}
