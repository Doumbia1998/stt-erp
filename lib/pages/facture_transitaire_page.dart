part of '../main.dart';

// --- FACTURES TRANSITAIRE : factures, détails par véhicule/conteneur, règlements ---

enum _PaidFilter { all, paid, unpaid }

const _transitairePaymentCategory = 'Règlement Transitaire';
const _paymentModes = [
  'Espèces',
  'Chèque',
  'Virement bancaire',
  'Mobile Money',
];

class FactureTransitairePage extends StatefulWidget {
  final List<TransitDossier> dossiers;
  final List<Prestataire> prestataires;
  final List<JournalCode> journals;

  const FactureTransitairePage({
    super.key,
    required this.dossiers,
    required this.prestataires,
    required this.journals,
  });

  @override
  State<FactureTransitairePage> createState() => _FactureTransitairePageState();
}

class _FactureTransitairePageState extends State<FactureTransitairePage> {
  DateTime? _from;
  DateTime? _to;
  Prestataire? _transitaire;
  _PaidFilter _paidFilter = _PaidFilter.all;
  String _query = '';
  TransitDossier? _selected;
  DossierOperation? _selectedPayment;

  static const _kind = DossierInvoiceKind.forwarder;

  DossierInvoice _invoice(TransitDossier d) => d.factureTransitaire;
  double _paid(TransitDossier d) => d.totalRegleDe(_kind);
  double _balance(TransitDossier d) => _invoice(d).montant - _paid(d);
  bool _isPaid(TransitDossier d) => _invoice(d).montant > 0 && _balance(d) <= 0;

  List<TransitDossier> get _invoiced =>
      widget.dossiers.where((d) => _invoice(d).statut != 'Brouillon').toList();

