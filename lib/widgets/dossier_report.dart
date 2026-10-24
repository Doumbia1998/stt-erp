part of '../main.dart';

// --- RAPPORT DE DOSSIER : tout ce qui a été fait sur un dossier, ses coûts et sa marge ---

// Frais d'un module voyage (Frontière, Bureau DD, Enquête) imputés à un dossier.
class _BilanVoyageModule {
  final AffectationVoyage affectation;
  // Part du dossier quand le camion transporte plusieurs dossiers.
  final double part;

  const _BilanVoyageModule(this.affectation, this.part);

  double get montant => affectation.total * part;
}

class _BilanTransport {
  final String reference;
  final String transporteur;
  final String plaque;
  final String conteneurs;
  final double montant;

  const _BilanTransport(
    this.reference,
    this.transporteur,
    this.plaque,
    this.conteneurs,
    this.montant,
  );
}

class _DossierBilan {
  final TransitDossier dossier;
  final List<(FactureTransitaire, FactureTransitaireLigne)> transit;
  final List<_BilanTransport> transports;
  final List<_BilanVoyageModule> modules;

  _DossierBilan._(this.dossier, this.transit, this.transports, this.modules);

  factory _DossierBilan(TransitDossier d) {
    final transit = [
      for (final f in _facturesTransitaire)
        for (final l in f.lignes)
          if (l.dossierId == d.id) (f, l),
    ];
    final transports = <_BilanTransport>[];
    final carried = <String>{};
    for (final f in _facturesTransporteur) {
      final mine = f.lignes.where((l) => l.dossierId == d.id).toList();
      if (mine.isEmpty) continue;
      // Le prix convenu de la facture est réparti au prorata des conteneurs.
      final all = f.lignes.fold<double>(0, (s, l) => s + l.montant);
      final own = mine.fold<double>(0, (s, l) => s + l.montant);
      final share = all > 0 ? own / all : mine.length / f.lignes.length;
      carried.addAll(mine.map((l) => l.cleConteneur));
      transports.add(
        _BilanTransport(
          f.reference,
          _partnerLabel(f.transporteurId),
          f.plaque,
          mine.map((l) => l.numeroConteneur).join(', '),
          f.montant * share,
        ),
      );
    }
    // Conteneurs pas encore facturés par un transporteur : transport dû du transitaire.
    for (final (f, l) in transit) {
      if (carried.contains(l.cleConteneur) || l.montantTransport <= 0) continue;
      transports.add(
        _BilanTransport(
          '${f.reference} (transport dû)',
          _partnerLabel(l.transporteurId),
          l.plaque,
          l.numeroConteneur,
          l.montantTransport,
        ),
      );
    }
    final modules = <_BilanVoyageModule>[];
    for (final a in _affectationsVoyage) {
      final numbers = a.dossiers
          .split(',')
          .map((n) => n.trim())
          .where((n) => n.isNotEmpty)
          .toList();
      if (!numbers.contains(d.numDossier)) continue;
      modules.add(_BilanVoyageModule(a, 1 / numbers.length));
    }
    return _DossierBilan._(d, transit, transports, modules);
  }

  double get chiffreAffaires => dossier.totalFacturesClient;
  double get encaisse => dossier.totalReglementsClient;
  double get resteClient => chiffreAffaires - encaisse;

  double get coutTransitaire {
    final lines = transit.fold<double>(0, (s, e) => s + e.$2.montant);
    // Ancien circuit : facture transitaire saisie sur le dossier.
    if (transit.isEmpty && dossier.factureTransitaire.statut == 'Clôturée') {
      return dossier.factureTransitaire.montant;
    }
    return lines;
  }

  double get coutTransport {
    final value = transports.fold<double>(0, (s, t) => s + t.montant);
    if (transports.isEmpty &&
        dossier.factureTransporteur.statut == 'Clôturée') {
      return dossier.factureTransporteur.montant;
    }
    return value;
  }

