part of '../main.dart';

// --- TYPES DE FRAIS et CONTRÔLE DE CAISSE ---

class TypesFraisPage extends StatefulWidget {
  final List<TypeFrais> types;
  final List<PlanAccount> comptes;

  const TypesFraisPage({super.key, required this.types, required this.comptes});

  @override
  State<TypesFraisPage> createState() => _TypesFraisPageState();
}

class _TypesFraisPageState extends State<TypesFraisPage> {
  final _formKey = GlobalKey<FormState>();
  final _libelle = TextEditingController();
  final _montant = TextEditingController();
  TypeFrais? _editing;
  String? _general;
  bool _saving = false;
  int _formVersion = 0;

  // Comptes généraux de charges (classe 6) auxquels rattacher les frais.
  List<PlanAccount> get _generals =>
      widget.comptes
          .where((a) => a.code.startsWith('6') && isGeneralAccountCode(a.code))
          .toList()
        ..sort((a, b) => a.code.compareTo(b.code));

  String _accountLabel(String code) {
    if (code.isEmpty) return '';
    final account = widget.comptes.where((a) => a.code == code).firstOrNull;
    return account == null ? code : '$code — ${account.libelle}';
  }

  late final List<ErpGridColumn<TypeFrais>> _columns = [
    ErpGridColumn(
      label: 'ID',
      width: 70,
      numeric: true,
      value: (t) => t.numero == 0 ? '' : '${t.numero}',
      sortValue: (t) => t.numero,
    ),
    ErpGridColumn(label: 'Libellé', width: 280, value: (t) => t.libelle),
    ErpGridColumn(
      label: 'Compte général',
      width: 260,
      value: (t) => _accountLabel(t.compteGeneral),
    ),
    ErpGridColumn(label: 'Sous-compte', width: 140, value: (t) => t.compte),
    ErpGridColumn(
      label: 'Montant',
      width: 140,
      numeric: true,
      value: (t) => formatCurrency(t.montant),
      sortValue: (t) => t.montant,
    ),
  ];

  @override
  void dispose() {
    _libelle.dispose();
    _montant.dispose();
    super.dispose();
  }

  void _edit(TypeFrais? type) => setState(() {
    _editing = type;
    _formVersion++;
    _libelle.text = type?.libelle ?? '';
    _montant.text = type == null || type.montant == 0
        ? ''
        : type.montant.toStringAsFixed(0);
    final generals = _generals.map((a) => a.code);
    _general = generals.contains(type?.compteGeneral)
        ? type!.compteGeneral
        : null;
  });

