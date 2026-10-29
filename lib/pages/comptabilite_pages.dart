part of '../main.dart';

// --- COMPTABILITÉ : modes de règlement, balance âgée, saisie des journaux ---

const _paymentTypes = [
  'Espèces',
  'Chèque',
  'Virement bancaire',
  'Mobile Money',
  'Carte bancaire',
  'Traite',
];

// Codes journaux et modes de règlement réunis dans deux onglets.
class JournauxEtModesPage extends StatelessWidget {
  final List<JournalCode> journals;
  final List<PlanAccount> comptes;
  final List<ModeReglement> modes;

  const JournauxEtModesPage({
    super.key,
    required this.journals,
    required this.comptes,
    required this.modes,
  });

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        Material(
          color: Colors.white,
          child: const TabBar(
            labelColor: _gridPrimary,
            indicatorColor: _gridAccent,
            tabs: [
              Tab(icon: Icon(Icons.menu_book_rounded), text: 'Codes journaux'),
              Tab(
                icon: Icon(Icons.payments_rounded),
                text: 'Modes de règlement',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              JournalCodesPage(journals: journals, comptes: comptes),
              ModesReglementPage(
                modes: modes,
                journals: journals,
                comptes: comptes,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ModesReglementPage extends StatefulWidget {
  final List<ModeReglement> modes;
  final List<JournalCode> journals;
  final List<PlanAccount> comptes;

  const ModesReglementPage({
    super.key,
    required this.modes,
    required this.journals,
    required this.comptes,
  });

  @override
  State<ModesReglementPage> createState() => _ModesReglementPageState();
}

class _ModesReglementPageState extends State<ModesReglementPage> {
  final _formKey = GlobalKey<FormState>();
  final _intitule = TextEditingController();
  ModeReglement? _editing;
  String _type = _paymentTypes.first;
  String? _journalClient;
  String? _journalFournisseur;
  String? _compte;
  bool _saving = false;

  List<PlanAccount> get _treasuryAccounts =>
      widget.comptes
          .where(
            (a) =>
                a.code.startsWith('5') ||
                a.nature == 'Banque' ||
                a.nature == 'Caisse',
          )
          .toList()
        ..sort((a, b) => a.code.compareTo(b.code));

  @override
  void dispose() {
    _intitule.dispose();
    super.dispose();
  }

  String? _known(String? code, Iterable<String> codes) =>
      code != null && code.isNotEmpty && codes.contains(code) ? code : null;

  void _edit(ModeReglement? mode) => setState(() {
    _editing = mode;
    _intitule.text = mode?.intitule ?? '';
    _type = _paymentTypes.contains(mode?.type)
        ? mode!.type
        : _paymentTypes.first;
    final codes = widget.journals.map((j) => j.code);
    _journalClient = _known(mode?.journalClient, codes);
    _journalFournisseur = _known(mode?.journalFournisseur, codes);
    _compte = _known(
      mode?.compteTresorerie,
      _treasuryAccounts.map((a) => a.code),
    );
  });

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF4F6FB),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final list = _buildList();
        final form = _buildForm();
        return wide
            ? Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: list),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(child: form),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(10),
                children: [form, const SizedBox(height: 14), list],
              );
      },
    ),
  );

