part of '../main.dart';

// --- FACTURES TRANSPORTEUR : un camion, les conteneurs transportés, avance et règlements ---

// Conteneur transporté par un camion (saisi dans une facture transitaire).
class _CarriedContainer {
  final FactureTransitaire source;
  final FactureTransitaireLigne line;

  const _CarriedContainer(this.source, this.line);

  String get cle => line.cleConteneur;
}

List<_CarriedContainer> _carriedContainers(
  List<FactureTransitaire> transitInvoices,
  List<FactureTransporteur> carrierInvoices,
  String transporteurId, {
  String? exceptFactureId,
}) {
  final taken = {
    for (final f in carrierInvoices)
      if (f.id != exceptFactureId)
        for (final l in f.lignes)
          if (l.numeroConteneur.isNotEmpty) l.cleConteneur,
  };
  return [
    for (final f in transitInvoices)
      for (final l in f.lignes)
        if (l.transporteurId == transporteurId &&
            !taken.contains(l.cleConteneur))
          _CarriedContainer(f, l),
  ];
}

class FactureTransporteurPage extends StatefulWidget {
  final List<TransitDossier> dossiers;
  final List<Prestataire> prestataires;
  final List<JournalCode> journals;
  final List<ModeReglement> modes;
  final List<FactureTransitaire> facturesTransitaire;
  final List<FactureTransporteur> factures;

  const FactureTransporteurPage({
    super.key,
    required this.dossiers,
    required this.prestataires,
    required this.journals,
    required this.facturesTransitaire,
    required this.factures,
    this.modes = const [],
  });

  @override
  State<FactureTransporteurPage> createState() =>
      _FactureTransporteurPageState();
}

class _FactureTransporteurPageState extends State<FactureTransporteurPage> {
  DateTime? _from;
  DateTime? _to;
  Prestataire? _transporteur;
  _PaidFilter _paidFilter = _PaidFilter.all;
  String _query = '';
  FactureTransporteur? _selected;
  ReglementFacture? _selectedPayment;

  String _partnerName(String id) =>
      widget.prestataires.where((p) => p.id == id).firstOrNull?.entreprise ??
      '';
  String _dossierNumber(String id) =>
      widget.dossiers.where((d) => d.id == id).firstOrNull?.numDossier ?? '';

  String _nth(List<String> values, int index) =>
      index < values.length ? values[index] : '';

