part of '../main.dart';

// --- HISTORIQUE D'UN CLIENT ---
// Coordonnées, total facturé, total réglé, reste à payer et historique des
// opérations (factures, factures complémentaires et règlements).

enum _FiltreHistorique { tout, factures, reglements }

class _OperationClient {
  final DateTime date;
  final String titre;
  final String detail;
  final double montant;
  final bool estReglement;
  final bool complementaire;

  const _OperationClient({
    required this.date,
    required this.titre,
    required this.detail,
    required this.montant,
    required this.estReglement,
    this.complementaire = false,
  });
}

class ClientHistoriquePage extends StatefulWidget {
  final Client client;

  const ClientHistoriquePage({super.key, required this.client});

  @override
  State<ClientHistoriquePage> createState() => _ClientHistoriquePageState();
}

class _ClientHistoriquePageState extends State<ClientHistoriquePage> {
  _FiltreHistorique _filtre = _FiltreHistorique.tout;

  static final _dateFormat = DateFormat('dd/MM/yy');

  List<TransitDossier> get _dossiersClient =>
      _dossiers.where((d) => d.client.id == widget.client.id).toList();

  List<_OperationClient> get _operations {
    final rows = <_OperationClient>[];
    for (final d in _dossiersClient) {
      final dossier = [
        'Dossier ${d.numDossier}',
        if (d.numBL.isNotEmpty) 'BL ${d.numBL}',
      ].join(' • ');
      if (d.factureClient.estValidee && d.factureClient.montant > 0) {
        rows.add(
          _OperationClient(
            date: _parseFrDate(d.factureClient.dateEmission) ?? DateTime(0),
            titre: 'FACTURE ${d.factureClient.reference}',
            detail: dossier,
            montant: d.factureClient.montant,
            estReglement: false,
          ),
        );
      }
      for (final op in d.operations) {
        final date = _parseFrDate(op.date) ?? DateTime(0);
        if (op.type == DossierOperationType.clientInvoice) {
          rows.add(
            _OperationClient(
              date: date,
              titre: 'FACTURE COMPLÉMENTAIRE ${op.titre}',
              detail: dossier,
              montant: op.montant,
              estReglement: false,
              complementaire: true,
            ),
          );
        } else if (op.type == DossierOperationType.clientPayment) {
          rows.add(
            _OperationClient(
              date: date,
              titre: 'RÈGLEMENT ${op.titre.split(' • ').first}',
              detail: [
                dossier,
                if (op.modePaiement.isNotEmpty) op.modePaiement,
                if (op.codeJournal.isNotEmpty) 'Journal ${op.codeJournal}',
              ].join(' • '),
              montant: op.montant,
              estReglement: true,
            ),
          );
        }
      }
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final dossiers = _dossiersClient;
    final facture = dossiers.fold<double>(
      0,
      (s, d) => s + d.totalFacturesClient,
    );
    final regle = dossiers.fold<double>(
      0,
      (s, d) => s + d.totalReglementsClient,
    );
    final initial = client.soldeInitial;
    final reste = initial + facture - regle;
    final all = _operations;
    final rows = all.where((o) {
      return switch (_filtre) {
        _FiltreHistorique.tout => true,
        _FiltreHistorique.factures => !o.estReglement,
        _FiltreHistorique.reglements => o.estReglement,
      };
    }).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: _journalBlue,
        foregroundColor: Colors.white,
        title: Text(
          client.nom.toUpperCase(),
          style: const TextStyle(fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'Imprimer le relevé du client',
            onPressed: () => _print(all, facture, regle, reste),
            icon: const Icon(Icons.print_rounded),
          ),
        ],
      ),
      body: ListView(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Wrap(
              spacing: 28,
              runSpacing: 8,
              children: [
                _info(Icons.person_rounded, client.nom),
                if (client.societe.isNotEmpty)
                  _info(Icons.business_rounded, client.societe),
                if (client.telephone.isNotEmpty)
                  _info(Icons.phone_rounded, client.telephone),
                if (client.compteComptable.isNotEmpty)
                  _info(Icons.account_balance_rounded, client.compteComptable),
                _info(
                  Icons.folder_copy_rounded,
                  '${dossiers.length} dossier(s)',
                ),
              ],
            ),
          ),
          Container(
            key: const ValueKey('client-history-summary'),
            color: const Color(0xFFE3F2FD),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(
              children: [
                if (initial != 0)
                  _ligneTotal('Solde initial', initial, Colors.black87),
                _ligneTotal('Total Facturé (Net)', facture, Colors.black87),
                _ligneTotal('Total Réglé', regle, const Color(0xFF2E7D32)),
                const Divider(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'RESTE À PAYER',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${formatCurrency(reste)} FCFA',
                      key: const ValueKey('client-history-reste'),
                      style: TextStyle(
                        color: reste > 0 ? Colors.red : const Color(0xFF2E7D32),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                const Text(
                  'HISTORIQUE DES OPÉRATIONS',
                  style: TextStyle(
                    color: _gridMuted,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                SegmentedButton<_FiltreHistorique>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _FiltreHistorique.tout,
                      label: Text('Tout (${all.length})'),
                    ),
                    ButtonSegment(
                      value: _FiltreHistorique.factures,
                      label: Text(
                        'Factures (${all.where((o) => !o.estReglement).length})',
                      ),
                    ),
                    ButtonSegment(
                      value: _FiltreHistorique.reglements,
                      label: Text(
                        'Règlements (${all.where((o) => o.estReglement).length})',
                      ),
                    ),
                  ],
                  selected: {_filtre},
                  onSelectionChanged: (s) => setState(() => _filtre = s.first),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'Aucune opération pour ce client.',
                  style: TextStyle(color: _gridMuted),
                ),
              ),
            ),
          for (final o in rows) _carte(o),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: _gridMuted),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 15)),
    ],
  );

  Widget _ligneTotal(String label, double value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        Text(
          '${formatCurrency(value)} FCFA',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _carte(_OperationClient o) {
    final color = o.estReglement
        ? const Color(0xFF2E7D32)
        : const Color(0xFF1E88E5);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: Icon(
          o.estReglement
              ? Icons.arrow_downward_rounded
              : o.complementaire
              ? Icons.post_add_rounded
              : Icons.arrow_upward_rounded,
          color: color,
        ),
        title: Text(o.titre, style: const TextStyle(fontSize: 16)),
        subtitle: Text(
          'Date : ${o.date.year == 0 ? '-' : _dateFormat.format(o.date)}  •  ${o.detail}',
        ),
        trailing: Text(
          '${o.estReglement ? '-' : ''}${formatCurrency(o.montant)} F',
          style: TextStyle(
            color: o.estReglement ? color : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _print(
    List<_OperationClient> rows,
    double facture,
    double regle,
    double reste,
  ) async {
    final logo = await _loadPdfLogo();
    final client = widget.client;
    final doc = pw.Document(
      title: 'Relevé client ${client.nom}',
      author: 'Sylla Transit & Transport',
    );
    // Solde progressif, du plus ancien au plus récent.
    final chrono = rows.reversed.toList();
    var solde = client.soldeInitial;
    final soldes = <double>[];
    for (final o in chrono) {
      solde += o.estReglement ? -o.montant : o.montant;
      soldes.add(solde);
    }
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (logo != null) ...[
                pw.Image(logo, height: 40),
                pw.SizedBox(width: 10),
              ],
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'STT',
                    style: pw.TextStyle(
                      color: _pdfPrimary,
                      fontSize: 18,
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
              pw.Text(
                'RELEVÉ CLIENT',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          _pdfInfoGrid([
            ('Client', client.nom),
            ('Téléphone', client.telephone),
            ('Compte', client.compteComptable),
            ('Édité le', DateFormat('dd/MM/yyyy').format(DateTime.now())),
          ]),
          pw.SizedBox(height: 10),
          _pdfTable(
            ['Date', 'Opération', 'Détail', 'Débit', 'Crédit', 'Solde'],
            [
              for (final (i, o) in chrono.indexed)
                [
                  o.date.year == 0 ? '' : _dateFormat.format(o.date),
                  o.titre,
                  o.detail.replaceAll('•', '-'),
                  o.estReglement ? '' : formatCurrency(o.montant),
                  o.estReglement ? formatCurrency(o.montant) : '',
                  formatCurrency(soldes[i]),
                ],
            ],
            numericColumns: {3, 4, 5},
            fontSize: 8.5,
          ),
          pw.SizedBox(height: 10),
          _pdfTotals([
            ('Total facturé', '${formatCurrency(facture)} FCFA'),
            ('Total réglé', '${formatCurrency(regle)} FCFA'),
            ('RESTE À PAYER', '${formatCurrency(reste)} FCFA'),
          ]),
        ],
      ),
    );
    await Printing.layoutPdf(
      name: 'Releve client ${client.nom}',
      onLayout: (_) => doc.save(),
    );
  }
}