  Widget _buildList() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _gridBorder),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
          child: Row(
            children: [
              const Icon(Icons.payments_rounded, color: _gridAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Modes de règlement',
                  style: TextStyle(
                    color: _gridText,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('mode-new'),
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nouveau'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (widget.modes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aucun mode de règlement. Créez par exemple « ESPECES », « CHEQUES » ou « VIREMENT BIM » et associez-leur les journaux de caisse ou de banque.',
              style: TextStyle(color: _gridMuted),
            ),
          ),
        for (final mode in widget.modes)
          ListTile(
            key: ValueKey('mode-${mode.id}'),
            selected: _editing?.id == mode.id,
            selectedTileColor: const Color(0xFFE8EAFF),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFE8EAF6),
              child: Icon(switch (mode.type) {
                'Chèque' => Icons.receipt_rounded,
                'Virement bancaire' => Icons.account_balance_rounded,
                'Mobile Money' => Icons.phone_iphone_rounded,
                'Carte bancaire' => Icons.credit_card_rounded,
                _ => Icons.payments_outlined,
              }, color: _gridAccent),
            ),
            title: Text(
              mode.intitule,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Type : ${mode.type} • Jnl client : ${mode.journalClient.isEmpty ? '—' : mode.journalClient} • '
              'Jnl fourn. : ${mode.journalFournisseur.isEmpty ? '—' : mode.journalFournisseur}'
              '${mode.compteTresorerie.isEmpty ? '' : ' • Compte ${mode.compteTresorerie}'}',
            ),
            onTap: () => _edit(mode),
            trailing: IconButton(
              tooltip: 'Supprimer ce mode',
              onPressed: () => _delete(mode),
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildForm() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _gridBorder),
    ),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _editing == null
                ? 'Nouveau mode de règlement'
                : 'Modifier « ${_editing!.intitule} »',
            style: const TextStyle(
              color: _gridText,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('mode-intitule'),
            controller: _intitule,
            textCapitalization: TextCapitalization.characters,
            decoration: _inputDecoration(
              'Intitulé du mode *',
              icon: Icons.label_outline_rounded,
              hint: 'ESPECES, CHEQUES, VIREMENT BIM…',
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Champ obligatoire';
              final duplicate = widget.modes.any(
                (m) =>
                    m.id != _editing?.id &&
                    _normalizeUniqueValue(m.intitule) ==
                        _normalizeUniqueValue(text),
              );
              return duplicate ? 'Ce mode existe déjà' : null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('mode-type-${_editing?.id}'),
            isExpanded: true,
            initialValue: _type,
            decoration: _inputDecoration(
              'Type de règlement',
              icon: Icons.category_outlined,
            ),
            items: [
              for (final type in _paymentTypes)
                DropdownMenuItem(value: type, child: Text(type)),
            ],
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
          const SizedBox(height: 18),
          const Text(
            'CODES JOURNAUX ASSOCIÉS',
            style: TextStyle(
              color: _gridMuted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          _journalField(
            'Règlement clients',
            _journalClient,
            (v) => _journalClient = v,
            'mode-journal-client',
          ),
          const SizedBox(height: 12),
          _journalField(
            'Règlement fournisseurs',
            _journalFournisseur,
            (v) => _journalFournisseur = v,
            'mode-journal-fournisseur',
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            key: ValueKey('mode-compte-${_editing?.id}'),
            isExpanded: true,
            initialValue: _compte,
            decoration: _inputDecoration(
              'Compte général de trésorerie',
              icon: Icons.account_balance_rounded,
            ),
            items: [
              for (final account in _treasuryAccounts)
                DropdownMenuItem(
                  value: account.code,
                  child: Text(
                    '${account.code} - ${account.libelle}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _compte = value),
          ),
          if (_treasuryAccounts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Aucun compte de classe 5 (banque, caisse) dans le plan comptable.',
                style: TextStyle(color: Color(0xFFB45309), fontSize: 12),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_editing != null)
                TextButton(
                  onPressed: () => _edit(null),
                  child: const Text('Annuler'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('mode-save'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Enregistrer'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _journalField(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
    String key,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$key-${_editing?.id}'),
    isExpanded: true,
    initialValue: value,
    decoration: _inputDecoration(label, icon: Icons.menu_book_outlined),
    items: [
      for (final journal in widget.journals)
        DropdownMenuItem(
          value: journal.code,
          child: Text(
            '${journal.code} • ${journal.intitule}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (v) => setState(() => onChanged(v)),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final mode = ModeReglement(
      id: _editing?.id ?? newLocalId('mode'),
      intitule: _intitule.text.trim().toUpperCase(),
      type: _type,
      journalClient: _journalClient ?? '',
      journalFournisseur: _journalFournisseur ?? '',
      compteTresorerie: _compte ?? '',
    );
    setState(() => _saving = true);
    final saved = await _persist(
      context,
      () => erpBackend.saveModeReglement(mode),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!saved) return;
      final index = widget.modes.indexWhere((m) => m.id == mode.id);
      if (index < 0) {
        widget.modes.add(mode);
      } else {
        widget.modes[index] = mode;
      }
    });
    if (saved) _edit(null);
  }

  Future<void> _delete(ModeReglement mode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce mode de règlement ?'),
        content: Text('« ${mode.intitule} » sera supprimé.'),
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
    if (!await _persist(context, () => erpBackend.deleteModeReglement(mode))) {
      return;
    }
    if (!mounted) return;
    setState(() => widget.modes.removeWhere((m) => m.id == mode.id));
    if (_editing?.id == mode.id) _edit(null);
  }
}

// --- BALANCE ÂGÉE DES CLIENTS ---

class _AgedBalanceRow {
  final Client client;
  double nonEchu = 0;
  double days15 = 0;
  double days30 = 0;
  double days45 = 0;
  double over46 = 0;

  _AgedBalanceRow(this.client);

  String get compte => client.compteComptable;
  double get solde => nonEchu + days15 + days30 + days45 + over46;

  void add(int? age, double amount) {
    if (age == null || age >= 46) {
      over46 += amount;
    } else if (age < 0) {
      nonEchu += amount;
    } else if (age <= 15) {
      days15 += amount;
    } else if (age <= 30) {
      days30 += amount;
    } else {
      days45 += amount;
    }
  }
}

// Calcule les impayés par client, ventilés selon l'ancienneté des factures.
// Les règlements soldent d'abord les factures les plus anciennes.
List<_AgedBalanceRow> _computeAgedBalance(
  List<Client> clients,
  List<TransitDossier> dossiers,
  DateTime reference,
) {
  final day = DateTime(reference.year, reference.month, reference.day);
  final rows = <_AgedBalanceRow>[];
  for (final client in clients) {
    final debts = <(DateTime?, double)>[];
    var paid = 0.0;
    if (client.soldeInitial > 0) debts.add((null, client.soldeInitial));
    for (final d in dossiers.where((d) => d.client.id == client.id)) {
      final invoice = d.factureClient;
      if (invoice.estValidee && invoice.montant > 0) {
        debts.add((_parseFrDate(invoice.dateEmission), invoice.montant));
      }
      for (final op in d.operations) {
        final date = _parseFrDate(op.date);
        if (date != null && date.isAfter(day.add(const Duration(days: 1)))) {
          continue;
        }
        if (op.type == DossierOperationType.clientInvoice) {
          debts.add((date, op.montant));
        } else if (op.type == DossierOperationType.clientPayment) {
          paid += op.montant;
        }
      }
    }
    debts.sort((a, b) {
      if (a.$1 == null) return -1;
      if (b.$1 == null) return 1;
      return a.$1!.compareTo(b.$1!);
    });
    final row = _AgedBalanceRow(client);
    for (final (date, amount) in debts) {
      final settled = math.min(paid, amount);
      paid -= settled;
      final remaining = amount - settled;
      if (remaining <= 0) continue;
      final age = date == null
          ? null
          : day.difference(DateTime(date.year, date.month, date.day)).inDays;
      row.add(age, remaining);
    }
    if (row.solde > 0.5) rows.add(row);
  }
  rows.sort((a, b) => b.solde.compareTo(a.solde));
  return rows;
}

String _dash(double value) => value.abs() < 0.5 ? '-' : formatCurrency(value);

class BalanceAgeePage extends StatefulWidget {
  final List<Client> clients;
  final List<TransitDossier> dossiers;

  const BalanceAgeePage({
    super.key,
    required this.clients,
    required this.dossiers,
  });

  @override
  State<BalanceAgeePage> createState() => _BalanceAgeePageState();
}

class _BalanceAgeePageState extends State<BalanceAgeePage> {
  DateTime _reference = DateTime.now();
  String _query = '';

  late final List<ErpGridColumn<_AgedBalanceRow>> _columns = [
    ErpGridColumn(label: 'Compte', width: 150, value: (r) => r.compte),
    ErpGridColumn(label: 'Intitulé', width: 260, value: (r) => r.client.nom),
    ErpGridColumn(
      label: 'Solde',
      width: 140,
      numeric: true,
      value: (r) => _dash(r.solde),
      sortValue: (r) => r.solde,
      builder: (r) => Text(
        _dash(r.solde),
        style: const TextStyle(
          color: _gridPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    ErpGridColumn(
      label: 'Non échu',
      width: 120,
      numeric: true,
      value: (r) => _dash(r.nonEchu),
      sortValue: (r) => r.nonEchu,
    ),
    ErpGridColumn(
      label: '1 à 15 j',
      width: 120,
      numeric: true,
      value: (r) => _dash(r.days15),
      sortValue: (r) => r.days15,
    ),
    ErpGridColumn(
      label: '16 à 30 j',
      width: 120,
      numeric: true,
      value: (r) => _dash(r.days30),
      sortValue: (r) => r.days30,
    ),
    ErpGridColumn(
      label: '31 à 45 j',
      width: 120,
      numeric: true,
      value: (r) => _dash(r.days45),
      sortValue: (r) => r.days45,
    ),
    ErpGridColumn(
      label: '+ 46 j',
      width: 130,
      numeric: true,
      value: (r) => _dash(r.over46),
      sortValue: (r) => r.over46,
      builder: (r) => Text(
        _dash(r.over46),
        style: const TextStyle(color: Color(0xFFDC2626)),
      ),
    ),
  ];

  List<_AgedBalanceRow> get _rows {
    final query = _query.trim().toLowerCase();
    return _computeAgedBalance(
      widget.clients,
      widget.dossiers,
      _reference,
    ).where((r) {
      if (query.isEmpty) return true;
      return '${r.compte} ${r.client.nom}'.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final total = rows.fold<double>(0, (sum, r) => sum + r.solde);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_gridPrimary, _gridAccent],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 10,
                spacing: 12,
                children: [
                  const Text(
                    'Balance Âgée des Clients',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Actualiser',
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      IconButton.filledTonal(
                        key: const ValueKey('aged-balance-pdf'),
                        tooltip: 'Imprimer / PDF',
                        onPressed: () =>
                            _printAgedBalance(rows, _reference, total),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Exporter (Excel)',
                        onPressed: () => _exportGrid(
                          context,
                          baseName: 'balance_agee_clients',
                          columns: _columns,
                          rows: rows,
                        ),
                        icon: const Icon(Icons.table_chart_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gridBorder),
              ),
              child: Wrap(
                spacing: 14,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ErpDateFilter(
                    label: 'Date de référence',
                    value: _reference,
                    onChanged: (value) =>
                        setState(() => _reference = value ?? DateTime.now()),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'Rechercher un client ou un compte…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'Total impayé global : ${formatCurrency(total)} F CFA  •  ${rows.length} client(s)',
                    key: const ValueKey('aged-balance-total'),
                    style: const TextStyle(
                      color: _gridPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: math.max(460, constraints.maxHeight - 230),
              child: ErpGrid<_AgedBalanceRow>(
                key: const ValueKey('aged-balance-grid'),
                columns: _columns,
                rows: rows,
                rowId: (r) => r.client.id,
                emptyIcon: Icons.verified_rounded,
                emptyText: 'Aucun impayé client à cette date.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<pw.MemoryImage?> _loadPdfLogo() async {
  try {
    final data = await rootBundle.load('assets/logo.png');
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

Future<void> _printAgedBalance(
  List<_AgedBalanceRow> rows,
  DateTime reference,
  double total,
) async {
  final logo = await _loadPdfLogo();
  const headerColor = PdfColor.fromInt(0xFF37474F);
  final cellStyle = const pw.TextStyle(fontSize: 8);
  final doc = pw.Document(
    title: 'Balance âgée des clients',
    author: 'Sylla Transit & Transport',
  );
  double sum(double Function(_AgedBalanceRow) pick) =>
      rows.fold(0, (s, r) => s + pick(r));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (logo != null) ...[
              pw.Image(logo, height: 42),
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
                  'Date de tirage : ${DateFormat('dd/MM/yyyy').format(DateTime.now())}'
                  '   •   Arrêtée au ${DateFormat('dd/MM/yyyy').format(reference)}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              'BALANCE ÂGÉE DES CLIENTS',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'Sylla Transit & Transport  |  Page ${context.pageNumber}/${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: [
            'Compte',
            'Intitulé',
            'Solde',
            'Non échu',
            '1 à 15 j',
            '16 à 30 j',
            '31 à 45 j',
            '+ 46 j',
          ],
          data: [
            for (final r in rows)
              [
                r.compte,
                r.client.nom,
                _dash(r.solde),
                _dash(r.nonEchu),
                _dash(r.days15),
                _dash(r.days30),
                _dash(r.days45),
                _dash(r.over46),
              ],
            [
              '',
              'TOTAL (${rows.length} client(s))',
              _dash(total),
              _dash(sum((r) => r.nonEchu)),
              _dash(sum((r) => r.days15)),
              _dash(sum((r) => r.days30)),
              _dash(sum((r) => r.days45)),
              _dash(sum((r) => r.over46)),
            ],
          ],
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 8,
          ),
          headerDecoration: const pw.BoxDecoration(color: headerColor),
          cellStyle: cellStyle,
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 5,
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(62),
            1: const pw.FlexColumnWidth(2.6),
            for (var i = 2; i < 8; i++) i: const pw.FlexColumnWidth(1.1),
          },
          cellAlignments: {
            for (var i = 2; i < 8; i++) i: pw.Alignment.centerRight,
          },
          headerAlignments: {
            for (var i = 2; i < 8; i++) i: pw.Alignment.centerRight,
          },
          border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
        ),
      ],
    ),
  );
  await Printing.layoutPdf(
    name: 'Balance agee clients ${DateFormat('dd-MM-yyyy').format(reference)}',
    onLayout: (_) => doc.save(),
  );
}

// --- SAISIE DES JOURNAUX ---

enum _JournalStatus { all, open, notOpen }

const _shortMonths = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

const _accountingCategories = [
  (
    'ventes',
    'Factures de Ventes',
    'Déversement dans le journal VEN (411 Clients / 706 Services vendus)',
  ),
  (
    'achats',
    'Factures d’Achats Fournisseurs',
    'Déversement dans le journal ACH (601 Achats / 401 Fournisseurs)',
  ),
  (
    'reglements',
    'Règlements & Encaissements',
    'Déversement dans le journal de la caisse ou de la banque utilisée (5xx Trésorerie / 411 – 401)',
  ),
  (
    'depenses',
    'Dépenses d’Exploitation',
    'Déversement dans le journal CAD (638 Charges / 571 Caisse)',
  ),
  (
    'transit',
    'Frais de Transit & Douane',
    'Déversement dans le journal ACH (6012 Frais de transit / 4012 Transitaires)',
  ),
  (
    'paie',
    'Salaires / Paie',
    'Journal PAIE (661 Rémunérations / 571-521 Trésorerie) — aucune donnée de paie pour l’instant',
  ),
  (
    'avances',
    'Avances & Acomptes',
    'Déversement dans le journal OD (409 Avances fournisseurs / 5xx Trésorerie)',
  ),
];

class _JournalRow {
  final String journal;
  final String intitule;
  final int year;
  final int month;
  final JournalPeriode? periode;

  const _JournalRow(
    this.journal,
    this.intitule,
    this.year,
    this.month,
    this.periode,
  );

  bool get isOpen => periode != null;
  String get moisCle => '$year-${month.toString().padLeft(2, '0')}';
  String get libellePeriode =>
      '${_shortMonths[month - 1]} ${year.toString().substring(2)}';
}

class SaisieJournauxPage extends StatefulWidget {
  final List<JournalCode> journals;

  const SaisieJournauxPage({super.key, required this.journals});

  @override
  State<SaisieJournauxPage> createState() => _SaisieJournauxPageState();
}

class _SaisieJournauxPageState extends State<SaisieJournauxPage> {
  int _year = DateTime.now().year;
  _JournalStatus _status = _JournalStatus.all;
  JournauxSynthese? _synthese;
  String? _error;
  bool _loading = false;
  _JournalRow? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final synthese = await erpBackend.journauxComptables(_year);
      if (mounted) setState(() => _synthese = synthese);
    } on ErpBackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_JournalRow> get _allRows {
    final periodes = _synthese?.periodes ?? const <JournalPeriode>[];
    final now = DateTime.now();
    final lastMonth = _year == now.year ? now.month : 12;
    final codes = {
      for (final j in widget.journals) j.code: j.intitule,
      for (final p in periodes) p.journal: '',
    };
    final rows = <_JournalRow>[];
    for (var month = 1; month <= lastMonth; month++) {
      final key = '$_year-${month.toString().padLeft(2, '0')}';
      for (final entry in codes.entries) {
        rows.add(
          _JournalRow(
            entry.key,
            entry.value.isNotEmpty
                ? entry.value
                : widget.journals
                          .where((j) => j.code == entry.key)
                          .firstOrNull
                          ?.intitule ??
                      '',
            _year,
            month,
            periodes
                .where((p) => p.journal == entry.key && p.mois == key)
                .firstOrNull,
          ),
        );
      }
    }
    return rows;
  }

  late final List<ErpGridColumn<_JournalRow>> _columns = [
    ErpGridColumn(
      label: 'Période',
      width: 110,
      value: (r) => r.libellePeriode,
      sortValue: (r) => r.moisCle,
    ),
    ErpGridColumn(label: 'Code', width: 90, value: (r) => r.journal),
    ErpGridColumn(label: 'Intitulé', width: 230, value: (r) => r.intitule),
    ErpGridColumn(
      label: 'Écritures',
      width: 100,
      numeric: true,
      value: (r) => '${r.periode?.ecritures ?? 0}',
      sortValue: (r) => r.periode?.ecritures ?? 0,
    ),
    ErpGridColumn(
      label: 'Total débit',
      width: 140,
      numeric: true,
      value: (r) => _dash(r.periode?.debit ?? 0),
      sortValue: (r) => r.periode?.debit ?? 0,
    ),
    ErpGridColumn(
      label: 'Total crédit',
      width: 140,
      numeric: true,
      value: (r) => _dash(r.periode?.credit ?? 0),
      sortValue: (r) => r.periode?.credit ?? 0,
    ),
    ErpGridColumn(
      label: 'Statut',
      width: 130,
      value: (r) => r.isOpen ? 'Ouvert' : 'Non ouvert',
      builder: (r) => r.isOpen
          ? const ErpStatusChip('Ouvert', Color(0xFF15803D))
          : const ErpStatusChip('Non ouvert', Color(0xFF94A3B8)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final all = _allRows;
    final rows = all
        .where(
          (r) => switch (_status) {
            _JournalStatus.all => true,
            _JournalStatus.open => r.isOpen,
            _JournalStatus.notOpen => !r.isOpen,
          },
        )
        .toList();
    final openCount = all.where((r) => r.isOpen).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final grid = ErpGrid<_JournalRow>(
            key: const ValueKey('journals-grid'),
            columns: _columns,
            rows: rows,
            rowId: (r) => '${r.journal}-${r.moisCle}',
            selected: _selected,
            onSelect: (r) => setState(() => _selected = r),
            onOpen: _openEntries,
            emptyIcon: Icons.menu_book_outlined,
            emptyText: _error ?? 'Aucun journal pour cette sélection.',
          );
          final filters = _statusFilters(all.length, openCount);
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              if (!wide) ...[filters, const SizedBox(height: 12)],
              SizedBox(
                height: math.max(480, constraints.maxHeight - 200),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 200, child: filters),
                          const SizedBox(width: 12),
                          Expanded(child: grid),
                        ],
                      )
                    : grid,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [_gridPrimary, _gridAccent]),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            const Text(
              'Saisie des journaux',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<int>(
                    value: _year,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (var y = DateTime.now().year; y >= 2024; y--)
                        DropdownMenuItem(value: y, child: Text('Exercice $y')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _year = value;
                        _selected = null;
                      });
                      _load();
                    },
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Actualiser',
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                FilledButton.icon(
                  key: const ValueKey('accounting-update'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _gridPrimary,
                  ),
                  onPressed: _runUpdate,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Mise à jour comptable'),
                ),
              ],
            ),
          ],
        ),
        if ((_synthese?.derniereMiseAJour ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _synthese!.derniereMiseAJour,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Color(0xFFFECACA))),
        ],
      ],
    ),
  );

  Widget _statusFilters(int total, int open) {
    Widget item(_JournalStatus status, IconData icon, String label, int n) =>
        ListTile(
          dense: true,
          selected: _status == status,
          selectedTileColor: const Color(0xFFE8EAFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: Icon(icon, size: 20),
          title: Text(label),
          trailing: Text('$n', style: const TextStyle(color: _gridMuted)),
          onTap: () => setState(() => _status = status),
        );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gridBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(_JournalStatus.all, Icons.list_rounded, 'Tous', total),
          item(_JournalStatus.open, Icons.folder_open_rounded, 'Ouverts', open),
          item(
            _JournalStatus.notOpen,
            Icons.folder_rounded,
            'Non ouverts',
            total - open,
          ),
        ],
      ),
    );
  }

  // Un journal non ouvert peut aussi recevoir des lignes saisies à la main.
  Future<void> _openEntries(_JournalRow row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JournalSaisiePage(
          journal: row.journal,
          intitule: row.intitule,
          year: row.year,
          month: row.month,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _runUpdate() async {
    final result = await showDialog<MiseAJourResultat>(
      context: context,
      builder: (context) => const _MiseAJourComptableDialog(),
    );
    if (result == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.task_alt_rounded,
          color: Color(0xFF15803D),
          size: 40,
        ),
        title: Text('${result.ecritures} écriture(s) comptabilisée(s)'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (key, label, _) in _accountingCategories)
                if (result.categories.containsKey(key))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    trailing: Text(
                      '${result.categories[key]!.$1} écr. • ${_amountText(result.categories[key]!.$2)}',
                    ),
                  ),
              for (final message in result.ignores)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• $message',
                    style: const TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }
}

class _MiseAJourComptableDialog extends StatefulWidget {
  const _MiseAJourComptableDialog();

  @override
  State<_MiseAJourComptableDialog> createState() =>
      _MiseAJourComptableDialogState();
}

class _MiseAJourComptableDialogState extends State<_MiseAJourComptableDialog> {
  late DateTimeRange _range;
  final Set<String> _selected = {
    for (final (key, _, _) in _accountingCategories) key,
  };
  bool _running = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(today.year, today.month - 1, today.day),
      end: DateTime(today.year, today.month, today.day),
    );
  }

  String _fr(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: SizedBox(
      width: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dialogHeader(
            icon: Icons.sync_rounded,
            title: 'Mise à jour de la comptabilité',
            subtitle: 'Déversement des opérations de gestion dans les journaux',
            onClose: () => Navigator.pop(context),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(18),
              children: [
                const Text(
                  'Période à déverser dans les journaux :',
                  style: TextStyle(color: _gridPrimary),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6FB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.date_range_rounded,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Du ${_fr(_range.start)} au ${_fr(_range.end)}',
                          key: const ValueKey('accounting-period'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: _pickRange,
                        child: const Text('Changer'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sélectionnez les opérations à comptabiliser :',
                  style: TextStyle(color: _gridPrimary),
                ),
                const SizedBox(height: 6),
                for (final (key, title, description) in _accountingCategories)
                  CheckboxListTile(
                    key: ValueKey('accounting-category-$key'),
                    value: _selected.contains(key),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(title),
                    subtitle: Text(
                      description,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selected.add(key);
                      } else {
                        _selected.remove(key);
                      }
                    }),
                  ),
                const SizedBox(height: 6),
                const Text(
                  'Relancer la mise à jour sur une même période remplace les écritures générées : rien n’est compté deux fois.',
                  style: TextStyle(color: _gridMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          _dialogFooter(
            onCancel: () => Navigator.pop(context),
            onValidate: _running || _selected.isEmpty ? null : _run,
            validateLabel: _running
                ? 'Comptabilisation…'
                : 'Lancer la mise à jour comptable',
            validateKey: const ValueKey('accounting-run'),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      helpText: 'Période à déverser',
      cancelText: 'Annuler',
      confirmText: 'Valider',
      saveText: 'Valider',
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final result = await erpBackend.miseAJourComptable(
        du: _fr(_range.start),
        au: _fr(_range.end),
        categories: [
          for (final (key, _, _) in _accountingCategories)
            if (_selected.contains(key)) key,
        ],
      );
      if (mounted) Navigator.pop(context, result);
    } on ErpBackendException catch (error) {
      if (!mounted) return;
      setState(() => _running = false);
      await _showInfoAlert(
        context,
        title: 'Mise à jour impossible',
        message: error.message,
      );
    }
  }
}