  List<FactureTransporteur> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.factures.where((f) {
      if (!_inPeriod(_parseFrDate(f.dateEmission), _from, _to)) return false;
      if (_transporteur != null && f.transporteurId != _transporteur!.id) {
        return false;
      }
      if (_paidFilter == _PaidFilter.paid && !f.estPayee) return false;
      if (_paidFilter == _PaidFilter.unpaid && f.estPayee) return false;
      if (query.isEmpty) return true;
      return _columns
          .map((c) => c.value(f))
          .join(' ')
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  int get _pending {
    final carriers = _transporteur == null
        ? widget.prestataires.where((p) => p.type == 'Transporteur')
        : [_transporteur!];
    return carriers.fold(
      0,
      (sum, c) =>
          sum +
          _carriedContainers(
            widget.facturesTransitaire,
            widget.factures,
            c.id,
          ).length,
    );
  }

  List<String> _bls(FactureTransporteur f) =>
      {for (final l in f.lignes) l.bl}.toList();
  List<String> _containers(FactureTransporteur f) => [
    for (final l in f.lignes) l.numeroConteneur,
  ];

  late final List<ErpGridColumn<FactureTransporteur>> _columns = [
    ErpGridColumn(
      label: 'ID',
      width: 70,
      numeric: true,
      value: (f) => f.numero == 0 ? '' : '${f.numero}',
      sortValue: (f) => f.numero,
    ),
    ErpGridColumn(
      label: 'Statut',
      width: 120,
      value: (f) => f.estPayee ? 'Payée' : 'Non payée',
      builder: (f) => f.estPayee
          ? const ErpStatusChip('Payée', Color(0xFF15803D))
          : const ErpStatusChip('Non payée', Color(0xFFEA580C)),
    ),
    ErpGridColumn(label: 'N° facture', width: 160, value: (f) => f.reference),
    ErpGridColumn(
      label: 'Transporteur',
      width: 170,
      value: (f) => _partnerName(f.transporteurId),
    ),
    ErpGridColumn(
      label: 'Date de facture',
      width: 115,
      value: (f) => f.dateEmission,
      sortValue: (f) => _parseFrDate(f.dateEmission) ?? DateTime(0),
    ),
    ErpGridColumn(label: 'Plaque véhicule', width: 130, value: (f) => f.plaque),
    ErpGridColumn(
      label: 'Numéro dossier',
      width: 200,
      value: (f) =>
          {for (final l in f.lignes) _dossierNumber(l.dossierId)}.join(', '),
    ),
    for (var i = 0; i < 3; i++)
      ErpGridColumn(
        label: 'BL ${i + 1}',
        width: 110,
        value: (f) => _nth(_bls(f), i),
      ),
    for (var i = 0; i < 3; i++)
      ErpGridColumn(
        label: 'Conteneur ${i + 1}',
        width: 130,
        value: (f) => _nth(_containers(f), i),
      ),
    ErpGridColumn(
      label: 'Total TTC',
      width: 130,
      numeric: true,
      value: (f) => _amountText(f.montant),
      sortValue: (f) => f.montant,
    ),
    ErpGridColumn(
      label: 'Avance camion',
      width: 130,
      numeric: true,
      value: (f) => _amountText(f.avance),
      sortValue: (f) => f.avance,
    ),
    ErpGridColumn(
      label: 'Total payé',
      width: 130,
      numeric: true,
      value: (f) => _amountText(f.totalRegle),
      sortValue: (f) => f.totalRegle,
    ),
    ErpGridColumn(
      label: 'Reliquat',
      width: 130,
      numeric: true,
      value: (f) => _amountText(f.reliquat),
      sortValue: (f) => f.reliquat,
      builder: (f) => Text(
        _amountText(f.reliquat),
        style: TextStyle(
          color: f.reliquat > 0
              ? const Color(0xFFDC2626)
              : const Color(0xFF15803D),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    ErpGridColumn(label: 'Saisi par', width: 140, value: (f) => f.auteur),
    ErpGridColumn(
      label: 'Saisi le',
      width: 105,
      value: (f) => f.dateSaisie.split(' ').first,
    ),
    ErpGridColumn(
      label: 'Heure saisie',
      width: 100,
      value: (f) =>
          f.dateSaisie.contains(' ') ? f.dateSaisie.split(' ').last : '',
    ),
    ErpGridColumn(
      label: 'Observations',
      width: 220,
      value: (f) => f.observations,
    ),
  ];

  late final List<ErpGridColumn<ReglementFacture>> _paymentColumns = [
    ErpGridColumn(
      label: 'Date règlement',
      width: 120,
      value: (r) => r.date.split(' ').first,
      sortValue: (r) => _parseFrDate(r.date) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Montant',
      width: 125,
      numeric: true,
      value: (r) => _amountText(r.montant),
      sortValue: (r) => r.montant,
    ),
    ErpGridColumn(
      label: 'Caisse',
      width: 150,
      value: (r) => _journalLabel(r.codeJournal),
    ),
    ErpGridColumn(
      label: 'Mode de paiement',
      width: 140,
      value: (r) => r.modePaiement,
    ),
    ErpGridColumn(
      label: 'Numéro de chèque',
      width: 130,
      value: (r) => r.numeroCheque,
    ),
    ErpGridColumn(
      label: 'Observations',
      width: 200,
      value: (r) => r.observations,
    ),
    ErpGridColumn(label: 'Auteur saisie', width: 140, value: (r) => r.auteur),
    ErpGridColumn(
      label: 'Date saisie',
      width: 105,
      value: (r) => r.saisiLe.split(' ').first,
    ),
    ErpGridColumn(
      label: 'Heure saisie',
      width: 95,
      value: (r) => r.saisiLe.contains(' ') ? r.saisiLe.split(' ').last : '',
    ),
  ];

  String _journalLabel(String code) {
    final journal = widget.journals.where((j) => j.code == code).firstOrNull;
    return journal == null ? code : '${journal.code} • ${journal.intitule}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final selected = rows.any((f) => f.id == _selected?.id) ? _selected : null;
    final payments = selected?.reglements ?? const <ReglementFacture>[];
    final selectedPayment = payments.any((p) => p.id == _selectedPayment?.id)
        ? _selectedPayment
        : null;
    final total = rows.fold<double>(0, (s, f) => s + f.montant);
    final advances = rows.fold<double>(0, (s, f) => s + f.avance);
    final paid = rows.fold<double>(0, (s, f) => s + f.totalRegle);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1150;
          final invoices = _panel(
            title: 'Factures transporteurs',
            icon: Icons.local_shipping_rounded,
            child: ErpGrid<FactureTransporteur>(
              key: const ValueKey('carrier-invoices-grid'),
              columns: _columns,
              rows: rows,
              rowId: (f) => f.id,
              selected: selected,
              onSelect: (f) => setState(() {
                _selected = f;
                _selectedPayment = null;
              }),
              onOpen: _edit,
              emptyIcon: Icons.receipt_long_outlined,
              emptyText: widget.factures.isEmpty
                  ? 'Aucune facture transporteur. Cliquez sur « Nouvelle facture ».'
                  : 'Aucune facture ne correspond aux filtres.',
            ),
          );
          final paymentsPanel = _panel(
            title: 'Règlements transporteur',
            icon: Icons.payments_rounded,
            actions: [
              ErpActionButton(
                key: const ValueKey('carrier-payment-new'),
                label: 'Nouveau paiement',
                icon: Icons.add_card_rounded,
                primary: true,
                color: const Color(0xFF15803D),
                onPressed: selected == null
                    ? null
                    : () => _addPayment(selected),
              ),
              ErpActionButton(
                key: const ValueKey('carrier-payment-delete'),
                label: 'Supprimer',
                icon: Icons.delete_outline_rounded,
                color: const Color(0xFFDC2626),
                onPressed: selected == null || selectedPayment == null
                    ? null
                    : () => _deletePayment(selected, selectedPayment),
              ),
            ],
            child: ErpGrid<ReglementFacture>(
              key: const ValueKey('carrier-payments-grid'),
              columns: _paymentColumns,
              rows: payments,
              rowId: (r) => r.id,
              selected: selectedPayment,
              onSelect: (r) => setState(() => _selectedPayment = r),
              emptyIcon: Icons.account_balance_wallet_outlined,
              emptyText: selected == null
                  ? 'Sélectionnez une facture pour voir ses règlements.'
                  : 'Aucun règlement pour cette facture.',
            ),
          );
          return ListView(
            padding: EdgeInsets.all(wide ? 18 : 10),
            children: [
              _buildToolbar(selected, total, advances, paid),
              const SizedBox(height: 12),
              _buildFilters(rows.length),
              const SizedBox(height: 12),
              if (wide)
                SizedBox(
                  height: math.max(560, constraints.maxHeight - 330),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 7, child: invoices),
                      const SizedBox(width: 12),
                      Expanded(flex: 4, child: paymentsPanel),
                    ],
                  ),
                )
              else ...[
                SizedBox(height: 420, child: invoices),
                const SizedBox(height: 12),
                SizedBox(height: 360, child: paymentsPanel),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
    List<Widget> actions = const [],
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _gridBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: _gridAccent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: _gridText,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            ...actions,
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: child),
      ],
    ),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _gridBorder),
    ),
    child: child,
  );

