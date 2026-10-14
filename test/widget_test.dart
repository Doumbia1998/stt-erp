// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stt/main.dart';
import 'package:stt/models_json.dart';

void main() {
  // Les tests n'appellent pas l'API : les données restent en mémoire.
  setUp(() => erpBackend = MemoryErpBackend());

  test('A dossier survives the JSON round trip used by the API', () {
    final client = Client(id: 'client-1', nom: 'Client test', telephone: '');
    final provider = Prestataire(
      id: 'provider-1',
      entreprise: 'Transport test',
      type: 'Transporteur',
      pays: 'Mali',
      villePort: 'Bamako',
      contact: '',
      telephone: '',
      email: '',
      services: '',
    );
    final dossier =
        TransitDossier(
            id: 'dossier-1',
            numDossier: 'STT-TEST',
            numBL: 'BL-1',
            numLB: '',
            client: client,
            prestataire: provider,
            nbConteneurs: 1,
            dateDebut: '09/10/2026',
            conteneurs: const [
              TransitContainer(
                numero: 'MSKU1234567',
                type: '40 pieds',
                marchandise: 'Riz',
              ),
            ],
            version: 3,
          )
          ..transporteurAffecte = provider
          ..depenses.add(
            Depense(
              titre: 'Péage',
              montant: 5000,
              categorie: 'Route',
              date: '10/10/2026 08:30',
            ),
          )
          ..operations.add(
            const DossierOperation(
              type: DossierOperationType.clientPayment,
              titre: 'Règlement',
              montant: 100000,
              date: '10/10/2026 09:00',
              codeJournal: 'BQ',
            ),
          );
    dossier.factureClient
      ..statut = 'Clôturée'
      ..montant = 100000
      ..dateEmission = '10/10/2026'
      ..lignes = const [
        InvoiceLine(
          description: 'Transport Bamako',
          quantite: 1,
          prixUnitaire: 100000,
        ),
      ];

    final json = dossierToJson(dossier)..['id'] = dossier.id;
    final restored = dossierFromJson(
      json,
      clients: {client.id: client},
      prestataires: {provider.id: provider},
    );

    expect(restored.client, same(client));
    expect(restored.prestataire, same(provider));
    expect(restored.transporteurAffecte, same(provider));
    expect(restored.version, 3);
    expect(restored.conteneurs.single.numero, 'MSKU1234567');
    expect(restored.factureClient.statut, 'Clôturée');
    expect(restored.factureClient.lignes.single.total, 100000);
    expect(restored.depenses.single.date, '10/10/2026 08:30');
    expect(restored.operations.single.codeJournal, 'BQ');
    expect(restored.soldeClient, 0);
  });

  testWidgets('Wrong credentials keep the user on the login page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TransitTrackerApp());
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), 'mauvais');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();
    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    expect(find.text('SE CONNECTER'), findsOneWidget);
  });

  testWidgets('ERP modules expose their pages from the top dropdowns', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TransitTrackerApp());

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();

    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(find.text('Dépenses par catégorie'), findsOneWidget);
    expect(find.text('Modules de gestion'), findsOneWidget);
    await tester.tap(find.byTooltip('Alertes conteneurs'));
    await tester.pumpAndSettle();
    expect(find.text('Suivi des conteneurs'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profil utilisateur'));
    await tester.pumpAndSettle();
    expect(find.text('Administrateur'), findsWidgets);
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();

    expect(find.text('Gestion'), findsWidgets);
    await tester.ensureVisible(find.byTooltip('Comptabilité'));
    await tester.tap(find.byTooltip('Comptabilité'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan Comptable').last);
    await tester.pumpAndSettle();

    expect(find.text('Plan Comptable'), findsWidgets);
    await tester.tap(find.text('NOUVEAU COMPTE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-code')),
      '411001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-label')),
      'Client Test',
    );
    await tester.tap(find.byKey(const ValueKey('plan-account-nature')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Client').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('411001 — Client Test'), findsOneWidget);
    expect(find.byTooltip('Modifier le compte'), findsOneWidget);
    await tester.tap(find.text('NOUVEAU COMPTE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-code')),
      '411001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-label')),
      'Compte en double',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Doublon détecté'), findsOneWidget);
    await tester.tap(find.text('Compris'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NOUVEAU COMPTE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-code')),
      '401001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-label')),
      'Transport Dakar',
    );
    await tester.tap(find.byKey(const ValueKey('plan-account-nature')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fournisseur').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOUVEAU COMPTE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-code')),
      '102001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-account-label')),
      'Banque STT',
    );
    await tester.tap(find.byKey(const ValueKey('plan-account-nature')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banque').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Comptabilité'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Code journaux').last);
    await tester.pumpAndSettle();
    expect(find.text('Interrogation et Lettrage'), findsNothing);
    await tester.tap(find.text('NOUVEAU JOURNAL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('journal-code')), 'BQ');
    await tester.enterText(
      find.byKey(const ValueKey('journal-intitule')),
      'Banque principale',
    );
    final journalAccountField = find.descendant(
      of: find.byKey(const ValueKey('journal-account-picker')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(journalAccountField, '102001');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('102001 • Banque STT').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BQ • Banque principale'), findsOneWidget);

    await tester.tap(find.byTooltip('Comptabilité'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan Comptable').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Recouvrement'));
    await tester.tap(find.byTooltip('Recouvrement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Etat des Impayés').last);
    await tester.pumpAndSettle();

    expect(find.text('Etat des Impayés'), findsWidgets);
    await tester.tap(find.byTooltip('Recouvrement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Règlement').last);
    await tester.pumpAndSettle();
    expect(find.text('Saisie des Règlements Clients'), findsOneWidget);
    expect(find.text('Saisie des Règlements Transporteurs'), findsOneWidget);
    await tester.tap(find.text('Saisie des Règlements Transporteurs'));
    await tester.pumpAndSettle();
    expect(find.text('Saisie des règlements transporteurs'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Transport'));
    await tester.tap(find.byTooltip('Transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dossier').last);
    await tester.pumpAndSettle();

    expect(find.text('Gestion des Dossiers'), findsOneWidget);
    expect(find.text('NOUVEAU DOSSIER'), findsOneWidget);
    await tester.tap(find.text('NOUVEAU DOSSIER'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau dossier client'), findsOneWidget);
    expect(find.text('Transitaire / chargeur'), findsOneWidget);
    expect(find.text('Type de facturation'), findsOneWidget);
    expect(find.text('Type de priorité'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Date d’arrivée du bateau'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Date d’arrivée du bateau'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Liste des conteneurs'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Liste des conteneurs'), findsOneWidget);
    expect(find.byKey(const ValueKey('container-row-0')), findsOneWidget);
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('container-row-1')), findsOneWidget);
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau dossier client'), findsNothing);

    await tester.ensureVisible(find.byTooltip('Transitaire'));
    await tester.tap(find.byTooltip('Transitaire'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clients').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_add_alt_1_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Client Test');
    await tester.enterText(find.byType(TextFormField).at(1), 'Société Test');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      '+223 70 000 0000',
    );
    final clientAccountField = find.descendant(
      of: find.byKey(const ValueKey('client-account-picker')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(clientAccountField, '411001');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('411001 • Client Test').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Compte client : 411001'), findsOneWidget);
    expect(find.byTooltip('Modifier le client'), findsOneWidget);
    await tester.tap(find.byTooltip('Modifier le client'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(2),
      '+223 76 111 2222',
    );
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(find.textContaining('+223 76 111 2222'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Transport'));
    await tester.tap(find.byTooltip('Transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dossier').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOUVEAU DOSSIER'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('dossier-client-search')),
        matching: find.byType(TextFormField),
      ),
      'Client Test',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Client Test').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(
              of: find.byKey(const ValueKey('dossier-client-search')),
              matching: find.byType(TextFormField),
            ),
          )
          .controller!
          .text,
      'Client Test',
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    final containerNumber = find.byKey(const ValueKey('container-number-0'));
    await tester.ensureVisible(containerNumber);
    await tester.enterText(containerNumber, 'MSKU1234567');
    await tester.tap(find.text('Créer le dossier'));
    await tester.pumpAndSettle();
    expect(find.text('Sélectionnez une valeur dans la liste'), findsNothing);

    expect(find.textContaining('Client : Client Test'), findsOneWidget);
    expect(find.textContaining('1 conteneur(s)'), findsOneWidget);
    final createdDossier = find
        .ancestor(
          of: find.textContaining('Client : Client Test'),
          matching: find.byType(ListTile),
        )
        .first;
    expect(
      find.descendant(
        of: createdDossier,
        matching: find.textContaining('Prestataire :'),
      ),
      findsNothing,
    );
    await tester.ensureVisible(find.byTooltip('Prestation'));
    await tester.tap(find.byTooltip('Prestation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Facture Client').last);
    await tester.pumpAndSettle();
    expect(find.text('Factures en cours'), findsOneWidget);
    expect(find.text('Factures validées'), findsOneWidget);
    expect(
      find.textContaining('Ouvrir la facture pour saisir les prestations'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Ouvrir la facture').first);
    await tester.pumpAndSettle();
    expect(find.text('Prestations facturées'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('invoice-quantity-0')),
          )
          .controller!
          .text,
      '1.0',
    );
    await tester.enterText(
      find.byKey(const ValueKey('invoice-description-0')),
      'Transport Bamako',
    );
    await tester.enterText(
      find.byKey(const ValueKey('invoice-price-0')),
      '75000',
    );
    await tester.tap(find.byKey(const ValueKey('add-invoice-line')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('invoice-description-1')),
      'Frais de dossier',
    );
    await tester.enterText(
      find.byKey(const ValueKey('invoice-price-1')),
      '25000',
    );
    await tester.pumpAndSettle();
    final invoiceTotal = tester.widget<Text>(
      find.byKey(const ValueKey('invoice-grand-total')),
    );
    expect(invoiceTotal.data!.replaceAll(RegExp(r'\D'), ''), '100000');
    await tester.tap(find.byKey(const ValueKey('save-invoice-exit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('En cours'), findsOneWidget);
    await tester.tap(find.byTooltip('Ouvrir la facture').first);
    await tester.pumpAndSettle();
    expect(find.text('Transport Bamako'), findsOneWidget);
    expect(find.text('Frais de dossier'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-invoice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider et clôturer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Factures validées'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Clôturée'), findsOneWidget);
    await tester.tap(find.byTooltip('Ouvrir la facture').first);
    await tester.pumpAndSettle();
    expect(find.text('Transport Bamako'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Transport'));
    await tester.tap(find.byTooltip('Transport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voyages').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-voyage')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'AB 1234 MD');
    await tester.enterText(find.byType(TextFormField).at(1), 'Chauffeur Test');
    await tester.enterText(find.byType(TextFormField).at(2), 'Dakar');
    await tester.enterText(find.byType(TextFormField).at(3), 'Bamako');
    await tester.enterText(find.byType(TextFormField).at(4), '12/10/2026');
    await tester.enterText(find.byType(TextFormField).at(5), '15/10/2026');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('AB 1234 MD'), findsOneWidget);
  });

  testWidgets('Mobile uses module drawer and can create a provider', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    (erpBackend as MemoryErpBackend).comptes.add(
      PlanAccount(
        id: 'account-401001',
        code: '401001',
        libelle: 'Transport Dakar',
        nature: 'Fournisseur',
      ),
    );

    await tester.pumpWidget(const TransitTrackerApp());
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ouvrir les modules'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('header-stt-logo')), findsOneWidget);
    final drawerPrestation = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('Prestation'),
    );
    await tester.ensureVisible(drawerPrestation);
    await tester.tap(drawerPrestation);
    await tester.pumpAndSettle();
    final drawerProvider = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('Espace Prestataire'),
    );
    await tester.tap(drawerProvider);
    await tester.pumpAndSettle();

    expect(find.text('Aucun prestataire enregistré'), findsOneWidget);
    await tester.tap(find.text('NOUVEAU PRESTATAIRE'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Transport Dakar');
    await tester.enterText(
      find.byType(TextFormField).at(4),
      '+221 77 000 0000',
    );
    await tester.enterText(
      find.byType(TextFormField).at(10),
      'Transport routier',
    );
    final providerAccountField = find.descendant(
      of: find.byKey(const ValueKey('provider-account-picker')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(providerAccountField);
    await tester.enterText(providerAccountField, '401001');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('401001 • Transport Dakar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text('Transport Dakar'), findsOneWidget);
    expect(find.textContaining('Bamako, Mali'), findsOneWidget);
    expect(find.textContaining('Compte fournisseur : 401001'), findsOneWidget);
    expect(find.byTooltip('Portail à activer'), findsOneWidget);
    await tester.tap(find.byTooltip('Modifier le prestataire'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), 'Bamako Centre');
    await tester.tap(find.text('Enregistrer les modifications'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bamako Centre, Mali'), findsOneWidget);

    await tester.tap(find.byTooltip('Ouvrir les modules'));
    await tester.pumpAndSettle();
    final drawerTransport = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('Transport'),
    );
    await tester.ensureVisible(drawerTransport);
    await tester.tap(drawerTransport);
    await tester.pumpAndSettle();
    final drawerDossier = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('Dossier'),
    );
    await tester.tap(drawerDossier);
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOUVEAU DOSSIER'));
    await tester.pumpAndSettle();
    final layoutError = tester.takeException();
    if (layoutError is FlutterError) {
      for (final diagnostic in layoutError.diagnostics) {
        debugPrint(diagnostic.toString());
      }
    }
    expect(layoutError, isNull);
    expect(find.text('Nouveau dossier client'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dossier-provider-search')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Liste des conteneurs'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Liste des conteneurs'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
  });

  test('Dossier balances keep the client and provider accounts separate', () {
    final client = Client(id: 'client-1', nom: 'Client test', telephone: '');
    final provider = Prestataire(
      id: 'provider-1',
      entreprise: 'Transport test',
      type: 'Transporteur',
      pays: 'Mali',
      villePort: 'Bamako',
      contact: '',
      telephone: '',
      email: '',
      services: '',
    );
    final dossier = TransitDossier(
      id: 'dossier-1',
      numDossier: 'STT-TEST',
      numBL: 'BL-1',
      numLB: '',
      client: client,
      prestataire: provider,
      nbConteneurs: 1,
      dateDebut: '09/10/2026',
    );
    expect(dossier.factureClient.statut, 'Brouillon');
    expect(dossier.facturePrestataire.statut, 'Brouillon');
    dossier.factureClient
      ..montant = 100000
      ..statut = 'Clôturée';
    dossier.factureTransporteur
      ..montant = 60000
      ..statut = 'Clôturée';
    dossier.operations.addAll([
      const DossierOperation(
        type: DossierOperationType.clientPayment,
        titre: 'Règlement client',
        montant: 100000,
        date: '09/10/2026',
      ),
      const DossierOperation(
        type: DossierOperationType.providerAdvance,
        titre: 'Avance',
        montant: 20000,
        date: '09/10/2026',
      ),
      const DossierOperation(
        type: DossierOperationType.providerPayment,
        titre: 'Paiement complémentaire',
        montant: 30000,
        date: '09/10/2026',
      ),
    ]);

    expect(dossier.soldeClient, 0);
    expect(dossier.soldePrestataire, 10000);
    expect(dossier.peutCloturer, isFalse);

    dossier.operations.add(
      const DossierOperation(
        type: DossierOperationType.providerPayment,
        titre: 'Solde final',
        montant: 10000,
        date: '09/10/2026',
      ),
    );
    expect(dossier.soldePrestataire, 0);
    expect(dossier.peutCloturer, isTrue);
  });

  testWidgets('Searchable provider selector filters the saved providers', (
    WidgetTester tester,
  ) async {
    final providers = [
      Prestataire(
        id: 'provider-dakar',
        entreprise: 'Transport Dakar',
        type: 'Transporteur',
        pays: 'Sénégal',
        villePort: 'Dakar',
        contact: '',
        telephone: '',
        email: '',
        services: '',
      ),
      Prestataire(
        id: 'provider-bamako',
        entreprise: 'Camions Bamako',
        type: 'Transporteur',
        pays: 'Mali',
        villePort: 'Bamako',
        contact: '',
        telephone: '',
        email: '',
        services: '',
      ),
    ];
    Prestataire? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: SearchableDropdownFormField<Prestataire>(
              key: const ValueKey('test-provider-search'),
              options: providers,
              value: null,
              label: 'Prestataire affecté',
              emptyText: 'Aucun prestataire',
              displayString: (provider) => provider.entreprise,
              onChanged: (provider) => selected = provider,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('test-provider-search')),
        matching: find.byType(TextFormField),
      ),
      'dakar',
    );
    await tester.pumpAndSettle();

    expect(find.text('Transport Dakar'), findsOneWidget);
    expect(find.text('Camions Bamako'), findsNothing);
    await tester.tap(find.text('Transport Dakar').last);
    await tester.pumpAndSettle();
    expect(selected?.id, 'provider-dakar');
  });
}