  double coutModule(String module) => modules
      .where((m) => m.affectation.module == module)
      .fold(0, (s, m) => s + m.montant);

  double get coutDepenses => dossier.totalDepenses;

  double get coutAutresPrestataires =>
      (dossier.facturePrestataire.statut == 'Clôturée'
          ? dossier.facturePrestataire.montant
          : 0) +
      dossier.operations
          .where((o) => o.type == DossierOperationType.providerInvoice)
          .fold(0, (s, o) => s + o.montant);

  List<(String, double)> get couts => [
    ('Transitaire (frais)', coutTransitaire),
    ('Transport', coutTransport),
    for (final module in fraisParModuleVoyage.keys)
      (module, coutModule(module)),
    ('Dépenses du dossier', coutDepenses),
    ('Autres prestataires', coutAutresPrestataires),
  ];

  double get totalCouts => couts.fold(0, (s, c) => s + c.$2);
  double get marge => chiffreAffaires - totalCouts;
  double get tauxMarge =>
      chiffreAffaires == 0 ? 0 : marge / chiffreAffaires * 100;
}

String _partnerLabel(String id) =>
    _prestataires.where((p) => p.id == id).firstOrNull?.entreprise ?? '';

String _percent(double value) => '${value.toStringAsFixed(1)} %';

// Résumé à l'écran (recettes, coûts, marge) avant l'impression du rapport.
Future<void> _showDossierReport(
  BuildContext context,
  List<TransitDossier> dossiers,
) async {
  if (dossiers.isEmpty) {
    await _showInfoAlert(
      context,
      title: 'Aucun dossier',
      message:
          'Sélectionnez un dossier ou recherchez les dossiers concernés pour faire le rapport.',
    );
    return;
  }
  final bilans = dossiers.map(_DossierBilan.new).toList();
  final ca = bilans.fold<double>(0, (s, b) => s + b.chiffreAffaires);
  final couts = bilans.fold<double>(0, (s, b) => s + b.totalCouts);
  final marge = ca - couts;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        dossiers.length == 1
            ? 'Rapport du dossier ${dossiers.first.numDossier}'
            : 'Rapport de ${dossiers.length} dossiers',
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ErpMetricTile(
                    label: 'Facturé au client',
                    value: _amountText(ca),
                    color: _gridAccent,
                    icon: Icons.request_quote_rounded,
                  ),
                  ErpMetricTile(
                    label: 'Coûts (tous frais)',
                    value: _amountText(couts),
                    color: const Color(0xFFEA580C),
                    icon: Icons.payments_outlined,
                  ),
                  ErpMetricTile(
                    key: const ValueKey('dossier-report-margin'),
                    label: 'Marge',
                    value:
                        '${_amountText(marge)} • ${_percent(ca == 0 ? 0 : marge / ca * 100)}',
                    color: marge >= 0
                        ? const Color(0xFF15803D)
                        : const Color(0xFFDC2626),
                    icon: Icons.trending_up_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final b in bilans) ...[
                Text(
                  '${b.dossier.numDossier} • ${b.dossier.client.nom}',
                  style: const TextStyle(
                    color: _gridText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text('Facturé : ${_amountText(b.chiffreAffaires)}'),
                    for (final (label, value) in b.couts)
                      if (value != 0) Text('$label : ${_amountText(value)}'),
                    Text(
                      'Marge : ${_amountText(b.marge)} (${_percent(b.tauxMarge)})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: b.marge >= 0
                            ? const Color(0xFF15803D)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        FilledButton.icon(
          key: const ValueKey('dossier-report-print'),
          onPressed: () {
            Navigator.pop(context);
            _printDossierReport(bilans);
          },
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('Imprimer en PDF'),
        ),
      ],
    ),
  );
}

pw.Widget _reportSection(String title) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
  child: pw.Text(
    title,
    style: pw.TextStyle(
      color: _pdfPrimary,
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    ),
  ),
);

