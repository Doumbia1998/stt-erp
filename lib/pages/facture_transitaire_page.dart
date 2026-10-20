part of '../main.dart';

// --- FACTURES TRANSITAIRE : plusieurs BL / dossiers par facture, camions, règlements ---

enum _PaidFilter { all, paid, unpaid }

const _transitairePaymentCategory = 'Règlement Transitaire';
const _paymentModes = [
  'Espèces',
  'Chèque',
  'Virement bancaire',
  'Mobile Money',
];

// Conteneur d'un dossier encore à facturer (conteneur vide : BL dont les conteneurs ne sont pas saisis).
class _AvailableContainer {
  final TransitDossier dossier;
  final TransitContainer container;

  const _AvailableContainer(this.dossier, this.container);

  String get cle => '${dossier.id}|${container.numero.toUpperCase()}';
}

// Tous les BL des dossiers ouverts qui ne sont pas encore facturés, quel que soit le transitaire.
List<_AvailableContainer> _availableContainers(
  List<TransitDossier> dossiers,
  List<FactureTransitaire> factures, {
  String? exceptFactureId,
}) {
  final taken = {
    for (final f in factures)
      if (f.id != exceptFactureId)
        for (final l in f.lignes) l.cleConteneur,
  };
  final result = <_AvailableContainer>[];
  for (final d in dossiers) {
    if (d.estCloture) continue;
    final numbered = d.conteneurs.where((c) => c.numero.trim().isNotEmpty);
    if (numbered.isEmpty) {
      if (d.numBL.trim().isNotEmpty && !taken.contains('${d.id}|')) {
        result.add(
          _AvailableContainer(
            d,
            TransitContainer(
              numero: '',
              type: '',
              marchandise: d.typeMarchandise,
            ),
          ),
        );
      }
      continue;
    }
    for (final c in numbered) {
      if (!taken.contains('${d.id}|${c.numero.toUpperCase()}')) {
        result.add(_AvailableContainer(d, c));
      }
    }
  }
  return result;
}

// Raison empêchant de clôturer un dossier côté transitaire (null si rien ne bloque).
String? _transitaireClosureIssue(TransitDossier d) {
  if (d.transitaireAffecte == null) return null;
  final invoices = _facturesTransitaire
      .where((f) => f.lignes.any((l) => l.dossierId == d.id))
      .toList();
  final invoiced = {
    for (final f in invoices)
      for (final l in f.lignes)
        if (l.dossierId == d.id) l.numeroConteneur.toUpperCase(),
  };
  final missing = d.conteneurs
      .where(
        (c) =>
            c.numero.isNotEmpty && !invoiced.contains(c.numero.toUpperCase()),
      )
      .length;
  if (missing > 0) {
    return '$missing conteneur(s) pas encore facturé(s) par le transitaire';
  }
  final unpaid = invoices.where((f) => !f.estAcquittee).toList();
  if (unpaid.isNotEmpty) {
    return 'facture(s) transitaire non soldée(s) : ${unpaid.map((f) => f.reference).join(', ')}';
  }
  return null;
}

class FactureTransitairePage extends StatefulWidget {
  final List<TransitDossier> dossiers;
  final List<Prestataire> prestataires;
  final List<JournalCode> journals;
  final List<ModeReglement> modes;
  final List<FactureTransitaire> factures;