  Widget _buildToolbar(
    FactureTransporteur? selected,
    double total,
    double advances,
    double paid,
  ) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_gridPrimary, _gridAccent],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.local_shipping_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Factures Transporteur',
                style: TextStyle(
                  color: _gridText,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ErpMetricTile(
              label: 'Total facture',
              value: _amountText(total),
              color: _gridAccent,
              icon: Icons.receipt_long_rounded,
            ),
            ErpMetricTile(
              label: 'Avances camion',
              value: _amountText(advances),
              color: const Color(0xFF7C3AED),
              icon: Icons.local_gas_station_rounded,
            ),
            ErpMetricTile(
              label: 'Total payé',
              value: _amountText(paid),
              color: const Color(0xFF15803D),
              icon: Icons.check_circle_outline_rounded,
            ),
            ErpMetricTile(
              label: 'Reliquat',
              value: _amountText(total - advances - paid),
              color: const Color(0xFFDC2626),
              icon: Icons.hourglass_bottom_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ErpActionButton(
              key: const ValueKey('carrier-invoice-new'),
              label: 'Nouvelle facture',
              icon: Icons.note_add_rounded,
              primary: true,
              onPressed: () => _openEditor(null),
            ),
            ErpActionButton(
              key: const ValueKey('carrier-invoice-edit'),
              label: 'Modifier',
              icon: Icons.edit_rounded,
              onPressed: selected == null ? null : () => _edit(selected),
            ),
            ErpActionButton(
              key: const ValueKey('carrier-invoice-delete'),
              label: 'Supprimer',
              icon: Icons.delete_outline_rounded,
              color: const Color(0xFFDC2626),
              onPressed: selected == null ? null : () => _delete(selected),
            ),
            ErpActionButton(
              label: 'Exporter',
              icon: Icons.file_download_outlined,
              onPressed: () => _exportGrid(
                context,
                baseName: 'factures_transporteur',
                columns: _columns,
                rows: _filtered,
              ),
            ),
            ErpActionButton(
              label: 'Imprimer',
              icon: Icons.print_outlined,
              onPressed: selected == null ? null : () => _print(selected),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildFilters(int count) => _card(
    Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ErpDateFilter(
          label: 'Période du',
          value: _from,
          onChanged: (value) => setState(() => _from = value),
        ),
        ErpDateFilter(
          label: 'Au',
          value: _to,
          onChanged: (value) => setState(() => _to = value),
        ),
        SizedBox(
          width: 250,
          child: SearchableDropdownFormField<Prestataire>(
            key: const ValueKey('carrier-invoice-filter'),
            options: widget.prestataires
                .where((p) => p.type == 'Transporteur')
                .toList(),
            value: _transporteur,
            label: 'Transporteur',
            emptyText: 'Tous les transporteurs',
            required: false,
            displayString: (p) => p.entreprise,
            onChanged: (p) => setState(() => _transporteur = p),
          ),
        ),
        SegmentedButton<_PaidFilter>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _PaidFilter.all, label: Text('Toutes')),
            ButtonSegment(value: _PaidFilter.paid, label: Text('Acquittées')),
            ButtonSegment(
              value: _PaidFilter.unpaid,
              label: Text('Non acquittées'),
            ),
          ],
          selected: {_paidFilter},
          onSelectionChanged: (value) =>
              setState(() => _paidFilter = value.first),
        ),
        SizedBox(
          width: 250,
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Facture, plaque, BL, conteneur…',
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count facture(s) • $_pending conteneur(s) transporté(s) à facturer',
            key: const ValueKey('carrier-invoice-count'),
            style: const TextStyle(
              color: Color(0xFFC2410C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _edit(FactureTransporteur facture) async {
    if (facture.reglements.isNotEmpty) {
      await _showInfoAlert(
        context,
        title: 'Facture déjà réglée',
        message:
            'Cette facture a déjà des règlements : elle ne peut plus être modifiée. Supprimez d’abord ses règlements si une correction est nécessaire.',
      );
      return;
    }
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => _FactureTransporteurQuickEdit(
        facture: facture,
        prestataires: widget.prestataires,
        factures: widget.factures,
      ),
    );
    if (!mounted) return;
    if (result == _openContainers) {
      await _openEditor(facture);
    } else if (result is FactureTransporteur) {
      setState(() {
        final index = widget.factures.indexWhere((f) => f.id == result.id);
        if (index >= 0) widget.factures[index] = result;
        _selected = result;
      });
    }
  }

  Future<void> _openEditor(FactureTransporteur? facture) async {
    final saved = await showDialog<FactureTransporteur>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FactureTransporteurEditor(
        initial: facture,
        dossiers: widget.dossiers,
        prestataires: widget.prestataires,
        journals: widget.journals,
        facturesTransitaire: widget.facturesTransitaire,
        factures: widget.factures,
        transporteur: facture == null ? _transporteur : null,
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      final index = widget.factures.indexWhere((f) => f.id == saved.id);
      if (index < 0) {
        widget.factures.add(saved);
      } else {
        widget.factures[index] = saved;
      }
      _selected = saved;
    });
  }

  Future<void> _delete(FactureTransporteur facture) async {
    if (facture.reglements.isNotEmpty) {
      await _showInfoAlert(
        context,
        title: 'Suppression impossible',
        message:
            'Cette facture a déjà des règlements. Supprimez d’abord les règlements.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
        title: const Text('Supprimer cette facture ?'),
        content: Text(
          'La facture ${facture.reference} (${_amountText(facture.montant)}) sera supprimée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await _persist(
      context,
      () => erpBackend.deleteFactureTransporteur(facture),
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      widget.factures.removeWhere((f) => f.id == facture.id);
      _selected = null;
    });
  }

  Future<void> _addPayment(FactureTransporteur facture) async {
    if (facture.reliquat <= 0) {
      await _showInfoAlert(
        context,
        title: 'Facture payée',
        message: 'Le net à payer de cette facture est déjà entièrement réglé.',
      );
      return;
    }
    if (widget.journals.isEmpty && widget.modes.isEmpty) {
      await _showInfoAlert(
        context,
        title: 'Caisse requise',
        message:
            'Créez d’abord une caisse ou une banque dans Comptabilité > Code journaux.',
      );
      return;
    }
    final operation = await showDialog<DossierOperation>(
      context: context,
      builder: (context) => _PaymentDialog(
        journals: widget.journals,
        modes: widget.modes,
        balance: facture.reliquat,
        invoiceReference: facture.reference,
      ),
    );
    if (operation == null || !mounted) return;
    final payment = ReglementFacture(
      date: operation.date,
      montant: operation.montant,
      codeJournal: operation.codeJournal,
      modePaiement: operation.modePaiement,
      numeroCheque: operation.numeroCheque,
      observations: operation.observations,
      auteur: operation.auteur,
      saisiLe: operation.saisiLe,
    );
    facture.reglements.add(payment);
    if (!await _persist(
      context,
      () => erpBackend.saveFactureTransporteur(facture),
    )) {
      facture.reglements.remove(payment);
    }
    if (mounted) setState(() => _selectedPayment = null);
  }

  Future<void> _deletePayment(
    FactureTransporteur facture,
    ReglementFacture payment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce règlement ?'),
        content: Text(
          'Règlement du ${payment.date.split(' ').first} de ${_amountText(payment.montant)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final index = facture.reglements.indexOf(payment);
    facture.reglements.removeAt(index);
    if (!await _persist(
      context,
      () => erpBackend.saveFactureTransporteur(facture),
    )) {
      facture.reglements.insert(index, payment);
    }
    if (mounted) setState(() => _selectedPayment = null);
  }

  Future<void> _print(FactureTransporteur f) async {
    final logo = await _loadPdfLogo();
    final doc = pw.Document(
      title: 'Facture ${f.reference}',
      author: 'Sylla Transit & Transport',
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Row(
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
                  pw.Text(
                    'Transporteur : ${_partnerName(f.transporteurId)}  •  Camion : ${f.plaque}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'FACTURE TRANSPORTEUR',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'N° ${f.reference} du ${f.dateEmission}',
                    style: const pw.TextStyle(fontSize: 9),
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
          _pdfTable(
            ['Dossier', 'BL', 'Conteneur', 'Montant (FCFA)'],
            [
              for (final l in f.lignes)
                [
                  _dossierNumber(l.dossierId),
                  l.bl,
                  l.numeroConteneur,
                  formatCurrency(l.montant),
                ],
            ],
            numericColumns: {3},
          ),
          pw.SizedBox(height: 12),
          _pdfTotals([
            ('Total TTC', '${formatCurrency(f.montant)} FCFA'),
            ('Avance camion', '${formatCurrency(f.avance)} FCFA'),
            ('Net à payer', '${formatCurrency(f.netAPayer)} FCFA'),
            ('Total payé', '${formatCurrency(f.totalRegle)} FCFA'),
            ('Reliquat', '${formatCurrency(f.reliquat)} FCFA'),
          ]),
          if (f.observations.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Observations : ${f.observations}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ],
      ),
    );
    await Printing.layoutPdf(
      name: 'Facture ${f.reference}',
      onLayout: (_) => doc.save(),
    );
  }
}

class _CarrierLineDraft {
  final String dossierId;
  final String bl;
  final String numeroConteneur;
  final double avanceSource;
  final montant = TextEditingController();

  _CarrierLineDraft({
    required this.dossierId,
    required this.bl,
    required this.numeroConteneur,
    required double amount,
    this.avanceSource = 0,
  }) {
    montant.text = amount == 0 ? '' : amount.toStringAsFixed(0);
  }

  String get cle => '$dossierId|${numeroConteneur.toUpperCase()}';
  double get value => _parseAmount(montant.text) ?? 0;
}

// Saisie d'une facture transporteur.
class _FactureTransporteurEditor extends StatefulWidget {
  final FactureTransporteur? initial;
  final List<TransitDossier> dossiers;
  final List<Prestataire> prestataires;
  final List<JournalCode> journals;
  final List<FactureTransitaire> facturesTransitaire;
  final List<FactureTransporteur> factures;
  final Prestataire? transporteur;

  const _FactureTransporteurEditor({
    required this.initial,
    required this.dossiers,
    required this.prestataires,
    required this.journals,
    required this.facturesTransitaire,
    required this.factures,
    this.transporteur,
  });

  @override
  State<_FactureTransporteurEditor> createState() =>
      _FactureTransporteurEditorState();
}

class _FactureTransporteurEditorState extends State<_FactureTransporteurEditor>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _observations = TextEditingController();
  final _advance = TextEditingController();
  final _totalCtrl = TextEditingController();
  // Vrai dès que l'utilisateur saisit lui-même le Total TTC.
  bool _manualTotal = false;
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final List<_CarrierLineDraft> _lines = [];
  Prestataire? _transporteur;
  Vehicule? _vehicule;
  String? _advanceJournal;
  DateTime _date = DateTime.now();
  _CarriedContainer? _selectedAvailable;
  bool _saving = false;

  List<Prestataire> get _carriers =>
      widget.prestataires.where((p) => p.type == 'Transporteur').toList();

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    if (f == null) {
      _transporteur = widget.transporteur;
      _reference.text = _nextInvoiceNumber(
        'FAC-TRP',
        widget.factures.map((x) => x.reference),
        _date,
      );
      return;
    }
    _transporteur = _carriers
        .where((p) => p.id == f.transporteurId)
        .firstOrNull;
    _vehicule = _transporteur?.vehicules
        .where((v) => _normalizePlate(v.plaque) == _normalizePlate(f.plaque))
        .firstOrNull;
    _reference.text = f.reference;
    _observations.text = f.observations;
    _advance.text = f.avance == 0 ? '' : f.avance.toStringAsFixed(0);
    _totalCtrl.text = f.montant == 0 ? '' : f.montant.toStringAsFixed(0);
    final linesSum = f.lignes.fold<double>(0, (s, l) => s + l.montant);
    _manualTotal = (linesSum - f.montant).abs() > 0.5;
    if (widget.journals.any((j) => j.code == f.journalAvance)) {
      _advanceJournal = f.journalAvance;
    }
    _date = _parseFrDate(f.dateEmission) ?? DateTime.now();
    _lines.addAll(
      f.lignes.map(
        (l) => _CarrierLineDraft(
          dossierId: l.dossierId,
          bl: l.bl,
          numeroConteneur: l.numeroConteneur,
          amount: l.montant,
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_reference, _observations, _advance, _totalCtrl]) {
      c.dispose();
    }
    _tabs.dispose();
    for (final l in _lines) {
      l.montant.dispose();
    }
    super.dispose();
  }

  String get _plate => _vehicule?.plaque ?? '';
  double get _linesTotal => _lines.fold(0, (s, l) => s + l.value);
  double get _total => _parseAmount(_totalCtrl.text) ?? 0;

  void _syncTotal() {
    if (_manualTotal) return;
    final sum = _linesTotal;
    _totalCtrl.text = sum == 0 ? '' : sum.toStringAsFixed(0);
  }

  double get _advanceValue => _parseAmount(_advance.text) ?? 0;

  List<_CarriedContainer> get _available {
    final carrier = _transporteur;
    if (carrier == null) return const [];
    final inInvoice = _lines.map((l) => l.cle).toSet();
    return _carriedContainers(
      widget.facturesTransitaire,
      widget.factures,
      carrier.id,
      exceptFactureId: widget.initial?.id,
    ).where((c) {
      if (inInvoice.contains(c.cle)) return false;
      if (_plate.isEmpty) return true;
      return _normalizePlate(c.line.plaque) == _normalizePlate(_plate);
    }).toList();
  }

  String _dossierNumber(String id) =>
      widget.dossiers.where((d) => d.id == id).firstOrNull?.numDossier ?? '';

  late final List<ErpGridColumn<_CarriedContainer>> _availableColumns = [
    ErpGridColumn(label: 'Véhicule', width: 120, value: (c) => c.line.plaque),
    ErpGridColumn(label: 'BL', width: 120, value: (c) => c.line.bl),
    ErpGridColumn(
      label: 'Numéro conteneur',
      width: 150,
      value: (c) => c.line.numeroConteneur,
    ),
    ErpGridColumn(
      label: 'Dossier',
      width: 160,
      value: (c) => _dossierNumber(c.line.dossierId),
    ),
    ErpGridColumn(
      label: 'Date de départ',
      width: 115,
      value: (c) => c.line.dateDepart,
    ),
    ErpGridColumn(
      label: 'Facture transitaire',
      width: 160,
      value: (c) => c.source.reference,
    ),
    ErpGridColumn(
      label: 'Transport dû',
      width: 130,
      numeric: true,
      value: (c) => _amountText(c.line.montantTransport),
    ),
    ErpGridColumn(
      label: 'Avance camion',
      width: 130,
      numeric: true,
      value: (c) => _amountText(c.line.avanceCamion),
    ),
  ];

  void _add(Iterable<_CarriedContainer> containers) => setState(() {
    var advance = _advanceValue;
    for (final c in containers) {
      _lines.add(
        _CarrierLineDraft(
          dossierId: c.line.dossierId,
          bl: c.line.bl,
          numeroConteneur: c.line.numeroConteneur,
          amount: c.line.montantTransport,
          avanceSource: c.line.avanceCamion,
        ),
      );
      advance += c.line.avanceCamion;
      if (_vehicule == null && c.line.plaque.isNotEmpty) {
        _vehicule = _transporteur?.vehicules
            .where(
              (v) =>
                  _normalizePlate(v.plaque) == _normalizePlate(c.line.plaque),
            )
            .firstOrNull;
      }
    }
    // L'avance camion saisie dans la facture transitaire est reprise.
    _advance.text = advance == 0 ? '' : advance.toStringAsFixed(0);
    _selectedAvailable = null;
    _syncTotal();
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final available = _available;
    final vehicles = _transporteur?.vehicules ?? const <Vehicule>[];
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: math.min(screen.width - 24, 1250),
        height: math.min(screen.height - 24, 900),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _dialogHeader(
                icon: Icons.local_shipping_rounded,
                title: widget.initial == null
                    ? 'Nouvelle facture transporteur'
                    : 'Modifier la facture transporteur',
                subtitle: _transporteur == null
                    ? 'Choisissez le transporteur et son camion'
                    : '${_transporteur!.entreprise}${_plate.isEmpty ? '' : ' • $_plate'}',
                onClose: () => Navigator.pop(context),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: screen.height * 0.4),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 250,
                        child: AbsorbPointer(
                          absorbing: _lines.isNotEmpty,
                          child: SearchableDropdownFormField<Prestataire>(
                            key: ValueKey(
                              'carrier-invoice-partner-${_lines.isNotEmpty}',
                            ),
                            options: _carriers,
                            value: _transporteur,
                            label: 'Transporteur *',
                            emptyText:
                                'Ajoutez un transporteur dans Transport > Transporteurs',
                            displayString: (p) => p.entreprise,
                            onChanged: (p) => setState(() {
                              if (p == null) return;
                              _transporteur = p;
                              _vehicule = null;
                            }),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<Vehicule?>(
                          key: ValueKey(
                            'carrier-invoice-plate-${_transporteur?.id}-${_vehicule?.id}',
                          ),
                          isExpanded: true,
                          initialValue: _vehicule,
                          decoration: _inputDecoration(
                            'Plaque véhicule',
                            icon: Icons.local_shipping_outlined,
                          ),
                          items: [
                            const DropdownMenuItem<Vehicule?>(
                              value: null,
                              child: Text('Tous ses camions'),
                            ),
                            for (final v in vehicles)
                              DropdownMenuItem<Vehicule?>(
                                value: v,
                                child: Text(
                                  v.chauffeur.isEmpty
                                      ? v.plaque
                                      : '${v.plaque} • ${v.chauffeur}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _vehicule = v),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextFormField(
                          key: const ValueKey('carrier-invoice-number'),
                          controller: _reference,
                          decoration: _inputDecoration(
                            'Numéro de facture *',
                            icon: Icons.tag_rounded,
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Champ obligatoire';
                            final duplicate = widget.factures.any(
                              (f) =>
                                  f.id != widget.initial?.id &&
                                  _normalizeUniqueValue(f.reference) ==
                                      _normalizeUniqueValue(text),
                            );
                            return duplicate
                                ? 'Ce numéro de facture existe déjà'
                                : null;
                          },
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: _FormDateField(
                          label: 'Date de facture',
                          value: _date,
                          clearable: false,
                          onChanged: (d) => setState(() => _date = d ?? _date),
                        ),
                      ),
                      SizedBox(
                        width: 320,
                        child: TextFormField(
                          controller: _observations,
                          decoration: _inputDecoration(
                            'Observations',
                            icon: Icons.notes_rounded,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: TextFormField(
                          key: const ValueKey('carrier-invoice-advance'),
                          controller: _advance,
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _inputDecoration(
                            'Avance camion',
                            icon: Icons.local_gas_station_outlined,
                          ).copyWith(suffixText: 'F'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: DropdownButtonFormField<String?>(
                          isExpanded: true,
                          initialValue: _advanceJournal,
                          decoration: _inputDecoration(
                            'Caisse de l’avance',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Non précisée'),
                            ),
                            for (final j in widget.journals)
                              DropdownMenuItem<String?>(
                                value: j.code,
                                child: Text(
                                  '${j.code} • ${j.intitule}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _advanceJournal = v),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: TextFormField(
                          key: const ValueKey('carrier-invoice-total'),
                          controller: _totalCtrl,
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration:
                              _inputDecoration(
                                'Total TTC',
                                icon: Icons.receipt_long_outlined,
                              ).copyWith(
                                suffixText: 'F',
                                helperText: _manualTotal && _lines.isNotEmpty
                                    ? 'Conteneurs : ${formatCurrency(_linesTotal)}'
                                    : null,
                              ),
                          onChanged: (_) => setState(() => _manualTotal = true),
                        ),
                      ),
                      _infoTile(
                        'Net à payer',
                        _amountText(_total - _advanceValue),
                        width: 170,
                      ),
                    ],
                  ),
                ),
              ),
              Material(
                color: Colors.white,
                child: TabBar(
                  controller: _tabs,
                  labelColor: _gridPrimary,
                  indicatorColor: _gridAccent,
                  tabs: [
                    Tab(
                      key: const ValueKey('carrier-tab-available'),
                      text:
                          '1. Conteneurs transportés disponibles (${available.length})',
                    ),
                    Tab(
                      key: const ValueKey('carrier-tab-details'),
                      text: '2. Détail de la facture (${_lines.length})',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: const Color(0xFFF4F6FB),
                  padding: const EdgeInsets.all(12),
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                key: const ValueKey('carrier-available-add'),
                                onPressed: _selectedAvailable == null
                                    ? null
                                    : () => _add([_selectedAvailable!]),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Ajouter le conteneur'),
                              ),
                              FilledButton.tonalIcon(
                                key: const ValueKey(
                                  'carrier-available-add-all',
                                ),
                                onPressed: available.isEmpty
                                    ? null
                                    : () => _add(available),
                                icon: const Icon(Icons.playlist_add_rounded),
                                label: Text(
                                  _plate.isEmpty
                                      ? 'Tout ajouter'
                                      : 'Tout ajouter pour $_plate',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ErpGrid<_CarriedContainer>(
                              key: const ValueKey('carried-containers-grid'),
                              columns: _availableColumns,
                              rows: available,
                              rowId: (c) => c.cle,
                              selected: _selectedAvailable,
                              onSelect: (c) =>
                                  setState(() => _selectedAvailable = c),
                              onOpen: (c) => _add([c]),
                              emptyIcon: Icons.inventory_2_outlined,
                              emptyText: _transporteur == null
                                  ? 'Choisissez d’abord le transporteur.'
                                  : 'Aucun conteneur transporté à facturer. Les camions se renseignent dans les factures transitaire.',
                            ),
                          ),
                        ],
                      ),
                      SingleChildScrollView(
                        child: _EditableTable(
                          emptyText:
                              'Aucun conteneur. Ajoutez-les depuis l’onglet 1.',
                          columns: const [
                            ('Dossier', 170),
                            ('BL', 130),
                            ('Numéro conteneur', 160),
                            ('Montant (FCFA)', 170),
                            ('', 52),
                          ],
                          rows: [
                            for (final (i, line) in _lines.indexed)
                              [
                                Text(_dossierNumber(line.dossierId)),
                                Text(line.bl),
                                Text(line.numeroConteneur),
                                TextFormField(
                                  key: ValueKey('carrier-line-$i-amount'),
                                  controller: line.montant,
                                  textAlign: TextAlign.right,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: _cellDecoration(hint: '0'),
                                  onChanged: (_) => setState(_syncTotal),
                                ),
                                IconButton(
                                  tooltip: 'Retirer de la facture',
                                  onPressed: () => setState(() {
                                    final removed = _lines.removeAt(i);
                                    final advance =
                                        _advanceValue - removed.avanceSource;
                                    _advance.text = advance <= 0
                                        ? ''
                                        : advance.toStringAsFixed(0);
                                    removed.montant.dispose();
                                    _syncTotal();
                                  }),
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _dialogFooter(
                onCancel: () => Navigator.pop(context),
                onValidate: _saving ? null : _save,
                validateLabel: 'Valider la facture',
                validateKey: const ValueKey('carrier-invoice-validate'),
                leading: Row(
                  children: [
                    const Text(
                      'Net à payer : ',
                      style: TextStyle(color: _gridMuted, fontSize: 15),
                    ),
                    Flexible(
                      child: Text(
                        '${formatCurrency(_total - _advanceValue)} FCFA',
                        key: const ValueKey('carrier-invoice-net'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _gridPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final carrier = _transporteur;
    String? problem;
    if (carrier == null) {
      problem = 'Choisissez le transporteur.';
    } else if (_lines.isEmpty && _total <= 0) {
      problem =
          'Ajoutez au moins un conteneur transporté ou saisissez le Total TTC.';
    } else if (_lines.any((l) => (_parseAmount(l.montant.text) ?? -1) < 0) ||
        _parseAmount(_advance.text) == null ||
        _parseAmount(_totalCtrl.text) == null ||
        _advanceValue < 0) {
      problem = 'Vérifiez les montants saisis.';
    } else if (_advanceValue > _total + 0.001) {
      problem = 'L’avance camion dépasse le montant de la facture.';
    }
    if (problem != null) {
      await _showInfoAlert(
        context,
        title: 'Facture incomplète',
        message: problem,
      );
      return;
    }
    final initial = widget.initial;
    final facture = FactureTransporteur(
      id: initial?.id ?? newLocalId('ftp'),
      numero: initial?.numero ?? 0,
      reference: _reference.text.trim(),
      transporteurId: carrier!.id,
      plaque: _plate.isNotEmpty ? _plate : (initial?.plaque ?? ''),
      dateEmission: DateFormat('dd/MM/yyyy').format(_date),
      observations: _observations.text.trim(),
      montant: _total,
      avance: _advanceValue,
      journalAvance: _advanceJournal ?? '',
      lignes: [
        for (final l in _lines)
          FactureTransporteurLigne(
            dossierId: l.dossierId,
            bl: l.bl,
            numeroConteneur: l.numeroConteneur,
            montant: l.value,
          ),
      ],
      reglements: initial?.reglements,
      version: initial?.version ?? 0,
      auteur: initial?.auteur ?? (_currentUser?.name ?? ''),
      dateSaisie:
          initial?.dateSaisie ??
          DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
    );
    setState(() => _saving = true);
    final saved = await _persist(
      context,
      () => erpBackend.saveFactureTransporteur(facture),
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    Navigator.pop(context, facture);
  }
}

const _openContainers = 'conteneurs';

// « Modifier » : transporteur, plaque, date, Total TTC, avance et observations.
class _FactureTransporteurQuickEdit extends StatefulWidget {
  final FactureTransporteur facture;
  final List<Prestataire> prestataires;
  final List<FactureTransporteur> factures;

  const _FactureTransporteurQuickEdit({
    required this.facture,
    required this.prestataires,
    required this.factures,
  });

  @override
  State<_FactureTransporteurQuickEdit> createState() =>
      _FactureTransporteurQuickEditState();
}

class _FactureTransporteurQuickEditState
    extends State<_FactureTransporteurQuickEdit> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _total = TextEditingController();
  final _advance = TextEditingController();
  final _observations = TextEditingController();
  Prestataire? _carrier;
  DateTime _date = DateTime.now();
  bool _saving = false;

  List<Prestataire> get _carriers =>
      widget.prestataires.where((p) => p.type == 'Transporteur').toList();

  @override
  void initState() {
    super.initState();
    final f = widget.facture;
    _carrier = _carriers.where((p) => p.id == f.transporteurId).firstOrNull;
    _plate.text = f.plaque;
    _total.text = f.montant == 0 ? '' : f.montant.toStringAsFixed(0);
    _advance.text = f.avance == 0 ? '' : f.avance.toStringAsFixed(0);
    _observations.text = f.observations;
    _date = _parseFrDate(f.dateEmission) ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [_plate, _total, _advance, _observations]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicles = _carrier?.vehicules ?? const <Vehicule>[];
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      title: _dialogHeader(
        icon: Icons.local_shipping_rounded,
        title: 'Modifier la facture transporteur',
        subtitle: widget.facture.reference,
        onClose: () => Navigator.pop(context),
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SearchableDropdownFormField<Prestataire>(
                  key: const ValueKey('quick-carrier'),
                  options: _carriers,
                  value: _carrier,
                  label: 'Transporteur *',
                  emptyText: 'Aucun transporteur',
                  displayString: (p) => p.entreprise,
                  onChanged: (p) => setState(() {
                    if (p == null || p.id == _carrier?.id) return;
                    _carrier = p;
                    _plate.clear();
                  }),
                ),
                const SizedBox(height: 12),
                if (vehicles.isEmpty)
                  TextFormField(
                    key: const ValueKey('quick-plate'),
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _inputDecoration(
                      'Plaque véhicule',
                      icon: Icons.local_shipping_outlined,
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey('quick-plate-${_carrier?.id}'),
                    isExpanded: true,
                    initialValue: vehicles.any((v) => v.plaque == _plate.text)
                        ? _plate.text
                        : null,
                    decoration: _inputDecoration(
                      'Plaque véhicule',
                      icon: Icons.local_shipping_outlined,
                    ),
                    items: [
                      for (final v in vehicles)
                        DropdownMenuItem(
                          value: v.plaque,
                          child: Text(
                            v.chauffeur.isEmpty
                                ? v.plaque
                                : '${v.plaque} • ${v.chauffeur}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _plate.text = v ?? ''),
                  ),
                const SizedBox(height: 12),
                _FormDateField(
                  label: 'Date de facture',
                  value: _date,
                  clearable: false,
                  onChanged: (d) => setState(() => _date = d ?? _date),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('quick-total'),
                        controller: _total,
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecoration(
                          'Total TTC *',
                          icon: Icons.receipt_long_outlined,
                        ).copyWith(suffixText: 'F'),
                        validator: (value) {
                          final amount = _parseAmount(value ?? '');
                          if (amount == null || amount <= 0) {
                            return 'Montant invalide';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('quick-advance'),
                        controller: _advance,
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecoration(
                          'Avance camion',
                          icon: Icons.local_gas_station_outlined,
                        ).copyWith(suffixText: 'F'),
                        validator: (value) {
                          final advance = _parseAmount(value ?? '');
                          final total = _parseAmount(_total.text) ?? 0;
                          if (advance == null || advance < 0) {
                            return 'Montant invalide';
                          }
                          return advance > total ? 'Dépasse le total' : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observations,
                  maxLines: 3,
                  decoration: _inputDecoration(
                    'Observations',
                    icon: Icons.notes_rounded,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('quick-containers'),
                    onPressed: () => Navigator.pop(context, _openContainers),
                    icon: const Icon(Icons.view_list_rounded),
                    label: Text(
                      'Conteneurs de la facture (${widget.facture.lignes.length})…',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          key: const ValueKey('quick-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Valider'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final carrier = _carrier;
    if (carrier == null) return;
    final f = widget.facture;
    final updated = FactureTransporteur(
      id: f.id,
      numero: f.numero,
      reference: f.reference,
      transporteurId: carrier.id,
      plaque: _plate.text.trim().toUpperCase(),
      dateEmission: DateFormat('dd/MM/yyyy').format(_date),
      observations: _observations.text.trim(),
      montant: _parseAmount(_total.text) ?? 0,
      avance: _parseAmount(_advance.text) ?? 0,
      journalAvance: f.journalAvance,
      lignes: f.lignes,
      reglements: f.reglements,
      version: f.version,
      auteur: f.auteur,
      dateSaisie: f.dateSaisie,
    );
    setState(() => _saving = true);
    final saved = await _persist(
      context,
      () => erpBackend.saveFactureTransporteur(updated),
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    Navigator.pop(context, updated);
  }
}