Future<void> _printDossierReport(List<_DossierBilan> bilans) async {
  final logo = await _loadPdfLogo();
  final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
  final doc = pw.Document(
    title: 'Rapport de dossier',
    author: 'Sylla Transit & Transport',
  );
  String money(double value) => formatCurrency(value);
  final ca = bilans.fold<double>(0, (s, b) => s + b.chiffreAffaires);
  final couts = bilans.fold<double>(0, (s, b) => s + b.totalCouts);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _pdfPrimary)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (logo != null) ...[
              pw.Image(logo, height: 36),
              pw.SizedBox(width: 10),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'STT',
                  style: pw.TextStyle(
                    color: _pdfPrimary,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'SYLLA TRANSIT & TRANSPORT',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  bilans.length == 1
                      ? 'RAPPORT DU DOSSIER ${bilans.first.dossier.numDossier}'
                      : 'RAPPORT DE ${bilans.length} DOSSIERS',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Édité le $now',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Sylla Transit & Transport  |  Page ${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        if (bilans.length > 1) ...[
          _reportSection('Synthèse des dossiers'),
          _pdfTable(
            ['Dossier', 'Client', 'Facturé', 'Coûts', 'Marge', 'Taux'],
            [
              for (final b in bilans)
                [
                  b.dossier.numDossier,
                  b.dossier.client.nom,
                  money(b.chiffreAffaires),
                  money(b.totalCouts),
                  money(b.marge),
                  _percent(b.tauxMarge),
                ],
            ],
            numericColumns: {2, 3, 4, 5},
            fontSize: 8,
          ),
          pw.SizedBox(height: 8),
          _pdfTotals([
            ('Total facturé', '${money(ca)} FCFA'),
            ('Total des coûts', '${money(couts)} FCFA'),
            ('Marge globale', '${money(ca - couts)} FCFA'),
            ('Taux de marge', _percent(ca == 0 ? 0 : (ca - couts) / ca * 100)),
          ]),
        ],
        for (final b in bilans) ..._dossierReportSection(b, bilans.length > 1),
      ],
    ),
  );
  await Printing.layoutPdf(
    name: bilans.length == 1
        ? 'Rapport ${bilans.first.dossier.numDossier}'
        : 'Rapport dossiers',
    format: PdfPageFormat.a4.landscape,
    onLayout: (_) => doc.save(),
  );
}