  const FactureTransitairePage({
    super.key,
    required this.dossiers,
    required this.prestataires,
    required this.journals,
    required this.factures,
    this.modes = const [],
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
  FactureTransitaire? _selected;
  ReglementFacture? _selectedPayment;

  Prestataire? _partner(String id) =>
      widget.prestataires.where((p) => p.id == id).firstOrNull;
  String _partnerName(String id) => _partner(id)?.entreprise ?? '';
  String _dossierNumber(String id) =>
      widget.dossiers.where((d) => d.id == id).firstOrNull?.numDossier ?? '';

  List<FactureTransitaire> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.factures.where((f) {
      if (!_inPeriod(_parseFrDate(f.dateEmission), _from, _to)) return false;
      if (_transitaire != null && f.transitaireId != _transitaire!.id) {
        return false;
      }
      if (_paidFilter == _PaidFilter.paid && !f.estAcquittee) return false;
      if (_paidFilter == _PaidFilter.unpaid && f.estAcquittee) return false;
      if (query.isEmpty) return true;
      return [
        ..._invoiceColumns.map((c) => c.value(f)),
        ...f.lignes.map((l) => '${l.bl} ${l.numeroConteneur} ${l.plaque}'),
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  int get _pendingContainers =>
      _availableContainers(widget.dossiers, widget.factures).length;

  late final List<ErpGridColumn<FactureTransitaire>> _invoiceColumns = [
    ErpGridColumn(
      label: 'ID',
      width: 70,
      numeric: true,
      value: (f) => f.numero == 0 ? '' : '${f.numero}',
      sortValue: (f) => f.numero,
    ),
    ErpGridColumn(
      label: 'Numéro de facture',
      width: 170,
      value: (f) => f.reference,
    ),
    ErpGridColumn(
      label: 'Statut',
      width: 140,
      value: (f) => f.estAcquittee ? 'Acquittée' : 'Non acquittée',
      builder: (f) => f.estAcquittee
          ? const ErpStatusChip('Acquittée', Color(0xFF15803D))
          : const ErpStatusChip('Non acquittée', Color(0xFFEA580C)),
    ),
    ErpGridColumn(
      label: 'Date de facture',
      width: 120,
      value: (f) => f.dateEmission,
      sortValue: (f) => _parseFrDate(f.dateEmission) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Total TTC',
      width: 135,
      numeric: true,
      value: (f) => _amountText(f.montant),
      sortValue: (f) => f.montant,
    ),
    ErpGridColumn(
      label: 'Total payé',
      width: 135,
      numeric: true,
      value: (f) => _amountText(f.totalRegle),
      sortValue: (f) => f.totalRegle,
    ),
    ErpGridColumn(
      label: 'Reliquat',
      width: 135,
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
    ErpGridColumn(
      label: 'Transitaire',
      width: 170,
      value: (f) => _partnerName(f.transitaireId),
    ),
    ErpGridColumn(
      label: 'Conteneurs',
      width: 100,
      numeric: true,
      value: (f) => '${f.lignes.length}',
      sortValue: (f) => f.lignes.length,
    ),
    ErpGridColumn(
      label: 'BL',
      width: 200,
      value: (f) => {for (final l in f.lignes) l.bl}.join(', '),
    ),
    ErpGridColumn(
      label: 'Observations',
      width: 220,
      value: (f) => f.observations,
    ),
  ];

  late final List<ErpGridColumn<FactureTransitaireLigne>> _lineColumns = [
    ErpGridColumn(label: 'BL', width: 130, value: (l) => l.bl),
    ErpGridColumn(
      label: 'Dossier',
      width: 160,
      value: (l) => _dossierNumber(l.dossierId),
    ),
    ErpGridColumn(
      label: 'Marchandise',
      width: 150,
      value: (l) => l.marchandise,
    ),
    ErpGridColumn(
      label: 'Date de départ',
      width: 115,
      value: (l) => l.dateDepart,
    ),
    ErpGridColumn(
      label: 'Numéro conteneur',
      width: 150,
      value: (l) => l.numeroConteneur,
    ),
    ErpGridColumn(
      label: 'Type conteneur',
      width: 120,
      value: (l) => l.typeConteneur,
    ),
    ErpGridColumn(
      label: 'Transporteur',
      width: 150,
      value: (l) => _partnerName(l.transporteurId),
    ),
    ErpGridColumn(label: 'Véhicule', width: 120, value: (l) => l.plaque),
    ErpGridColumn(
      label: 'Tél. chauffeur',
      width: 130,
      value: (l) => l.telephoneChauffeur,
    ),
    for (final (label, pick)
        in <(String, double Function(FactureTransitaireLigne))>[
          ('Frais de transit', (l) => l.fraisTransit),
          ('Surestaries et magasinage', (l) => l.surestariesMagasinage),
          ('Volume et poids', (l) => l.volumePoids),
          ('Autres frais', (l) => l.autresFrais),
          ('Frais de péage', (l) => l.fraisPeage),
          ('Montant', (l) => l.montant),
          ('Transport dû', (l) => l.montantTransport),
          ('Avance camion', (l) => l.avanceCamion),
        ])
      ErpGridColumn(
        label: label,
        width: label.length > 14 ? 170 : 130,
        numeric: true,
        value: (l) => _amountText(pick(l)),
        sortValue: (l) => pick(l),
      ),
  ];

  late final List<ErpGridColumn<ReglementFacture>> _paymentColumns = [
    ErpGridColumn(
      label: 'Date règlement',
      width: 125,
      value: (r) => r.date.split(' ').first,
      sortValue: (r) => _parseFrDate(r.date) ?? DateTime(0),
    ),
    ErpGridColumn(
      label: 'Montant',
      width: 135,
      numeric: true,
      value: (r) => _amountText(r.montant),
      sortValue: (r) => r.montant,
    ),
    ErpGridColumn(
      label: 'Caisse',
      width: 160,
      value: (r) => _journalLabel(r.codeJournal),
    ),
    ErpGridColumn(
      label: 'Mode de paiement',
      width: 150,
      value: (r) => r.modePaiement,
    ),
    ErpGridColumn(
      label: 'Numéro de chèque',
      width: 140,
      value: (r) => r.numeroCheque,
    ),
    ErpGridColumn(
      label: 'Observations',
      width: 230,
      value: (r) => r.observations,
    ),
    ErpGridColumn(label: 'Auteur saisie', width: 150, value: (r) => r.auteur),
    ErpGridColumn(
      label: 'Date saisie',
      width: 110,
      value: (r) => r.saisiLe.split(' ').first,
    ),
    ErpGridColumn(
      label: 'Heure saisie',
      width: 100,
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
    final paid = rows.fold<double>(0, (s, f) => s + f.totalRegle);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1150;
          final invoiceGrid = _section(
            title: 'Factures transitaire',
            icon: Icons.directions_boat_rounded,
            child: ErpGrid<FactureTransitaire>(
              key: const ValueKey('transitaire-invoices-grid'),
              columns: _invoiceColumns,
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
                  ? 'Aucune facture transitaire. Cliquez sur « Nouvelle facture ».'
                  : 'Aucune facture ne correspond aux filtres.',
            ),
          );
          final details = _section(
            title: selected == null
                ? 'Détails de la facture'
                : 'Détails de la facture ${selected.reference}',
            icon: Icons.local_shipping_rounded,
            child: ErpGrid<FactureTransitaireLigne>(
              key: const ValueKey('transitaire-lines-grid'),
              columns: _lineColumns,
              rows: selected?.lignes ?? const [],
              rowId: (l) => l.cleConteneur,
              emptyIcon: Icons.touch_app_outlined,
              emptyText: 'Sélectionnez une facture pour voir ses conteneurs.',
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
            child: ErpGrid<ReglementFacture>(
              key: const ValueKey('transitaire-payments-grid'),
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
          final header = [
            _buildToolbar(selected, total, paid),
            const SizedBox(height: 12),
            _buildFilters(rows.length),
            const SizedBox(height: 12),
          ];
          return Padding(
            padding: EdgeInsets.all(wide ? 18 : 10),
            child: wide
                ? ListView(
                    children: [
                      ...header,
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
                      ...header,
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

  Widget _buildToolbar(
    FactureTransitaire? selected,
    double total,
    double paid,
  ) {
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
                onPressed: () => _openEditor(null),
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
                    ? () => _printFactureTransitaire(
                        selected,
                        transitaire: _partnerName(selected.transitaireId),
                        dossierNumber: _dossierNumber,
                        partnerName: _partnerName,
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
              hintText: 'Facture, BL, conteneur, plaque…',
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
            '$count facture(s) • $_pendingContainers conteneur(s) à facturer',
            key: const ValueKey('transitaire-count'),
            style: const TextStyle(
              color: Color(0xFFC2410C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _edit(FactureTransitaire facture) async {
    if (facture.reglements.isNotEmpty) {
      await _showInfoAlert(
        context,
        title: 'Facture déjà réglée',
        message:
            'Cette facture a déjà des règlements : elle ne peut plus être modifiée. Supprimez d’abord ses règlements si une correction est nécessaire.',
      );
      return;
    }
    await _openEditor(facture);
  }

  Future<void> _openEditor(FactureTransitaire? facture) async {
    final saved = await showDialog<FactureTransitaire>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FactureTransitaireEditor(
        initial: facture,
        dossiers: widget.dossiers,
        prestataires: widget.prestataires,
        factures: widget.factures,
        transitaire: facture == null ? _transitaire : null,
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

  Future<void> _delete(FactureTransitaire facture) async {
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
          'La facture ${facture.reference} (${_amountText(facture.montant)}) sera supprimée. Ses ${facture.lignes.length} conteneur(s) redeviendront disponibles.',
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
      () => erpBackend.deleteFactureTransitaire(facture),
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      widget.factures.removeWhere((f) => f.id == facture.id);
      _selected = null;
    });
  }

  Future<void> _addPayment(FactureTransitaire facture) async {
    if (facture.reliquat <= 0) {
      await _showInfoAlert(
        context,
        title: 'Facture acquittée',
        message: 'Cette facture est déjà entièrement réglée.',
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
      () => erpBackend.saveFactureTransitaire(facture),
    )) {
      facture.reglements.remove(payment);
    }
    if (mounted) setState(() => _selectedPayment = null);
  }

  Future<void> _deletePayment(
    FactureTransitaire facture,
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
      () => erpBackend.saveFactureTransitaire(facture),
    )) {
      facture.reglements.insert(index, payment);
    }
    if (mounted) setState(() => _selectedPayment = null);
  }
}

class _TransitLineDraft {
  final String dossierId;
  final String bl;
  final String numeroConteneur;
  final String marchandise;
  final String typeConteneur;
  String transporteurId;
  final dateDepart = TextEditingController();
  final plaque = TextEditingController();
  final telephone = TextEditingController();
  final transit = TextEditingController();
  final demurrage = TextEditingController();
  final volume = TextEditingController();
  final other = TextEditingController();
  final toll = TextEditingController();
  final transport = TextEditingController();
  final advance = TextEditingController();

  _TransitLineDraft(FactureTransitaireLigne l)
    : dossierId = l.dossierId,
      bl = l.bl,
      numeroConteneur = l.numeroConteneur,
      marchandise = l.marchandise,
      typeConteneur = l.typeConteneur,
      transporteurId = l.transporteurId {
    dateDepart.text = l.dateDepart;
    plaque.text = l.plaque;
    telephone.text = l.telephoneChauffeur;
    transit.text = _draft(l.fraisTransit);
    demurrage.text = _draft(l.surestariesMagasinage);
    volume.text = _draft(l.volumePoids);
    other.text = _draft(l.autresFrais);
    toll.text = _draft(l.fraisPeage);
    transport.text = _draft(l.montantTransport);
    advance.text = _draft(l.avanceCamion);
  }

  static String _draft(double value) =>
      value == 0 ? '' : value.toStringAsFixed(0);

  String get cle => '$dossierId|${numeroConteneur.toUpperCase()}';

  List<TextEditingController> get fees => [
    transit,
    demurrage,
    volume,
    other,
    toll,
  ];
  List<TextEditingController> get amounts => [...fees, transport, advance];

  double get montant => fees.fold(0, (s, c) => s + (_parseAmount(c.text) ?? 0));
  double get montantTransport => _parseAmount(transport.text) ?? 0;
  double get avanceCamion => _parseAmount(advance.text) ?? 0;

  bool get hasInvalidAmount => amounts.any((c) {
    final value = _parseAmount(c.text);
    return value == null || value < 0;
  });

  FactureTransitaireLigne toLine() => FactureTransitaireLigne(
    dossierId: dossierId,
    bl: bl,
    numeroConteneur: numeroConteneur,
    marchandise: marchandise,
    typeConteneur: typeConteneur,
    dateDepart: dateDepart.text.trim(),
    transporteurId: transporteurId,
    plaque: plaque.text.trim().toUpperCase(),
    telephoneChauffeur: telephone.text.trim(),
    fraisTransit: _parseAmount(transit.text) ?? 0,
    surestariesMagasinage: _parseAmount(demurrage.text) ?? 0,
    volumePoids: _parseAmount(volume.text) ?? 0,
    autresFrais: _parseAmount(other.text) ?? 0,
    fraisPeage: _parseAmount(toll.text) ?? 0,
    montantTransport: montantTransport,
    avanceCamion: avanceCamion,
  );

  void dispose() {
    for (final c in [dateDepart, plaque, telephone, ...amounts]) {
      c.dispose();
    }
  }
}

// Saisie d'une facture transitaire : camion en en-tête, BL disponibles, détail.
class _FactureTransitaireEditor extends StatefulWidget {
  final FactureTransitaire? initial;
  final List<TransitDossier> dossiers;
  final List<Prestataire> prestataires;
  final List<FactureTransitaire> factures;
  final Prestataire? transitaire;

  const _FactureTransitaireEditor({
    required this.initial,
    required this.dossiers,
    required this.prestataires,
    required this.factures,
    this.transitaire,
  });

  @override
  State<_FactureTransitaireEditor> createState() =>
      _FactureTransitaireEditorState();
}

class _FactureTransitaireEditorState extends State<_FactureTransitaireEditor>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _observations = TextEditingController();
  final _plateText = TextEditingController();
  final _driverPhone = TextEditingController();
  final _search = TextEditingController();
  final _globalToll = TextEditingController();
  final _truckTotal = TextEditingController();
  final _truckAdvance = TextEditingController();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final List<_TransitLineDraft> _lines = [];
  Prestataire? _transitaire;
  Prestataire? _transporteur;
  Vehicule? _vehicule;
  DateTime _date = DateTime.now();
  bool _saving = false;

  List<Prestataire> get _transitaires =>
      widget.prestataires.where((p) => p.type == 'Transitaire').toList();
  List<Prestataire> get _transporteurs =>
      widget.prestataires.where((p) => p.type == 'Transporteur').toList();
  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    if (f == null) {
      _transitaire = widget.transitaire;
      _reference.text = _nextInvoiceNumber(
        'FAC-TRS',
        widget.factures.map((x) => x.reference),
        _date,
      );
      return;
    }
    _transitaire = widget.prestataires
        .where((p) => p.id == f.transitaireId)
        .firstOrNull;
    _reference.text = f.reference;
    _observations.text = f.observations;
    _date = _parseFrDate(f.dateEmission) ?? DateTime.now();
    _lines.addAll(f.lignes.map(_TransitLineDraft.new));
    // Lignes sans transporteur : on le retrouve grâce à la plaque du camion.
    for (final line in _lines.where((l) => l.transporteurId.isEmpty)) {
      final plate = _normalizePlate(line.plaque.text);
      if (plate.isEmpty) continue;
      final owner = _transporteurs
          .where(
            (p) => p.vehicules.any((v) => _normalizePlate(v.plaque) == plate),
          )
          .firstOrNull;
      if (owner != null) line.transporteurId = owner.id;
    }
    final tolls = _lines.fold<double>(
      0,
      (s, l) => s + (_parseAmount(l.toll.text) ?? 0),
    );
    if (tolls > 0) _globalToll.text = tolls.toStringAsFixed(0);
    _syncTruckAmounts();
    // Le dernier camion utilisé est repris comme camion courant.
    final last = f.lignes.lastOrNull;
    if (last != null) {
      _transporteur = widget.prestataires
          .where((p) => p.id == last.transporteurId)
          .firstOrNull;
      _vehicule = _transporteur?.vehicules
          .where(
            (v) => _normalizePlate(v.plaque) == _normalizePlate(last.plaque),
          )
          .firstOrNull;
      _plateText.text = last.plaque;
      _driverPhone.text = last.telephoneChauffeur;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _globalToll,
      _truckTotal,
      _truckAdvance,
      _reference,
      _observations,
      _plateText,
      _driverPhone,
      _search,
    ]) {
      c.dispose();
    }
    _tabs.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String get _currentPlate => (_vehicule?.plaque ?? _plateText.text).trim();

  List<_AvailableContainer> get _available {
    final inInvoice = _lines.map((l) => l.cle).toSet();
    final query = _search.text.trim().toLowerCase();
    final rows =
        _availableContainers(
          widget.dossiers,
          widget.factures,
          exceptFactureId: widget.initial?.id,
        ).where((a) {
          if (inInvoice.contains(a.cle)) return false;
          if (query.isEmpty) return true;
          return '${a.dossier.numBL} ${a.container.numero} ${a.dossier.numDossier} ${a.dossier.client.nom} ${a.container.marchandise} ${a.dossier.transitaireAffecte?.entreprise ?? ''}'
              .toLowerCase()
              .contains(query);
        }).toList();
    // Les BL du transitaire choisi passent en premier.
    final id = _transitaire?.id;
    if (id != null) {
      rows.sort((a, b) {
        final ma = a.dossier.transitaireAffecte?.id == id ? 0 : 1;
        final mb = b.dossier.transitaireAffecte?.id == id ? 0 : 1;
        return ma - mb;
      });
    }
    return rows;
  }

  double get _total => _lines.fold(0, (s, l) => s + l.montant);

  static final _availableColumns = <ErpGridColumn<_AvailableContainer>>[
    ErpGridColumn(
      label: 'BL disponible',
      width: 150,
      value: (a) => a.dossier.numBL,
    ),
    ErpGridColumn(
      label: 'Numéro conteneur',
      width: 170,
      value: (a) =>
          a.container.numero.isEmpty ? '(non saisi)' : a.container.numero,
    ),
    ErpGridColumn(label: 'Type', width: 110, value: (a) => a.container.type),
    ErpGridColumn(
      label: 'Marchandise',
      width: 160,
      value: (a) => a.container.marchandise.isEmpty
          ? a.dossier.typeMarchandise
          : a.container.marchandise,
    ),
    ErpGridColumn(
      label: 'Dossier',
      width: 170,
      value: (a) => a.dossier.numDossier,
    ),
    ErpGridColumn(
      label: 'Client',
      width: 190,
      value: (a) => a.dossier.client.nom,
    ),
    ErpGridColumn(
      label: 'Transitaire du dossier',
      width: 190,
      value: (a) => a.dossier.transitaireAffecte?.entreprise ?? '',
    ),
  ];

  // Répartit un montant global à parts égales sur les conteneurs (le reste sur le dernier).
  void _spread(
    TextEditingController global,
    TextEditingController Function(_TransitLineDraft) field,
  ) {
    if (_lines.isEmpty) return;
    final whole = (_parseAmount(global.text) ?? 0).round();
    final share = whole ~/ _lines.length;
    for (final (i, line) in _lines.indexed) {
      final value = i == _lines.length - 1
          ? whole - share * (_lines.length - 1)
          : share;
      field(line).text = value == 0 ? '' : '$value';
    }
  }

  void _spreadToll() => _spread(_globalToll, (l) => l.toll);

  void _spreadAll() {
    _spreadToll();
    _spread(_truckTotal, (l) => l.transport);
    _spread(_truckAdvance, (l) => l.advance);
  }

  // Le total en en-tête reflète la somme des lignes après une saisie ligne par ligne.
  void _syncTotal(
    TextEditingController global,
    TextEditingController Function(_TransitLineDraft) field,
  ) {
    final total = _lines.fold<double>(
      0,
      (s, l) => s + (_parseAmount(field(l).text) ?? 0),
    );
    global.text = total == 0 ? '' : total.toStringAsFixed(0);
  }

  void _syncGlobalToll() => _syncTotal(_globalToll, (l) => l.toll);

  void _syncTruckAmounts() {
    _syncTotal(_truckTotal, (l) => l.transport);
    _syncTotal(_truckAdvance, (l) => l.advance);
  }

  // Le camion saisi en en-tête s'applique à tous les conteneurs de la facture.
  void _applyTruck() {
    final plate = _currentPlate.toUpperCase();
    final phone = _driverPhone.text.trim();
    for (final line in _lines) {
      line.transporteurId = _transporteur?.id ?? '';
      line.plaque.text = plate;
      line.telephone.text = phone;
    }
  }

  List<(Prestataire, Vehicule)> get _trucks => [
    for (final p in _transporteurs)
      if (_transporteur == null || p.id == _transporteur!.id)
        for (final v in p.vehicules) (p, v),
    if (_transporteur != null)
      for (final p in _transporteurs)
        if (p.id != _transporteur!.id)
          for (final v in p.vehicules) (p, v),
  ];

  void _add(Iterable<_AvailableContainer> containers) {
    final phone = _driverPhone.text.trim();
    setState(() {
      for (final a in containers) {
        _lines.add(
          _TransitLineDraft(
            FactureTransitaireLigne(
              dossierId: a.dossier.id,
              bl: a.dossier.numBL,
              numeroConteneur: a.container.numero.toUpperCase(),
              marchandise: a.container.marchandise.isEmpty
                  ? a.dossier.typeMarchandise
                  : a.container.marchandise,
              typeConteneur: a.container.type,
              dateDepart: DateFormat('dd/MM/yyyy').format(DateTime.now()),
              transporteurId: _transporteur?.id ?? '',
              plaque: _currentPlate.toUpperCase(),
              telephoneChauffeur: phone,
            ),
          ),
        );
      }
      _spreadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final available = _available;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: math.min(screen.width - 24, 1400),
        height: math.min(screen.height - 24, 940),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _dialogHeader(
                icon: Icons.directions_boat_rounded,
                title: _isEdit
                    ? 'Modifier la facture transitaire'
                    : 'Nouvelle facture transitaire',
                subtitle:
                    _transitaire?.entreprise ??
                    'Choisissez le transitaire puis ajoutez ses BL disponibles',
                onClose: () => Navigator.pop(context),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: screen.height * 0.42),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: _buildHeaderFields(),
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
                      key: const ValueKey('tab-available'),
                      text: '1. Liste des BL disponibles (${available.length})',
                    ),
                    Tab(
                      key: const ValueKey('tab-details'),
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
                      _buildAvailableTab(available),
                      _buildDetailsTab(),
                    ],
                  ),
                ),
              ),
              _dialogFooter(
                onCancel: () => Navigator.pop(context),
                onValidate: _saving ? null : _save,
                validateLabel: 'Valider la facture',
                validateKey: const ValueKey('transitaire-invoice-validate'),
                leading: Row(
                  children: [
                    const Text(
                      'Total TTC : ',
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
      ),
    );
  }

  Widget _buildHeaderFields() {
    final noTruckList =
        _transporteur != null && _transporteur!.vehicules.isEmpty;
    final trucks = _trucks;
    final currentTruck = _vehicule == null
        ? null
        : trucks.where((t) => t.$2.id == _vehicule!.id).firstOrNull;
    final plate = _currentPlate.isEmpty ? '' : ' ($_currentPlate)';
    final shared = _lines.isEmpty
        ? null
        : 'Réparti sur ${_lines.length} conteneur(s)';
    Widget amountField(
      Key key,
      TextEditingController controller,
      String label,
      IconData icon,
      VoidCallback spread,
    ) => SizedBox(
      width: 220,
      child: TextFormField(
        key: key,
        controller: controller,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _inputDecoration(
          label,
          icon: icon,
        ).copyWith(suffixText: 'F', helperText: shared),
        onChanged: (_) => setState(spread),
      ),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 260,
          child: AbsorbPointer(
            absorbing: _lines.isNotEmpty,
            child: SearchableDropdownFormField<Prestataire>(
              key: ValueKey('transitaire-invoice-partner-${_lines.isNotEmpty}'),
              options: _transitaires,
              value: _transitaire,
              label: 'Transitaire *',
              emptyText: 'Ajoutez un transitaire dans Espace Prestataire',
              displayString: (p) => p.entreprise,
              onChanged: (p) => setState(() => _transitaire = p),
            ),
          ),
        ),
        SizedBox(
          width: 250,
          child: SearchableDropdownFormField<Prestataire>(
            // La clé suit le transporteur : choisir un camion met ce champ à jour.
            key: ValueKey('transitaire-invoice-carrier-${_transporteur?.id}'),
            options: _transporteurs,
            value: _transporteur,
            label: 'Transporteur',
            emptyText: 'Ajoutez un transporteur dans Transport > Transporteurs',
            required: false,
            displayString: (p) => p.entreprise,
            // Pendant la frappe la sélection est vidée : seul un choix dans la liste compte.
            onChanged: (p) => setState(() {
              if (p == null || p.id == _transporteur?.id) return;
              _transporteur = p;
              _vehicule = null;
              _plateText.clear();
              _driverPhone.clear();
              _applyTruck();
            }),
          ),
        ),
        SizedBox(
          width: 312,
          child: Row(
            children: [
              Expanded(child: _plateField(noTruckList, trucks, currentTruck)),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                key: const ValueKey('transitaire-invoice-new-truck'),
                tooltip: 'Nouveau camion',
                onPressed: _createTruck,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 190,
          child: TextFormField(
            key: const ValueKey('transitaire-invoice-driver-phone'),
            controller: _driverPhone,
            keyboardType: TextInputType.phone,
            decoration: _inputDecoration(
              'Tél. chauffeur',
              icon: Icons.phone_rounded,
            ),
            onChanged: (_) => setState(_applyTruck),
          ),
        ),
        SizedBox(
          width: 220,
          child: TextFormField(
            key: const ValueKey('transitaire-invoice-number'),
            controller: _reference,
            decoration: _inputDecoration(
              'Numéro de facture *',
              icon: Icons.tag_rounded,
            ),
            validator: _validateReference,
          ),
        ),
        SizedBox(
          width: 190,
          child: _FormDateField(
            label: 'Date de facture',
            value: _date,
            clearable: false,
            onChanged: (date) => setState(() => _date = date ?? _date),
          ),
        ),
        SizedBox(
          width: 340,
          child: TextFormField(
            controller: _observations,
            decoration: _inputDecoration(
              'Observations',
              icon: Icons.notes_rounded,
            ),
          ),
        ),
        amountField(
          const ValueKey('transitaire-invoice-truck-advance'),
          _truckAdvance,
          'Avance camion$plate',
          Icons.payments_outlined,
          () => _spread(_truckAdvance, (l) => l.advance),
        ),
        amountField(
          const ValueKey('transitaire-invoice-truck-total'),
          _truckTotal,
          'Total transporteur$plate',
          Icons.local_shipping_rounded,
          () => _spread(_truckTotal, (l) => l.transport),
        ),
        amountField(
          const ValueKey('transitaire-invoice-global-toll'),
          _globalToll,
          'Frais de péage global',
          Icons.toll_rounded,
          _spreadToll,
        ),
      ],
    );
  }

  // Transporteur « DIVERS » qui reçoit les camions saisis sans transporteur connu.
  Prestataire? get _diversCarrier => _transporteurs
      .where((p) => p.entreprise.toUpperCase().contains('DIVERS'))
      .firstOrNull;

  // Nouveau camion saisi depuis la facture : rattaché au transporteur choisi
  // ou au transporteur DIVERS (créé au besoin avec le compte fournisseur général).
  Future<void> _createTruck() async {
    final draft = await showDialog<_NewTruck>(
      context: context,
      builder: (_) => _NewTruckDialog(
        transporteurs: _transporteurs,
        initialCarrier: _transporteur ?? _diversCarrier,
        plate: _vehicule == null ? _plateText.text : '',
        existingPlates: {
          for (final p in _transporteurs)
            for (final v in p.vehicules) _normalizePlate(v.plaque),
        },
      ),
    );
    if (draft == null || !mounted) return;
    var carrier = draft.carrier;
    final created = carrier == null;
    carrier ??= Prestataire(
      id: newLocalId('prest'),
      entreprise: 'TRANSPORTEUR DIVERS',
      type: 'Transporteur',
      pays: 'Mali',
      villePort: '',
      contact: '',
      telephone: '',
      email: '',
      services: 'Camions divers',
      compteComptable:
          _accountsForTiers(
            _planAccounts,
            nature: 'Fournisseur',
            classPrefix: '40',
          ).firstOrNull?.code ??
          '',
    );
    final vehicle = Vehicule(
      id: newLocalId('veh'),
      plaque: draft.plaque,
      chauffeur: draft.chauffeur,
      telephone: draft.telephone,
    );
    final previous = carrier.vehicules;
    carrier.vehicules = [...previous, vehicle];
    final target = carrier;
    if (!await _persist(context, () => erpBackend.savePrestataire(target))) {
      target.vehicules = previous;
      return;
    }
    if (created) {
      widget.prestataires.add(target);
      _linkTiersAccount(
        _planAccounts,
        tiersId: target.id,
        previousCode: null,
        newCode: target.compteComptable,
      );
    }
    if (!mounted) return;
    setState(() {
      _transporteur = target;
      _vehicule = vehicle;
      _plateText.text = vehicle.plaque;
      _driverPhone.text = vehicle.telephone;
      _applyTruck();
    });
  }

  Widget _plateField(
    bool noTruckList,
    List<(Prestataire, Vehicule)> trucks,
    (Prestataire, Vehicule)? currentTruck,
  ) => noTruckList || trucks.isEmpty
      ? TextFormField(
          key: const ValueKey('transitaire-invoice-plate-text'),
          controller: _plateText,
          textCapitalization: TextCapitalization.characters,
          decoration: _inputDecoration(
            'Plaque véhicule',
            icon: Icons.local_shipping_outlined,
          ),
          onChanged: (_) => setState(_applyTruck),
        )
      : SearchableDropdownFormField<(Prestataire, Vehicule)>(
          key: ValueKey('transitaire-invoice-plate-${_vehicule?.id}'),
          options: trucks,
          value: currentTruck,
          label: 'Plaque véhicule',
          emptyText: 'Aucun camion enregistré',
          required: false,
          displayString: (t) => t.$2.chauffeur.isEmpty
              ? '${t.$2.plaque} • ${t.$1.entreprise}'
              : '${t.$2.plaque} • ${t.$2.chauffeur} • ${t.$1.entreprise}',
          // Le camion choisi remplit le transporteur et le téléphone du chauffeur.
          onChanged: (t) => setState(() {
            if (t == null || t.$2.id == _vehicule?.id) return;
            _transporteur = t.$1;
            _vehicule = t.$2;
            _plateText.text = t.$2.plaque;
            _driverPhone.text = t.$2.telephone;
            _applyTruck();
          }),
        );

  Widget _buildAvailableTab(List<_AvailableContainer> available) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Rechercher un BL, un conteneur…',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('available-add-all'),
            onPressed: available.isEmpty ? null : () => _add(available),
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text(
              _search.text.trim().isEmpty
                  ? 'Tout ajouter'
                  : 'Ajouter les ${available.length} résultat(s)',
            ),
          ),
          Text(
            'Cliquez sur une ligne pour l’ajouter au détail de la facture.'
            '${_currentPlate.isEmpty ? '' : ' Camion : $_currentPlate${_transporteur == null ? '' : ' (${_transporteur!.entreprise})'}'}',
            style: const TextStyle(color: _gridMuted, fontSize: 12.5),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Expanded(
        child: ErpGrid<_AvailableContainer>(
          key: const ValueKey('available-containers-grid'),
          columns: _availableColumns,
          rows: available,
          rowId: (a) => a.cle,
          // Un clic ajoute directement le conteneur (ou le BL) à la facture.
          onSelect: (a) => _add([a]),
          emptyIcon: Icons.inventory_2_outlined,
          emptyText: _search.text.trim().isEmpty
              ? 'Aucun BL à facturer : les conteneurs des dossiers ouverts sont déjà facturés.'
              : 'Aucun BL ne correspond à la recherche.',
        ),
      ),
    ],
  );

  Widget _buildDetailsTab() {
    Widget cell(
      TextEditingController c, {
      String? hint,
      bool amount = false,
      Key? key,
      VoidCallback? sync,
    }) => TextFormField(
      key: key,
      controller: c,
      textAlign: amount ? TextAlign.right : TextAlign.start,
      keyboardType: amount
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: _cellDecoration(hint: hint),
      onChanged: (_) => setState(sync ?? () {}),
    );
    Widget fixed(String value, {Key? key}) => Text(
      value,
      key: key,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: _gridText),
    );
    String truck(_TransitLineDraft line) {
      final carrier = _transporteurs
          .where((p) => p.id == line.transporteurId)
          .firstOrNull
          ?.entreprise;
      final plate = line.plaque.text.trim();
      return [?carrier, if (plate.isNotEmpty) plate].join(' • ');
    }

    return SingleChildScrollView(
      child: _EditableTable(
        emptyText:
            'Aucun conteneur. Ajoutez-les depuis l’onglet « Liste des BL disponibles ».',
        columns: const [
          ('BL', 120),
          ('Marchandise', 140),
          ('Date de départ', 130),
          ('Numéro conteneur', 150),
          ('Type', 100),
          ('Transporteur / Véhicule', 230),
          ('Tél. chauffeur', 140),
          ('Frais de transit', 130),
          ('Surestaries / magasinage', 165),
          ('Volume et poids', 130),
          ('Autres frais', 120),
          ('Frais de péage', 120),
          ('Montant', 130),
          ('Transport dû', 130),
          ('Avance camion', 130),
          ('', 52),
        ],
        rows: [
          for (final (i, line) in _lines.indexed)
            [
              fixed(line.bl),
              fixed(line.marchandise),
              cell(line.dateDepart, hint: 'jj/mm/aaaa'),
              fixed(line.numeroConteneur.isEmpty ? '—' : line.numeroConteneur),
              fixed(line.typeConteneur),
              fixed(truck(line), key: ValueKey('line-$i-truck')),
              fixed(line.telephone.text),
              cell(
                line.transit,
                hint: '0',
                amount: true,
                key: ValueKey('line-$i-transit'),
              ),
              cell(line.demurrage, hint: '0', amount: true),
              cell(line.volume, hint: '0', amount: true),
              cell(line.other, hint: '0', amount: true),
              cell(
                line.toll,
                hint: '0',
                amount: true,
                key: ValueKey('line-$i-toll'),
                sync: _syncGlobalToll,
              ),
              Text(
                _amountText(line.montant),
                key: ValueKey('line-$i-total'),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _gridPrimary,
                ),
              ),
              cell(
                line.transport,
                hint: '0',
                amount: true,
                key: ValueKey('line-$i-transport'),
                sync: _syncTruckAmounts,
              ),
              cell(
                line.advance,
                hint: '0',
                amount: true,
                key: ValueKey('line-$i-advance'),
                sync: _syncTruckAmounts,
              ),
              IconButton(
                tooltip: 'Retirer de la facture',
                onPressed: () => setState(() {
                  _lines.removeAt(i).dispose();
                  _spreadAll();
                }),
                icon: const Icon(
                  Icons.remove_circle_outline_rounded,
                  color: Colors.redAccent,
                ),
              ),
            ],
        ],
      ),
    );
  }

  String? _validateReference(String? value) {
    final reference = value?.trim() ?? '';
    if (reference.isEmpty) return 'Champ obligatoire';
    final duplicate = widget.factures.any(
      (f) =>
          f.id != widget.initial?.id &&
          _normalizeUniqueValue(f.reference) ==
              _normalizeUniqueValue(reference),
    );
    return duplicate ? 'Ce numéro de facture existe déjà' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final transitaire = _transitaire;
    String? problem;
    if (transitaire == null) {
      problem = 'Choisissez le transitaire.';
    } else if (_lines.isEmpty) {
      problem =
          'Ajoutez au moins un conteneur depuis la liste des BL disponibles.';
    } else if (_lines.any((l) => l.hasInvalidAmount)) {
      problem =
          'Vérifiez les montants saisis : seuls des nombres positifs sont acceptés.';
    } else if (_lines.any(
      (l) =>
          l.dateDepart.text.trim().isNotEmpty &&
          _parseFrDate(l.dateDepart.text) == null,
    )) {
      problem = 'Une date de départ est invalide (format jj/mm/aaaa).';
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
    final facture = FactureTransitaire(
      id: initial?.id ?? newLocalId('ftr'),
      numero: initial?.numero ?? 0,
      reference: _reference.text.trim(),
      transitaireId: transitaire!.id,
      dateEmission: DateFormat('dd/MM/yyyy').format(_date),
      observations: _observations.text.trim(),
      lignes: _lines.map((l) => l.toLine()).toList(),
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
      () => erpBackend.saveFactureTransitaire(facture),
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    Navigator.pop(context, facture);
  }
}

class _NewTruck {
  final Prestataire? carrier;
  final String plaque;
  final String chauffeur;
  final String telephone;

  const _NewTruck(this.carrier, this.plaque, this.chauffeur, this.telephone);
}

// Saisie rapide d'un camion : plaque, chauffeur, téléphone et transporteur.
class _NewTruckDialog extends StatefulWidget {
  final List<Prestataire> transporteurs;
  final Prestataire? initialCarrier;
  final String plate;
  final Set<String> existingPlates;

  const _NewTruckDialog({
    required this.transporteurs,
    required this.initialCarrier,
    required this.plate,
    required this.existingPlates,
  });

  @override
  State<_NewTruckDialog> createState() => _NewTruckDialogState();
}

class _NewTruckDialogState extends State<_NewTruckDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _plate = TextEditingController(text: widget.plate.toUpperCase());
  final _driver = TextEditingController();
  final _phone = TextEditingController();
  late Prestataire? _carrier = widget.initialCarrier;

  @override
  void dispose() {
    _plate.dispose();
    _driver.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouveau camion'),
    content: SizedBox(
      width: 380,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('new-truck-plate'),
              controller: _plate,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: _inputDecoration(
                'Numéro du véhicule (plaque) *',
                icon: Icons.local_shipping_outlined,
              ),
              validator: (value) {
                final plate = _normalizePlate(value ?? '');
                if (plate.isEmpty) return 'Champ obligatoire';
                if (widget.existingPlates.contains(plate)) {
                  return 'Ce camion existe déjà : choisissez-le dans la liste';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('new-truck-driver'),
              controller: _driver,
              textCapitalization: TextCapitalization.words,
              decoration: _inputDecoration(
                'Nom du chauffeur',
                icon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('new-truck-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: _inputDecoration(
                'Numéro du chauffeur',
                icon: Icons.phone_rounded,
              ),
            ),
            const SizedBox(height: 12),
            SearchableDropdownFormField<Prestataire>(
              key: const ValueKey('new-truck-carrier'),
              options: widget.transporteurs,
              value: _carrier,
              label: 'Transporteur',
              emptyText: 'TRANSPORTEUR DIVERS',
              required: false,
              displayString: (p) => p.entreprise,
              onChanged: (p) => setState(() => _carrier = p),
            ),
            const SizedBox(height: 8),
            Text(
              _carrier == null
                  ? 'Sans transporteur choisi, le camion est rattaché à « TRANSPORTEUR DIVERS », créé automatiquement.'
                  : 'Le camion est ajouté à la fiche de ${_carrier!.entreprise}.',
              style: const TextStyle(color: _gridMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton.icon(
        key: const ValueKey('new-truck-save'),
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _NewTruck(
              _carrier,
              _plate.text.trim().toUpperCase(),
              _driver.text.trim(),
              _phone.text.trim(),
            ),
          );
        },
        icon: const Icon(Icons.check_rounded),
        label: const Text('Créer le camion'),
      ),
    ],
  );
}

Future<void> _printFactureTransitaire(
  FactureTransitaire f, {
  required String transitaire,
  required String Function(String) dossierNumber,
  required String Function(String) partnerName,
}) async {
  final logo = await _loadPdfLogo();
  final doc = pw.Document(
    title: 'Facture ${f.reference}',
    author: 'Sylla Transit & Transport',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
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
                  'Transitaire : $transitaire',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'FACTURE TRANSITAIRE',
                  style: pw.TextStyle(
                    fontSize: 16,
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
          [
            'BL',
            'Dossier',
            'Conteneur',
            'Type',
            'Marchandise',
            'Départ',
            'Transporteur',
            'Véhicule',
            'Transit',
            'Surestaries',
            'Vol./poids',
            'Autres',
            'Péage',
            'Montant',
          ],
          [
            for (final l in f.lignes)
              [
                l.bl,
                dossierNumber(l.dossierId),
                l.numeroConteneur,
                l.typeConteneur,
                l.marchandise,
                l.dateDepart,
                partnerName(l.transporteurId),
                l.plaque,
                formatCurrency(l.fraisTransit),
                formatCurrency(l.surestariesMagasinage),
                formatCurrency(l.volumePoids),
                formatCurrency(l.autresFrais),
                formatCurrency(l.fraisPeage),
                formatCurrency(l.montant),
              ],
          ],
          numericColumns: {8, 9, 10, 11, 12, 13},
          fontSize: 7.5,
        ),
        pw.SizedBox(height: 12),
        _pdfTotals([
          ('Total facture', '${formatCurrency(f.montant)} FCFA'),
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
    format: PdfPageFormat.a4.landscape,
    onLayout: (_) => doc.save(),
  );
}

// Nouveau règlement d'une facture.
class _PaymentDialog extends StatefulWidget {
  final List<JournalCode> journals;
  final List<ModeReglement> modes;
  final double balance;
  final String invoiceReference;

  const _PaymentDialog({
    required this.journals,
    this.modes = const [],
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
  ModeReglement? _modeReglement;

  // Avec des modes de règlement, la caisse vient du journal « fournisseurs » du mode.
  bool get _useModes => widget.modes.isNotEmpty;
  bool get _isCheque =>
      _useModes ? (_modeReglement?.estCheque ?? false) : _mode == 'Chèque';

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
              if (_useModes)
                DropdownButtonFormField<ModeReglement>(
                  key: const ValueKey('payment-mode'),
                  isExpanded: true,
                  initialValue: _modeReglement,
                  decoration: _inputDecoration(
                    'Mode de règlement *',
                    icon: Icons.payments_outlined,
                  ),
                  items: [
                    for (final mode in widget.modes)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(
                          mode.journalFournisseur.isEmpty
                              ? mode.intitule
                              : '${mode.intitule} • journal ${mode.journalFournisseur}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (value) {
                    if (value == null) return 'Choisissez le mode de règlement';
                    if (value.journalFournisseur.isEmpty) {
                      return 'Ce mode n’a pas de journal « règlement fournisseurs »';
                    }
                    return null;
                  },
                  onChanged: (value) => setState(() => _modeReglement = value),
                ),
              if (!_useModes) ...[
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
              ],
              if (_isCheque) ...[
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
        codeJournal: _useModes
            ? _modeReglement!.journalFournisseur
            : _journal!.code,
        modePaiement: _useModes ? _modeReglement!.intitule : _mode,
        numeroCheque: _isCheque ? _cheque.text.trim() : '',
        observations: _observations.text.trim(),
        auteur: _currentUser?.name ?? '',
        saisiLe: DateFormat('dd/MM/yyyy HH:mm').format(now),
      ),
    );
  }
}