  // Sous-compte affiché : celui du type, ou le prochain numéro libre.
  String get _subAccountPreview {
    final general = _general;
    if (general == null) return '';
    final editing = _editing;
    if (editing != null &&
        editing.compteGeneral == general &&
        editing.compte.isNotEmpty) {
      return '${editing.compte} (sous-compte existant)';
    }
    return '${nextSubAccountCode(general, widget.comptes.map((a) => a.code))} (créé automatiquement)';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6FB),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final grid = ErpGrid<TypeFrais>(
          key: const ValueKey('fee-types-grid'),
          columns: _columns,
          rows: widget.types,
          rowId: (t) => t.id,
          selected: _editing,
          onSelect: _edit,
          emptyIcon: Icons.receipt_long_outlined,
          emptyText:
              'Aucun type de frais. Saisissez un libellé et choisissez son compte général.',
        );
        final form = _buildForm();
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            if (wide)
              SizedBox(
                height: math.max(480, constraints.maxHeight - 130),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 380,
                      child: SingleChildScrollView(child: form),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: grid),
                  ],
                ),
              )
            else ...[
              form,
              const SizedBox(height: 12),
              SizedBox(height: 480, child: grid),
            ],
          ],
        );
      },
    ),
  );

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [_gridPrimary, _gridAccent]),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        const Text(
          'Types de frais',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Nombre de types de frais : ${widget.types.length}',
          key: const ValueKey('fee-types-count'),
          style: const TextStyle(color: Colors.white70),
        ),
        FilledButton.icon(
          key: const ValueKey('fee-type-new'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: _gridPrimary,
          ),
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nouveau type de frais'),
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
                ? 'Nouveau type de frais'
                : 'Modifier « ${_editing!.libelle} »',
            style: const TextStyle(
              color: _gridText,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('fee-type-label'),
            controller: _libelle,
            textCapitalization: TextCapitalization.characters,
            decoration: _inputDecoration(
              'Libellé *',
              icon: Icons.label_outline_rounded,
              hint: 'AMENDE, DROIT DE DOUANE…',
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Champ obligatoire';
              final duplicate = widget.types.any(
                (t) =>
                    t.id != _editing?.id &&
                    _normalizeUniqueValue(t.libelle) ==
                        _normalizeUniqueValue(text),
              );
              return duplicate ? 'Ce type de frais existe déjà' : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('fee-type-amount'),
            controller: _montant,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration(
              'Montant par défaut',
              icon: Icons.payments_outlined,
            ).copyWith(suffixText: 'FCFA'),
            validator: (value) {
              final amount = _parseAmount(value ?? '');
              return amount == null || amount < 0 ? 'Montant invalide' : null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('fee-type-general-$_formVersion'),
            isExpanded: true,
            initialValue: _general,
            decoration: _inputDecoration(
              'Compte général *',
              icon: Icons.account_tree_outlined,
            ),
            items: [
              for (final account in _generals)
                DropdownMenuItem(
                  value: account.code,
                  child: Text(
                    '${account.code} — ${account.libelle}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            validator: (value) =>
                value == null ? 'Choisissez le compte général' : null,
            onChanged: (value) => setState(() => _general = value),
          ),
          if (_generals.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Aucun compte général de classe 6 (ex. 65880000) dans le plan comptable.',
                style: TextStyle(color: Color(0xFFB45309), fontSize: 12),
              ),
            ),
          if (_subAccountPreview.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.subdirectory_arrow_right_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sous-compte : $_subAccountPreview',
                      key: const ValueKey('fee-type-subaccount'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_editing != null)
                OutlinedButton.icon(
                  key: const ValueKey('fee-type-delete'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Supprimer'),
                ),
              FilledButton.icon(
                key: const ValueKey('fee-type-save'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(_editing == null ? 'Enregistrer' : 'Modifier'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final previous = _editing;
    final type = TypeFrais(
      id: previous?.id ?? newLocalId('frais'),
      numero: previous?.numero ?? 0,
      libelle: _libelle.text.trim().toUpperCase(),
      montant: _parseAmount(_montant.text) ?? 0,
      compteGeneral: _general ?? '',
      compte: previous?.compteGeneral == _general ? previous?.compte ?? '' : '',
    );
    setState(() => _saving = true);
    PlanAccount? created;
    final saved = await _persist(context, () async {
      created = await erpBackend.saveTypeFrais(type);
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!saved) return;
      final account = created;
      if (account != null &&
          !widget.comptes.any((a) => a.code == account.code)) {
        widget.comptes.add(account);
      }
      // Le libellé du sous-compte suit celui du type de frais.
      for (final a in widget.comptes.where((a) => a.code == type.compte)) {
        a.libelle = type.libelle;
      }
      final index = widget.types.indexWhere((t) => t.id == type.id);
      if (index < 0) {
        widget.types.add(type);
      } else {
        widget.types[index] = type;
      }
    });
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created == null
              ? '« ${type.libelle} » enregistré.'
              : '« ${type.libelle} » enregistré : sous-compte ${type.compte} créé sous ${type.compteGeneral}.',
        ),
      ),
    );
    _edit(null);
  }

  Future<void> _delete() async {
    final type = _editing;
    if (type == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce type de frais ?'),
        content: Text(
          '« ${type.libelle} » sera supprimé. Son sous-compte ${type.compte} reste dans le plan comptable.',
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
    if (!await _persist(context, () => erpBackend.deleteTypeFrais(type))) {
      return;
    }
    if (!mounted) return;
    setState(() => widget.types.removeWhere((t) => t.id == type.id));
    _edit(null);
  }
}

// --- CONTRÔLE DE CAISSE ---

class _CashLine {
  final DateTime date;
  final String piece;
  final String compteGeneral;
  final String compteTiers;
  final String libelle;
  final double recette;
  final double depense;
  double solde = 0;
  final int order;

  _CashLine({
    required this.date,
    required this.piece,
    required this.compteGeneral,
    required this.compteTiers,
    required this.libelle,
    required this.recette,
    required this.depense,
    required this.order,
  });
}

class CashControlPage extends StatefulWidget {
  final List<TransitDossier> dossiers;
  final List<JournalCode> journals;

  const CashControlPage({
    super.key,
    required this.dossiers,
    required this.journals,
  });

  @override
  State<CashControlPage> createState() => _CashControlPageState();
}

class _CashControlPageState extends State<CashControlPage> {
  JournalCode? _journal;
  DateTime? _start = DateTime(DateTime.now().year, 1, 1);
  DateTime? _end = DateTime(DateTime.now().year, 12, 31);
  String _query = '';

  static final _dateFormat = DateFormat('dd/MM/yy');

  String _treasury(String journalCode) =>
      widget.journals
          .where((j) => j.code == journalCode)
          .firstOrNull
          ?.compteTresorerie ??
      '';

  Prestataire? _partner(TransitDossier d, DossierOperation op) =>
      switch (op.categorie) {
        'Règlement Transitaire' => d.transitaireAffecte ?? d.prestataire,
        'Règlement Transporteur' => d.transporteurAffecte ?? d.prestataire,
        _ => d.prestataire,
      };

  // Lignes de caisse : encaissements clients, paiements et avances fournisseurs, frais.
  List<_CashLine> get _lines {
    final lines = <_CashLine>[];
    var order = 0;
    for (final d in widget.dossiers) {
      for (final op in d.operations) {
        final isIn = op.type == DossierOperationType.clientPayment;
        final isOut =
            op.type == DossierOperationType.providerPayment ||
            op.type == DossierOperationType.providerAdvance;
        if (!isIn && !isOut) continue;
        if (_journal != null && op.codeJournal != _journal!.code) continue;
        final date = _parseFrDate(op.date);
        if (date == null || !_inPeriod(date, _start, _end)) continue;
        final partner = isIn ? null : _partner(d, op);
        final mode = op.modePaiement.isEmpty ? '' : ' (${op.modePaiement})';
        final piece = isIn
            ? (d.estFacture ? d.factureClient.reference : d.numDossier)
            : op.categorie == 'Règlement Transitaire' &&
                  d.factureTransitaire.estValidee
            ? d.factureTransitaire.reference
            : d.numDossier;
        lines.add(
          _CashLine(
            date: date,
            piece: op.numeroCheque.isEmpty
                ? piece
                : '$piece • Chq ${op.numeroCheque}',
            compteGeneral: _treasury(op.codeJournal),
            compteTiers: isIn
                ? d.client.compteComptable
                : partner?.compteComptable ?? '',
            libelle: isIn
                ? 'Règlement ${d.client.nom}$mode'
                : op.type == DossierOperationType.providerAdvance
                ? 'Avance ${partner?.entreprise ?? 'prestataire'}$mode'
                : 'Règlement ${partner?.entreprise ?? 'prestataire'}$mode',
            recette: isIn ? op.montant : 0,
            depense: isOut ? op.montant : 0,
            order: order++,
          ),
        );
      }
      // Les frais de dossier n'ont pas de journal : ils figurent dans « Tous ».
      if (_journal == null) {
        for (final e in d.depenses) {
          final date = _parseFrDate(e.date);
          if (date == null || !_inPeriod(date, _start, _end)) continue;
          lines.add(
            _CashLine(
              date: date,
              piece: d.numDossier,
              compteGeneral: '',
              compteTiers: '',
              libelle:
                  'Dépense : ${e.titre}${e.categorie.isEmpty ? '' : ' (${e.categorie})'}',
              recette: 0,
              depense: e.montant,
              order: order++,
            ),
          );
        }
      }
    }
    lines.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.order.compareTo(b.order);
    });
    var balance = 0.0;
    for (final line in lines) {
      balance += line.recette - line.depense;
      line.solde = balance;
    }
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return lines;
    return lines
        .where(
          (l) => '${l.piece} ${l.compteGeneral} ${l.compteTiers} ${l.libelle}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
  }

  static final _columns = <ErpGridColumn<_CashLine>>[
    ErpGridColumn(
      label: 'Date',
      width: 95,
      value: (l) => _dateFormat.format(l.date),
      sortValue: (l) => l.date,
    ),
    ErpGridColumn(label: 'N° pièce', width: 190, value: (l) => l.piece),
    ErpGridColumn(
      label: 'Compte général',
      width: 130,
      value: (l) => l.compteGeneral,
    ),
    ErpGridColumn(
      label: 'Compte tiers',
      width: 130,
      value: (l) => l.compteTiers,
    ),
    ErpGridColumn(
      label: 'Libellé écriture',
      width: 320,
      value: (l) => l.libelle,
    ),
    ErpGridColumn(
      label: 'Recettes',
      width: 130,
      numeric: true,
      value: (l) => formatCurrency(l.recette),
      sortValue: (l) => l.recette,
      builder: (l) => Text(
        formatCurrency(l.recette),
        style: TextStyle(
          color: l.recette > 0 ? const Color(0xFF15803D) : _gridMuted,
        ),
      ),
    ),
    ErpGridColumn(
      label: 'Dépenses',
      width: 130,
      numeric: true,
      value: (l) => formatCurrency(l.depense),
      sortValue: (l) => l.depense,
      builder: (l) => Text(
        formatCurrency(l.depense),
        style: TextStyle(
          color: l.depense > 0 ? const Color(0xFFDC2626) : _gridMuted,
        ),
      ),
    ),
    ErpGridColumn(
      label: 'Solde',
      width: 140,
      numeric: true,
      value: (l) => formatCurrency(l.solde),
      sortValue: (l) => l.solde,
      builder: (l) => Text(
        formatCurrency(l.solde),
        style: const TextStyle(
          color: _gridPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final income = lines.fold<double>(0, (s, l) => s + l.recette);
    final outflow = lines.fold<double>(0, (s, l) => s + l.depense);
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
                spacing: 12,
                runSpacing: 10,
                children: [
                  const Text(
                    'Contrôle de caisse',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('generate-cash-control'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _gridPrimary,
                        ),
                        onPressed: () => _printCashControl(lines),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Imprimer / PDF'),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Exporter (Excel)',
                        onPressed: () => _exportGrid(
                          context,
                          baseName: 'controle_caisse',
                          columns: _columns,
                          rows: lines,
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
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<JournalCode?>(
                      key: const ValueKey('cash-journal-filter'),
                      isExpanded: true,
                      initialValue: _journal,
                      decoration: _inputDecoration(
                        'Journal',
                        icon: Icons.menu_book_rounded,
                      ),
                      items: [
                        const DropdownMenuItem<JournalCode?>(
                          value: null,
                          child: Text('Tous les journaux'),
                        ),
                        for (final journal in widget.journals)
                          DropdownMenuItem<JournalCode?>(
                            value: journal,
                            child: Text(
                              '${journal.code} • ${journal.intitule}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (journal) =>
                          setState(() => _journal = journal),
                    ),
                  ),
                  ErpDateFilter(
                    label: 'Période du',
                    value: _start,
                    onChanged: (value) => setState(() => _start = value),
                  ),
                  ErpDateFilter(
                    label: 'Au',
                    value: _end,
                    onChanged: (value) => setState(() => _end = value),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'Rechercher une pièce, un tiers…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ErpMetricTile(
                  label: 'Recettes',
                  value: _amountText(income),
                  color: const Color(0xFF15803D),
                  icon: Icons.south_west_rounded,
                ),
                ErpMetricTile(
                  label: 'Dépenses',
                  value: _amountText(outflow),
                  color: const Color(0xFFDC2626),
                  icon: Icons.north_east_rounded,
                ),
                ErpMetricTile(
                  label: 'Solde de la période',
                  value: _amountText(income - outflow),
                  color: _gridAccent,
                  icon: Icons.account_balance_wallet_rounded,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: math.max(440, constraints.maxHeight - 300),
              child: ErpGrid<_CashLine>(
                key: const ValueKey('cash-control-grid'),
                columns: _columns,
                rows: lines,
                rowId: (l) => '${l.order}',
                emptyIcon: Icons.account_balance_wallet_outlined,
                emptyText:
                    'Aucun mouvement de caisse pour cette période et ce journal.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printCashControl(List<_CashLine> lines) async {
    final logo = await _loadPdfLogo();
    const headerColor = PdfColor.fromInt(0xFF37474F);
    final journal = _journal == null
        ? 'Tous'
        : '${_journal!.code} — ${_journal!.intitule}';
    final period =
        'Période du ${_start == null ? '…' : _dateFormat.format(_start!)} au ${_end == null ? '…' : _dateFormat.format(_end!)}';
    final income = lines.fold<double>(0, (s, l) => s + l.recette);
    final outflow = lines.fold<double>(0, (s, l) => s + l.depense);
    final doc = pw.Document(
      title: 'Contrôle de caisse',
      author: 'Sylla Transit & Transport',
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
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
                    pw.Text(
                      'Journal : $journal',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Text(
                  'CONTRÔLE DE CAISSE',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(period, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
          ],
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
              'Date',
              'N° pièce',
              'Compte général',
              'Compte tiers',
              'Libellé écriture',
              'Recettes',
              'Dépenses',
              'Solde',
            ],
            data: [
              for (final l in lines)
                [
                  _dateFormat.format(l.date),
                  l.piece,
                  l.compteGeneral,
                  l.compteTiers,
                  l.libelle,
                  formatCurrency(l.recette),
                  formatCurrency(l.depense),
                  formatCurrency(l.solde),
                ],
              [
                '',
                '',
                '',
                '',
                'TOTAUX DE LA PÉRIODE',
                formatCurrency(income),
                formatCurrency(outflow),
                formatCurrency(income - outflow),
              ],
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            headerDecoration: const pw.BoxDecoration(color: headerColor),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(46),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(0.9),
              3: const pw.FlexColumnWidth(0.9),
              4: const pw.FlexColumnWidth(3),
              5: const pw.FlexColumnWidth(1),
              6: const pw.FlexColumnWidth(1),
              7: const pw.FlexColumnWidth(1.1),
            },
            cellAlignments: {
              for (var i = 5; i < 8; i++) i: pw.Alignment.centerRight,
            },
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      name: 'Controle de caisse',
      format: PdfPageFormat.a4.landscape,
      onLayout: (_) => doc.save(),
    );
  }
}