List<pw.Widget> _dossierReportSection(_DossierBilan b, bool newPage) {
  final d = b.dossier;
  String money(double value) => formatCurrency(value);
  final payments = d.operations
      .where((o) => o.type == DossierOperationType.clientPayment)
      .toList();
  return [
    if (newPage) pw.NewPage(),
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(colors: [_pdfPrimary, _pdfAccent]),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(
        'Dossier ${d.numDossier} • ${d.client.nom}',
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ),
    pw.SizedBox(height: 6),
    _pdfInfoGrid([
      ('Client', d.client.nom),
      ('Numéro BL', d.numBL),
      ('Transitaire', d.nomTransitaire),
      ('Date de création', d.dateCreation),
      ('Statut', d.statut),
      ('Marchandise', d.typeMarchandise),
      ('Lieu de livraison', d.lieuLivraison),
      ('Conteneurs', '${d.conteneurs.length}'),
    ]),
    _reportSection('Conteneurs'),
    _pdfTable(
      ['Numéro', 'Type', 'Marchandise'],
      [
        for (final c in d.conteneurs) [c.numero, c.type, c.marchandise],
      ],
      fontSize: 8,
    ),
    if (b.transit.isNotEmpty) ...[
      _reportSection('Transitaire et camions'),
      _pdfTable(
        [
          'Facture',
          'Transitaire',
          'Conteneur',
          'Départ',
          'Transporteur',
          'Camion',
          'Transit',
          'Surest.',
          'Vol./poids',
          'Autres',
          'Péage',
          'Frais',
          'Avance',
        ],
        [
          for (final (f, l) in b.transit)
            [
              f.reference,
              _partnerLabel(f.transitaireId),
              l.numeroConteneur,
              l.dateDepart,
              _partnerLabel(l.transporteurId),
              l.plaque,
              money(l.fraisTransit),
              money(l.surestariesMagasinage),
              money(l.volumePoids),
              money(l.autresFrais),
              money(l.fraisPeage),
              money(l.montant),
              money(l.avanceCamion),
            ],
        ],
        numericColumns: {6, 7, 8, 9, 10, 11, 12},
        fontSize: 7,
      ),
    ],
    if (b.transports.isNotEmpty) ...[
      _reportSection('Transport'),
      _pdfTable(
        ['Facture', 'Transporteur', 'Camion', 'Conteneurs', 'Coût'],
        [
          for (final t in b.transports)
            [
              t.reference,
              t.transporteur,
              t.plaque,
              t.conteneurs,
              money(t.montant),
            ],
        ],
        numericColumns: {4},
        fontSize: 8,
      ),
    ],
    if (b.modules.isNotEmpty) ...[
      _reportSection('Frontière, Bureau DD et Enquête'),
      _pdfTable(
        [
          'Étape',
          'Camion',
          'Départ',
          'Statut',
          'Frais saisis',
          'Total',
          'Part du dossier',
        ],
        [
          for (final m in b.modules)
            [
              m.affectation.module,
              m.affectation.plaque,
              m.affectation.dateDepart,
              m.affectation.estValide ? 'Validé' : 'En cours',
              [
                if (m.affectation.aT1) 'T1 joint',
                for (final e in m.affectation.frais.entries)
                  '${e.key} ${money(e.value)}',
              ].join(' • '),
              money(m.affectation.total),
              money(m.montant),
            ],
        ],
        numericColumns: {5, 6},
        fontSize: 7.5,
      ),
    ],
    if (d.depenses.isNotEmpty) ...[
      _reportSection('Dépenses du dossier'),
      _pdfTable(
        ['Date', 'Libellé', 'Catégorie', 'Montant'],
        [
          for (final e in d.depenses)
            [e.date, e.titre, e.categorie, money(e.montant)],
        ],
        numericColumns: {3},
        fontSize: 8,
      ),
    ],
    _reportSection('Client : facturation et paiements'),
    _pdfTable(
      ['Date', 'Opération', 'Mode', 'Montant'],
      [
        if (d.factureClient.statut == 'Clôturée')
          [
            d.factureClient.dateEmission,
            'Facture ${d.factureClient.reference}',
            '',
            money(d.factureClient.montant),
          ],
        for (final o in d.operations.where(
          (o) => o.type == DossierOperationType.clientInvoice,
        ))
          [o.date.split(' ').first, o.titre, '', money(o.montant)],
        for (final o in payments)
          [
            o.date.split(' ').first,
            'Règlement ${o.titre}',
            o.modePaiement,
            '- ${money(o.montant)}',
          ],
      ],
      numericColumns: {3},
      fontSize: 8,
    ),
    _reportSection('Résultat du dossier'),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _pdfTable(
            ['Coûts', 'Montant'],
            [
              for (final (label, value) in b.couts) [label, money(value)],
            ],
            numericColumns: {1},
            fontSize: 8.5,
          ),
        ),
        pw.SizedBox(width: 16),
        _pdfTotals([
          ('Facturé au client', '${money(b.chiffreAffaires)} FCFA'),
          ('Encaissé', '${money(b.encaisse)} FCFA'),
          ('Reste à encaisser', '${money(b.resteClient)} FCFA'),
          ('Total des coûts', '${money(b.totalCouts)} FCFA'),
          ('MARGE', '${money(b.marge)} FCFA'),
          ('Taux de marge', _percent(b.tauxMarge)),
        ]),
      ],
    ),
  ];
}