  List<TransitDossier> get _filtered {
    final query = _query.trim().toLowerCase();
    return _invoiced.where((d) {
      final date = _parseFrDate(_invoice(d).dateEmission);
      if (!_inPeriod(date, _from, _to)) return false;
      if (_transitaire != null &&
          d.transitaireAffecte?.id != _transitaire!.id) {
        return false;
      }
      if (_paidFilter == _PaidFilter.paid && !_isPaid(d)) return false;
      if (_paidFilter == _PaidFilter.unpaid && _isPaid(d)) return false;
      if (query.isEmpty) return true;
      return _invoiceColumns
          .map((c) => c.value(d))
          .join(' ')
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  late final List<ErpGridColumn<TransitDossier>> _invoiceColumns = [
    ErpGridColumn(
      label: 'ID',
      width: 70,
      numeric: true,
      value: (d) => _invoice(d).numero == 0 ? '' : '${_invoice(d).numero}',
      sortValue: (d) => _invoice(d).numero,
    ),
    ErpGridColumn(
      label: 'Numéro de facture',
      width: 175,
      value: (d) => _invoice(d).reference,
    ),
    ErpGridColumn(
      label: 'Statut',
      width: 140,
      value: (d) => _isPaid(d) ? 'Acquittée' : 'Non acquittée',
      builder: (d) => _isPaid(d)
          ? const ErpStatusChip('Acquittée', Color(0xFF15803D))
          : const ErpStatusChip('Non acquittée', Color(0xFFEA580C)),
    ),
    ErpGridColumn(
      label: 'Date de facture',
      width: 120,
      value: (d) => _invoice(d).dateEmission,
      sortValue: (d) => _parseFrDate(_invoice(d).dateEmission) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Total TTC',
      width: 135,
      numeric: true,
      value: (d) => _amountText(_invoice(d).montant),
      sortValue: (d) => _invoice(d).montant,
    ),
    ErpGridColumn(
      label: 'Total payé',
      width: 135,
      numeric: true,
      value: (d) => _amountText(_paid(d)),
      sortValue: (d) => _paid(d),
    ),
    ErpGridColumn(
      label: 'Reliquat',
      width: 135,
      numeric: true,
      value: (d) => _amountText(_balance(d)),
      sortValue: (d) => _balance(d),
      builder: (d) => Text(
        _amountText(_balance(d)),
        style: TextStyle(
          color: _balance(d) > 0
              ? const Color(0xFFDC2626)
              : const Color(0xFF15803D),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    ErpGridColumn(
      label: 'Transitaire',
      width: 170,
      value: (d) => d.nomTransitaire,
    ),
    ErpGridColumn(label: 'Dossier', width: 180, value: (d) => d.numDossier),
    ErpGridColumn(label: 'Client', width: 180, value: (d) => d.client.nom),
    ErpGridColumn(
      label: 'Observations',
      width: 220,
      value: (d) => _invoice(d).observations,
    ),
  ];

  late final List<ErpGridColumn<InvoiceLine>> _lineColumns = [
    ErpGridColumn(
      label: 'Véhicule',
      width: 130,
      value: (l) => l.plaqueVehicule,
    ),
    ErpGridColumn(
      label: 'Tél. chauffeur',
      width: 140,
      value: (l) => l.telephoneChauffeur,
    ),
    ErpGridColumn(label: 'BL', width: 140, value: (l) => l.bl),
    ErpGridColumn(
      label: 'Montant total',
      width: 135,
      numeric: true,
      value: (l) => _amountText(l.totalPrestataire),
      sortValue: (l) => l.totalPrestataire,
    ),
    ErpGridColumn(
      label: 'Numéro conteneur',
      width: 155,
      value: (l) => l.numeroConteneur,
    ),
    ErpGridColumn(
      label: 'Type conteneur',
      width: 125,
      value: (l) => l.typeConteneur,
    ),
    ErpGridColumn(
      label: 'Marchandise',
      width: 170,
      value: (l) => l.marchandise,
    ),
    ErpGridColumn(
      label: 'Conteneurs 20 pieds',
      width: 115,
      numeric: true,
      value: (l) => l.typeConteneur.startsWith('20') ? '1' : '0',
    ),
    ErpGridColumn(
      label: 'Conteneurs 40 pieds',
      width: 115,
      numeric: true,
      value: (l) => l.typeConteneur.startsWith('40') ? '1' : '0',
    ),
    ErpGridColumn(
      label: 'Frais de transit',
      width: 130,
      numeric: true,
      value: (l) => _amountText(l.fraisTransit),
      sortValue: (l) => l.fraisTransit,
    ),
    ErpGridColumn(
      label: 'Surestaries et magasinage',
      width: 170,
      numeric: true,
      value: (l) => _amountText(l.surestariesMagasinage),
      sortValue: (l) => l.surestariesMagasinage,
    ),
    ErpGridColumn(
      label: 'Volume et poids',
      width: 130,
      numeric: true,
      value: (l) => _amountText(l.volumePoids),
      sortValue: (l) => l.volumePoids,
    ),
    ErpGridColumn(
      label: 'Frais de péage',
      width: 125,
      numeric: true,
      value: (l) => _amountText(l.fraisPeage),
      sortValue: (l) => l.fraisPeage,
    ),
    ErpGridColumn(
      label: 'Autres frais',
      width: 125,
      numeric: true,
      value: (l) => _amountText(l.autresFrais),
      sortValue: (l) => l.autresFrais,
    ),
  ];

  late final List<ErpGridColumn<DossierOperation>> _paymentColumns = [
    ErpGridColumn(
      label: 'Date règlement',
      width: 125,
      value: (op) => op.date.split(' ').first,
      sortValue: (op) => _parseFrDate(op.date) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Montant',
      width: 135,
      numeric: true,
      value: (op) => _amountText(op.montant),
      sortValue: (op) => op.montant,
    ),
    ErpGridColumn(label: 'Caisse', width: 150, value: _journalLabel),
    ErpGridColumn(
      label: 'Mode de paiement',
      width: 150,
      value: (op) => op.modePaiement,
    ),
    ErpGridColumn(
      label: 'Numéro de chèque',
      width: 140,
      value: (op) => op.numeroCheque,
    ),
    ErpGridColumn(
      label: 'Observations',
      width: 230,
      value: (op) => op.observations,
    ),
    ErpGridColumn(label: 'Auteur saisie', width: 150, value: (op) => op.auteur),
    ErpGridColumn(
      label: 'Date saisie',
      width: 110,
      value: (op) => op.saisiLe.split(' ').first,
    ),
    ErpGridColumn(
      label: 'Heure saisie',
      width: 100,
      value: (op) => op.saisiLe.contains(' ') ? op.saisiLe.split(' ').last : '',
    ),
  ];

  String _journalLabel(DossierOperation op) {
    final journal = widget.journals
        .where((j) => j.code == op.codeJournal)
        .firstOrNull;
    return journal == null
        ? op.codeJournal
        : '${journal.code} • ${journal.intitule}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final selected = rows.any((d) => d.id == _selected?.id) ? _selected : null;
    final payments = selected == null
        ? <DossierOperation>[]
        : selected.reglementsDe(_kind).toList();
    final selectedPayment = payments.any((p) => p.id == _selectedPayment?.id)
        ? _selectedPayment
        : null;
    final total = rows.fold<double>(0, (sum, d) => sum + _invoice(d).montant);
    final paid = rows.fold<double>(0, (sum, d) => sum + _paid(d));
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1150;
          final invoiceGrid = _section(
            title: 'Factures transitaire',
            icon: Icons.directions_boat_rounded,
            child: ErpGrid<TransitDossier>(
              key: const ValueKey('transitaire-invoices-grid'),
              columns: _invoiceColumns,
              rows: rows,
              rowId: (d) => d.id,
              selected: selected,
              onSelect: (d) => setState(() {
                _selected = d;
                _selectedPayment = null;
              }),
              onOpen: _edit,
              emptyIcon: Icons.receipt_long_outlined,
              emptyText: _invoiced.isEmpty
                  ? 'Aucune facture transitaire. Cliquez sur « Nouvelle facture ».'
                  : 'Aucune facture ne correspond aux filtres.',
            ),
          );
          final details = _section(
            title: selected == null
                ? 'Détails de la facture'
                : 'Détails de la facture ${_invoice(selected).reference}',
            icon: Icons.local_shipping_rounded,
            child: ErpGrid<InvoiceLine>(
              key: const ValueKey('transitaire-lines-grid'),
              columns: _lineColumns,
              rows: selected == null ? const [] : _invoice(selected).lignes,
              rowId: (l) =>
                  '${l.numeroConteneur}-${l.plaqueVehicule}-${l.hashCode}',
              emptyIcon: Icons.touch_app_outlined,
              emptyText: selected == null
                  ? 'Sélectionnez une facture pour voir ses détails.'
                  : 'Cette facture ne contient aucune ligne.',
            ),
          );
          final paymentsPanel = _section(
            title: 'Règlements',
            icon: Icons.payments_rounded,
            actions: [
              ErpActionButton(
                key: const ValueKey('payment-new'),
                label: 'Nouveau paiement',
                icon: Icons.add_card_rounded,
                primary: true,
                color: const Color(0xFF15803D),
                onPressed: selected == null
                    ? null
                    : () => _addPayment(selected),
              ),
              ErpActionButton(
                key: const ValueKey('payment-delete'),
                label: 'Supprimer',
                icon: Icons.delete_outline_rounded,
                color: const Color(0xFFDC2626),
                onPressed: selected == null || selectedPayment == null
                    ? null
                    : () => _deletePayment(selected, selectedPayment),
              ),
            ],
            child: ErpGrid<DossierOperation>(
              key: const ValueKey('transitaire-payments-grid'),
              columns: _paymentColumns,
              rows: payments,
              rowId: (op) => op.id,
              selected: selectedPayment,
              onSelect: (op) => setState(() => _selectedPayment = op),
              emptyIcon: Icons.account_balance_wallet_outlined,
              emptyText: selected == null
                  ? 'Sélectionnez une facture pour voir ses règlements.'
                  : 'Aucun règlement pour cette facture.',
            ),
          );
          return Padding(
            padding: EdgeInsets.all(wide ? 18 : 10),
            child: wide
                // Les grilles gardent une hauteur confortable ; sur un petit écran la page défile.
                ? ListView(
                    children: [
                      _buildToolbar(selected, total, paid),
                      const SizedBox(height: 12),
                      _buildFilters(rows.length),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: math.max(660, constraints.maxHeight - 360),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 5, child: invoiceGrid),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 6,
                              child: Column(
                                children: [
                                  Expanded(child: details),
                                  const SizedBox(height: 12),
                                  Expanded(child: paymentsPanel),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                    children: [
                      _buildToolbar(selected, total, paid),
                      const SizedBox(height: 12),
                      _buildFilters(rows.length),
                      const SizedBox(height: 12),
                      SizedBox(height: 380, child: invoiceGrid),
                      const SizedBox(height: 12),
                      SizedBox(height: 320, child: details),
                      const SizedBox(height: 12),
                      SizedBox(height: 360, child: paymentsPanel),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _section({
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

  Widget _buildToolbar(TransitDossier? selected, double total, double paid) {
    final hasSelection = selected != null;
    return _card(
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
                  Icons.directions_boat_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Factures Transitaire',
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
                label: 'Total facturé',
                value: _amountText(total),
                color: _gridAccent,
                icon: Icons.receipt_long_rounded,
              ),
              ErpMetricTile(
                label: 'Total payé',
                value: _amountText(paid),
                color: const Color(0xFF15803D),
                icon: Icons.check_circle_outline_rounded,
              ),
              ErpMetricTile(
                label: 'Reliquat',
                value: _amountText(total - paid),
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
                key: const ValueKey('transitaire-invoice-new'),
                label: 'Nouvelle facture',
                icon: Icons.note_add_rounded,
                primary: true,
                onPressed: _create,
              ),
              ErpActionButton(
                key: const ValueKey('transitaire-invoice-edit'),
                label: 'Modifier',
                icon: Icons.edit_rounded,
                onPressed: hasSelection ? () => _edit(selected) : null,
              ),
              ErpActionButton(
                key: const ValueKey('transitaire-invoice-delete'),
                label: 'Supprimer',
                icon: Icons.delete_outline_rounded,
                color: const Color(0xFFDC2626),
                onPressed: hasSelection ? () => _delete(selected) : null,
              ),
              ErpActionButton(
                label: 'Exporter',
                icon: Icons.file_download_outlined,
                onPressed: () => _exportGrid(
                  context,
                  baseName: 'factures_transitaire',
                  columns: _invoiceColumns,
                  rows: _filtered,
                ),
              ),
              ErpActionButton(
                label: 'Imprimer',
                icon: Icons.print_outlined,
                onPressed: hasSelection
                    ? () => _printTransitaireInvoice(
                        selected,
                        PdfPageFormat.a4.landscape,
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

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
            key: const ValueKey('transitaire-filter'),
            options: widget.prestataires
                .where((p) => p.type == 'Transitaire')
                .toList(),
            value: _transitaire,
            label: 'Transitaire',
            emptyText: 'Tous les transitaires',
            required: false,
            displayString: (p) => p.entreprise,
            onChanged: (p) => setState(() => _transitaire = p),
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
          width: 260,
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Rechercher une facture…',
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
            '$count facture(s)',
            style: const TextStyle(
              color: Color(0xFFC2410C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _create() async {
    final candidates = widget.dossiers
        .where(
          (d) =>
              !d.estCloture &&
              _invoice(d).statut == 'Brouillon' &&
              (_transitaire == null ||
                  d.transitaireAffecte?.id == _transitaire!.id),
        )
        .toList();
    if (candidates.isEmpty) {
      await _showInfoAlert(
        context,
        title: 'Aucun dossier à facturer',
        message:
            'Tous les dossiers ouverts ont déjà une facture transitaire, ou aucun dossier n’existe encore.',
      );
      return;
    }
    final dossier = await showDialog<TransitDossier>(
      context: context,
      builder: (context) => _DossierPickerDialog(dossiers: candidates),
    );
    if (dossier == null || !mounted) return;
    await _openEditor(dossier);
  }

  Future<void> _edit(TransitDossier dossier) async {
    if (_paid(dossier) > 0) {
      await _showInfoAlert(
        context,
        title: 'Facture déjà réglée',
        message:
            'Cette facture a déjà des règlements : elle ne peut plus être modifiée. Supprimez d’abord ses règlements si une correction est nécessaire.',
      );
      return;
    }
    if (dossier.estCloture) {
      await _showInfoAlert(
        context,
        title: 'Dossier clôturé',
        message: 'Le dossier de cette facture est clôturé.',
      );
      return;
    }
    await _openEditor(dossier);
  }

  Future<void> _openEditor(TransitDossier dossier) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TransitaireInvoiceDialog(
        dossier: dossier,
        dossiers: widget.dossiers,
        transitaires: widget.prestataires
            .where((p) => p.type == 'Transitaire')
            .toList(),
      ),
    );
    if (saved == true && mounted) setState(() => _selected = dossier);
  }

  Future<void> _delete(TransitDossier dossier) async {
    if (_paid(dossier) > 0 || dossier.estCloture) {
      await _showInfoAlert(
        context,
        title: 'Suppression impossible',
        message: dossier.estCloture
            ? 'Le dossier de cette facture est clôturé.'
            : 'Cette facture a déjà des règlements. Supprimez d’abord les règlements.',
      );
      return;
    }
    final invoice = _invoice(dossier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
        title: const Text('Supprimer cette facture ?'),
        content: Text(
          'La facture ${invoice.reference} (${_amountText(invoice.montant)}) du dossier ${dossier.numDossier} sera supprimée.',
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
    final previous = (
      invoice.reference,
      invoice.lignes,
      invoice.montant,
      invoice.statut,
      invoice.dateEmission,
      invoice.observations,
      invoice.description,
    );
    invoice
      ..reference = 'FT-${dossier.numDossier}'
      ..lignes = []
      ..montant = 0
      ..statut = 'Brouillon'
      ..dateEmission = ''
      ..observations = ''
      ..description = '';
    if (!await _persist(context, () => erpBackend.saveDossier(dossier))) {
      invoice
        ..reference = previous.$1
        ..lignes = previous.$2
        ..montant = previous.$3
        ..statut = previous.$4
        ..dateEmission = previous.$5
        ..observations = previous.$6
        ..description = previous.$7;
    }
    if (mounted) setState(() {});
  }

  Future<void> _addPayment(TransitDossier dossier) async {
    if (dossier.estCloture) {
      await _showInfoAlert(
        context,
        title: 'Dossier clôturé',
        message: 'Aucun règlement ne peut être ajouté à un dossier clôturé.',
      );
      return;
    }
    if (_balance(dossier) <= 0) {
      await _showInfoAlert(
        context,
        title: 'Facture acquittée',
        message: 'Cette facture est déjà entièrement réglée.',
      );
      return;
    }
    if (widget.journals.isEmpty) {
      await _showInfoAlert(
        context,
        title: 'Caisse requise',
        message:
            'Créez d’abord une caisse ou une banque dans Comptabilité > Code journaux.',
      );
      return;
    }
    final payment = await showDialog<DossierOperation>(
      context: context,
      builder: (context) => _PaymentDialog(
        journals: widget.journals,
        balance: _balance(dossier),
        invoiceReference: _invoice(dossier).reference,
      ),
    );
    if (payment == null || !mounted) return;
    dossier.operations.add(payment);
    if (!await _persist(context, () => erpBackend.saveDossier(dossier))) {
      dossier.operations.remove(payment);
    }
    if (mounted) setState(() => _selectedPayment = null);
  }

  Future<void> _deletePayment(
    TransitDossier dossier,
    DossierOperation payment,
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
    final index = dossier.operations.indexOf(payment);
    dossier.operations.removeAt(index);
    if (!await _persist(context, () => erpBackend.saveDossier(dossier))) {
      dossier.operations.insert(index, payment);
    }
    if (mounted) setState(() => _selectedPayment = null);
  }
}

// Choix du dossier à facturer.
class _DossierPickerDialog extends StatefulWidget {
  final List<TransitDossier> dossiers;

  const _DossierPickerDialog({required this.dossiers});

  @override
  State<_DossierPickerDialog> createState() => _DossierPickerDialogState();
}

class _DossierPickerDialogState extends State<_DossierPickerDialog> {
  TransitDossier? _dossier;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouvelle facture transitaire'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choisissez le dossier à facturer. La facture reprendra ses conteneurs.',
            style: TextStyle(color: _gridMuted),
          ),
          const SizedBox(height: 14),
          SearchableDropdownFormField<TransitDossier>(
            key: const ValueKey('transitaire-dossier-picker'),
            options: widget.dossiers,
            value: _dossier,
            label: 'Dossier',
            emptyText: 'Aucun dossier',
            displayString: (d) =>
                '${d.numDossier} • ${d.client.nom}${d.nomTransitaire.isEmpty ? '' : ' • ${d.nomTransitaire}'}',
            onChanged: (d) => setState(() => _dossier = d),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _dossier == null
            ? null
            : () => Navigator.pop(context, _dossier),
        child: const Text('Continuer'),
      ),
    ],
  );
}

class _TransitLineDraft {
  final plate = TextEditingController();
  final driverPhone = TextEditingController();
  final bl = TextEditingController();
  final container = TextEditingController();
  final containerType = TextEditingController();
  final cargo = TextEditingController();
  final transit = TextEditingController();
  final volume = TextEditingController();
  final demurrage = TextEditingController();
  final toll = TextEditingController();
  final other = TextEditingController();

  _TransitLineDraft({InvoiceLine? line, TransitContainer? from, String? bl}) {
    if (line != null) {
      plate.text = line.plaqueVehicule;
      driverPhone.text = line.telephoneChauffeur;
      this.bl.text = line.bl;
      container.text = line.numeroConteneur;
      containerType.text = line.typeConteneur;
      cargo.text = line.marchandise;
      transit.text = _draft(line.fraisTransit);
      volume.text = _draft(line.volumePoids);
      demurrage.text = _draft(line.surestariesMagasinage);
      toll.text = _draft(line.fraisPeage);
      other.text = _draft(line.autresFrais);
      return;
    }
    this.bl.text = bl ?? '';
    if (from != null) {
      container.text = from.numero;
      containerType.text = from.type;
      cargo.text = from.marchandise;
    }
  }

  static String _draft(double value) =>
      value == 0 ? '' : value.toStringAsFixed(0);

  List<TextEditingController> get amounts => [
    transit,
    volume,
    demurrage,
    toll,
    other,
  ];

  double get total =>
      amounts.fold(0, (sum, c) => sum + (_parseAmount(c.text) ?? 0));

  bool get hasInvalidAmount => amounts.any((c) {
    final value = _parseAmount(c.text);
    return value == null || value < 0;
  });

  InvoiceLine toLine() => InvoiceLine(
    description: 'Transit ${container.text.trim()}'.trim(),
    quantite: 1,
    prixUnitaire: total,
    plaqueVehicule: plate.text.trim().toUpperCase(),
    telephoneChauffeur: driverPhone.text.trim(),
    bl: bl.text.trim(),
    numeroConteneur: container.text.trim().toUpperCase(),
    typeConteneur: containerType.text.trim(),
    marchandise: cargo.text.trim(),
    fraisTransit: _parseAmount(transit.text) ?? 0,
    volumePoids: _parseAmount(volume.text) ?? 0,
    surestariesMagasinage: _parseAmount(demurrage.text) ?? 0,
    fraisPeage: _parseAmount(toll.text) ?? 0,
    autresFrais: _parseAmount(other.text) ?? 0,
  );

  void dispose() {
    for (final c in [
      plate,
      driverPhone,
      bl,
      container,
      containerType,
      cargo,
      ...amounts,
    ]) {
      c.dispose();
    }
  }
}

// Saisie ou modification d'une facture transitaire.
class _TransitaireInvoiceDialog extends StatefulWidget {
  final TransitDossier dossier;
  final List<TransitDossier> dossiers;
  final List<Prestataire> transitaires;

  const _TransitaireInvoiceDialog({
    required this.dossier,
    required this.dossiers,
    required this.transitaires,
  });

  @override
  State<_TransitaireInvoiceDialog> createState() =>
      _TransitaireInvoiceDialogState();
}

class _TransitaireInvoiceDialogState extends State<_TransitaireInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _observations = TextEditingController();
  final List<_TransitLineDraft> _lines = [];
  Prestataire? _transitaire;
  DateTime _date = DateTime.now();
  bool _saving = false;

  TransitDossier get _dossier => widget.dossier;
  DossierInvoice get _invoice => _dossier.factureTransitaire;
  bool get _isEdit => _invoice.statut != 'Brouillon';

  @override
  void initState() {
    super.initState();
    _transitaire = _dossier.transitaireAffecte;
    if (_isEdit) {
      _reference.text = _invoice.reference;
      _observations.text = _invoice.observations;
      _date = _parseFrDate(_invoice.dateEmission) ?? DateTime.now();
      _lines.addAll(_invoice.lignes.map((l) => _TransitLineDraft(line: l)));
    } else {
      _reference.text = _nextInvoiceNumber(
        'FAC-TRS',
        widget.dossiers.map((d) => d.factureTransitaire.reference),
        _date,
      );
      _lines.addAll(
        _dossier.conteneurs.map(
          (c) => _TransitLineDraft(from: c, bl: _dossier.numBL),
        ),
      );
    }
    if (_lines.isEmpty) _lines.add(_TransitLineDraft(bl: _dossier.numBL));
  }

  @override
  void dispose() {
    _reference.dispose();
    _observations.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  double get _total => _lines.fold(0, (sum, l) => sum + l.total);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final d = _dossier;
    Widget cell(
      TextEditingController c, {
      String? hint,
      bool amount = false,
      Key? key,
    }) => TextFormField(
      key: key,
      controller: c,
      textAlign: amount ? TextAlign.right : TextAlign.start,
      keyboardType: amount
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: _cellDecoration(hint: hint),
      onChanged: amount ? (_) => setState(() {}) : null,
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: math.min(screen.width - 28, 1150),
        height: math.min(screen.height - 28, 880),
        child: Column(
          children: [
            _dialogHeader(
              icon: Icons.directions_boat_rounded,
              title: _isEdit
                  ? 'Modifier la facture transitaire'
                  : 'Nouvelle facture transitaire',
              subtitle: '${d.numDossier} • ${d.client.nom}',
              onClose: () => Navigator.pop(context),
            ),
            Expanded(
              child: Container(
                color: const Color(0xFFF4F6FB),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _dialogSection(
                        icon: Icons.folder_open_rounded,
                        title: 'Dossier',
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _infoTile('Dossier', d.numDossier),
                            _infoTile('Client', d.client.nom),
                            _infoTile('BL', d.numBL),
                            _infoTile('Marchandise', d.typeMarchandise),
                            _infoTile(
                              'Conteneurs 20 / 40 pieds',
                              '${d.nbConteneurs20} / ${d.nbConteneurs40}',
                            ),
                          ],
                        ),
                      ),
                      _dialogSection(
                        icon: Icons.receipt_long_rounded,
                        title: 'Facture',
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            SizedBox(
                              width: 280,
                              child: SearchableDropdownFormField<Prestataire>(
                                key: const ValueKey(
                                  'transitaire-invoice-partner',
                                ),
                                options: widget.transitaires,
                                value: _transitaire,
                                label: 'Transitaire *',
                                emptyText:
                                    'Ajoutez un transitaire dans Espace Prestataire',
                                displayString: (p) => p.entreprise,
                                onChanged: (p) =>
                                    setState(() => _transitaire = p),
                              ),
                            ),
                            SizedBox(
                              width: 260,
                              child: TextFormField(
                                key: const ValueKey(
                                  'transitaire-invoice-number',
                                ),
                                controller: _reference,
                                decoration: _inputDecoration(
                                  'Numéro de facture *',
                                  icon: Icons.tag_rounded,
                                ),
                                validator: _validateReference,
                              ),
                            ),
                            SizedBox(
                              width: 210,
                              child: _FormDateField(
                                label: 'Date de facture',
                                value: _date,
                                clearable: false,
                                onChanged: (date) =>
                                    setState(() => _date = date ?? _date),
                              ),
                            ),
                            SizedBox(
                              width: 500,
                              child: TextFormField(
                                controller: _observations,
                                maxLines: 2,
                                decoration: _inputDecoration(
                                  'Observations',
                                  icon: Icons.notes_rounded,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _dialogSection(
                        icon: Icons.local_shipping_rounded,
                        title: 'Véhicules, conteneurs et frais',
                        trailing: FilledButton.tonalIcon(
                          key: const ValueKey('transitaire-line-add'),
                          onPressed: () => setState(
                            () => _lines.add(_TransitLineDraft(bl: d.numBL)),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Ajouter une ligne'),
                        ),
                        child: _EditableTable(
                          columns: const [
                            ('Véhicule', 130),
                            ('Tél. chauffeur', 140),
                            ('BL', 140),
                            ('Numéro conteneur', 160),
                            ('Type conteneur', 120),
                            ('Marchandise', 160),
                            ('Frais de transit', 130),
                            ('Volume et poids', 130),
                            ('Surestaries / magasinage', 170),
                            ('Frais de péage', 120),
                            ('Autres frais', 120),
                            ('Montant total', 140),
                            ('', 52),
                          ],
                          rows: [
                            for (final (i, line) in _lines.indexed)
                              [
                                cell(
                                  line.plate,
                                  hint: 'AB 1234 MD',
                                  key: ValueKey('transitaire-line-$i-plate'),
                                ),
                                cell(line.driverPhone, hint: '+223 …'),
                                cell(line.bl),
                                cell(line.container),
                                cell(line.containerType),
                                cell(line.cargo),
                                cell(
                                  line.transit,
                                  hint: '0',
                                  amount: true,
                                  key: ValueKey('transitaire-line-$i-transit'),
                                ),
                                cell(line.volume, hint: '0', amount: true),
                                cell(line.demurrage, hint: '0', amount: true),
                                cell(
                                  line.toll,
                                  hint: '0',
                                  amount: true,
                                  key: ValueKey('transitaire-line-$i-toll'),
                                ),
                                cell(line.other, hint: '0', amount: true),
                                Text(
                                  _amountText(line.total),
                                  key: ValueKey('transitaire-line-total-$i'),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _gridPrimary,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Retirer la ligne',
                                  onPressed: _lines.length == 1
                                      ? null
                                      : () => setState(
                                          () => _lines.removeAt(i).dispose(),
                                        ),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
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
            ),
            _dialogFooter(
              onCancel: () => Navigator.pop(context),
              onValidate: _saving ? null : _validate,
              validateLabel: 'Valider la facture',
              validateKey: const ValueKey('transitaire-invoice-validate'),
              leading: Row(
                children: [
                  const Text(
                    'Total facture : ',
                    style: TextStyle(color: _gridMuted, fontSize: 15),
                  ),
                  Flexible(
                    child: Text(
                      '${formatCurrency(_total)} FCFA',
                      key: const ValueKey('transitaire-invoice-total'),
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
    );
  }

  String? _validateReference(String? value) {
    final reference = value?.trim() ?? '';
    if (reference.isEmpty) return 'Champ obligatoire';
    final duplicate = widget.dossiers.any(
      (d) =>
          d.id != _dossier.id &&
          _normalizeUniqueValue(d.factureTransitaire.reference) ==
              _normalizeUniqueValue(reference),
    );
    return duplicate ? 'Ce numéro de facture existe déjà' : null;
  }

  Future<void> _validate() async {
    if (!_formKey.currentState!.validate()) return;
    final transitaire = _transitaire;
    if (transitaire == null) return;
    if (_lines.any((l) => l.hasInvalidAmount)) {
      await _showInfoAlert(
        context,
        title: 'Montant invalide',
        message:
            'Vérifiez les frais saisis : seuls des nombres positifs sont acceptés.',
      );
      return;
    }
    if (_total <= 0) {
      await _showInfoAlert(
        context,
        title: 'Montant requis',
        message: 'Saisissez au moins un frais pour cette facture.',
      );
      return;
    }
    final invoice = _invoice;
    final previous = (
      invoice.reference,
      invoice.lignes,
      invoice.montant,
      invoice.statut,
      invoice.dateEmission,
      invoice.observations,
      invoice.description,
      _dossier.transitaireAffecte,
      _dossier.prestataire,
      _dossier.transitaire,
    );
    invoice
      ..reference = _reference.text.trim()
      ..lignes = _lines.map((l) => l.toLine()).toList()
      ..montant = _total
      ..statut = 'Clôturée'
      ..dateEmission = DateFormat('dd/MM/yyyy').format(_date)
      ..observations = _observations.text.trim()
      ..description = 'Transit du dossier ${_dossier.numDossier}';
    _dossier.transitaireAffecte = transitaire;
    _dossier.prestataire ??= transitaire;
    setState(() => _saving = true);
    final saved = await _persist(
      context,
      () => erpBackend.saveDossier(_dossier),
    );
    if (!saved) {
      invoice
        ..reference = previous.$1
        ..lignes = previous.$2
        ..montant = previous.$3
        ..statut = previous.$4
        ..dateEmission = previous.$5
        ..observations = previous.$6
        ..description = previous.$7;
      _dossier
        ..transitaireAffecte = previous.$8
        ..prestataire = previous.$9;
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }
}

// Nouveau règlement d'une facture.
class _PaymentDialog extends StatefulWidget {
  final List<JournalCode> journals;
  final double balance;
  final String invoiceReference;

  const _PaymentDialog({
    required this.journals,
    required this.balance,
    required this.invoiceReference,
  });

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.balance.toStringAsFixed(0),
  );
  final _cheque = TextEditingController();
  final _observations = TextEditingController();
  DateTime _date = DateTime.now();
  JournalCode? _journal;
  String _mode = _paymentModes.first;

  @override
  void initState() {
    super.initState();
    if (widget.journals.length == 1) _journal = widget.journals.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    _cheque.dispose();
    _observations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouveau paiement'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Facture ${widget.invoiceReference} • reliquat ${_amountText(widget.balance)}',
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _FormDateField(
                label: 'Date du règlement',
                value: _date,
                clearable: false,
                onChanged: (date) => setState(() => _date = date ?? _date),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('payment-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _inputDecoration(
                  'Montant *',
                  icon: Icons.payments_outlined,
                ).copyWith(suffixText: 'FCFA'),
                validator: (value) {
                  final amount = _parseAmount(value ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Saisissez un montant supérieur à zéro';
                  }
                  if (amount > widget.balance + 0.001) {
                    return 'Le montant dépasse le reliquat (${_amountText(widget.balance)})';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<JournalCode>(
                key: const ValueKey('payment-journal'),
                isExpanded: true,
                initialValue: _journal,
                decoration: _inputDecoration(
                  'Caisse *',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                items: [
                  for (final journal in widget.journals)
                    DropdownMenuItem(
                      value: journal,
                      child: Text('${journal.code} • ${journal.intitule}'),
                    ),
                ],
                validator: (value) =>
                    value == null ? 'Choisissez la caisse' : null,
                onChanged: (value) => setState(() => _journal = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _mode,
                decoration: _inputDecoration(
                  'Mode de paiement',
                  icon: Icons.credit_card_rounded,
                ),
                items: [
                  for (final mode in _paymentModes)
                    DropdownMenuItem(value: mode, child: Text(mode)),
                ],
                onChanged: (value) => setState(() => _mode = value ?? _mode),
              ),
              if (_mode == 'Chèque') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cheque,
                  decoration: _inputDecoration(
                    'Numéro de chèque *',
                    icon: Icons.confirmation_number_outlined,
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Saisissez le numéro du chèque'
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _observations,
                maxLines: 2,
                decoration: _inputDecoration(
                  'Observations',
                  icon: Icons.notes_rounded,
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
        key: const ValueKey('payment-save'),
        onPressed: _save,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Enregistrer'),
      ),
    ],
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    final date = DateTime(
      _date.year,
      _date.month,
      _date.day,
      now.hour,
      now.minute,
    );
    Navigator.pop(
      context,
      DossierOperation(
        type: DossierOperationType.providerPayment,
        titre: 'Règlement ${widget.invoiceReference}',
        categorie: _transitairePaymentCategory,
        montant: _parseAmount(_amount.text)!,
        date: DateFormat('dd/MM/yyyy HH:mm').format(date),
        codeJournal: _journal!.code,
        modePaiement: _mode,
        numeroCheque: _mode == 'Chèque' ? _cheque.text.trim() : '',
        observations: _observations.text.trim(),
        auteur: _currentUser?.name ?? '',
        saisiLe: DateFormat('dd/MM/yyyy HH:mm').format(now),
      ),
    );
  }
}
