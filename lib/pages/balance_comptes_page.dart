part of '../main.dart';

// --- BALANCE DES COMPTES (balance générale) ---

class BalanceComptesPage extends StatefulWidget {
  final List<PlanAccount> comptes;
  final List<JournalCode> journals;

  const BalanceComptesPage({
    super.key,
    required this.comptes,
    required this.journals,
  });

  @override
  State<BalanceComptesPage> createState() => _BalanceComptesPageState();
}

class _BalanceComptesPageState extends State<BalanceComptesPage> {
  DateTime? _from = DateTime(DateTime.now().year, 1, 1);
  DateTime? _to = DateTime.now();
  String? _accountFrom;
  String? _accountTo;
  String? _journalFrom;
  String? _journalTo;
  List<BalanceLigne>? _rows;
  bool _loading = false;

  static final _fr = DateFormat('dd/MM/yyyy');

  List<PlanAccount> get _accounts =>
      [...widget.comptes]..sort((a, b) => a.code.compareTo(b.code));
  List<JournalCode> get _journals =>
      [...widget.journals]..sort((a, b) => a.code.compareTo(b.code));

  static final _columns = <ErpGridColumn<BalanceLigne>>[
    ErpGridColumn(
      label: 'Numéro de compte',
      width: 150,
      value: (r) => r.compte,
    ),
    ErpGridColumn(
      label: 'Intitulé des comptes',
      width: 320,
      value: (r) => r.intitule,
    ),
    ErpGridColumn(
      label: 'Mouvements débit',
      width: 160,
      numeric: true,
      value: (r) => formatCurrency(r.debit),
      sortValue: (r) => r.debit,
    ),
    ErpGridColumn(
      label: 'Mouvements crédit',
      width: 160,
      numeric: true,
      value: (r) => formatCurrency(r.credit),
      sortValue: (r) => r.credit,
    ),
    ErpGridColumn(
      label: 'Solde',
      width: 160,
      numeric: true,
      value: (r) => formatCurrency(r.solde),
      sortValue: (r) => r.solde,
      builder: (r) => Text(
        formatCurrency(r.solde),
        style: TextStyle(
          color: r.solde < 0 ? const Color(0xFFDC2626) : _gridPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  ];

  Future<List<BalanceLigne>?> _load() async {
    if (_from == null || _to == null) {
      await _showInfoAlert(
        context,
        title: 'Période requise',
        message: 'Indiquez la période d’écriture (du … au …).',
      );
      return null;
    }
    setState(() => _loading = true);
    try {
      final rows = await erpBackend.balanceComptes(
        du: _fr.format(_from!),
        au: _fr.format(_to!),
        compteDu: _accountFrom,
        compteAu: _accountTo,
        journalDu: _journalFrom,
        journalAu: _journalTo,
      );
      if (mounted) setState(() => _rows = rows);
      return rows;
    } on ErpBackendException catch (error) {
      if (mounted) {
        await _showInfoAlert(
          context,
          title: 'Balance impossible',
          message: error.message,
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows ?? const <BalanceLigne>[];
    final debit = rows.fold<double>(0, (s, r) => s + r.debit);
    final credit = rows.fold<double>(0, (s, r) => s + r.credit);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: ListView(
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
            child: const Row(
              children: [
                Icon(Icons.balance_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Balance des comptes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _buildForm(),
            ),
          ),
          if (_rows != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ErpMetricTile(
                  label: 'Total débit',
                  value: _amountText(debit),
                  color: _gridAccent,
                  icon: Icons.south_west_rounded,
                ),
                ErpMetricTile(
                  label: 'Total crédit',
                  value: _amountText(credit),
                  color: const Color(0xFF15803D),
                  icon: Icons.north_east_rounded,
                ),
                ErpMetricTile(
                  label: 'Net',
                  value: _amountText(debit - credit),
                  color: (debit - credit).abs() < 0.5
                      ? const Color(0xFF15803D)
                      : const Color(0xFFDC2626),
                  icon: Icons.balance_rounded,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 520,
              child: ErpGrid<BalanceLigne>(
                key: const ValueKey('trial-balance-grid'),
                columns: _columns,
                rows: rows,
                rowId: (r) => r.compte,
                emptyIcon: Icons.balance_outlined,
                emptyText:
                    'Aucune écriture sur cette période. Lancez la mise à jour comptable dans Saisie des journaux.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForm() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _gridBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.account_balance_rounded,
          size: 52,
          color: _gridPrimary,
        ),
        const SizedBox(height: 10),
        const Text(
          'Génération de la Balance Générale',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _gridText,
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        _label('PÉRIODE D’ÉCRITURE'),
        _pair(
          _FormDateField(
            label: 'Du',
            value: _from,
            onChanged: (d) => setState(() => _from = d),
          ),
          _FormDateField(
            label: 'Au',
            value: _to,
            onChanged: (d) => setState(() => _to = d),
          ),
        ),
        const SizedBox(height: 18),
        _label('INTERVALLE DE COMPTES'),
        _pair(
          _accountField(
            'Du compte…',
            _accountFrom,
            (v) => _accountFrom = v,
            'balance-account-from',
          ),
          _accountField(
            'Au compte…',
            _accountTo,
            (v) => _accountTo = v,
            'balance-account-to',
          ),
        ),
        const SizedBox(height: 18),
        _label('INTERVALLE DE JOURNAUX'),
        _pair(
          _journalField('Du journal…', _journalFrom, (v) => _journalFrom = v),
          _journalField('Au journal…', _journalTo, (v) => _journalTo = v),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('trial-balance-pdf'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          onPressed: _loading
              ? null
              : () async {
                  final rows = await _load();
                  if (rows != null) await _printTrialBalance(rows);
                },
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('TIRER LA BALANCE (PDF)'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('trial-balance-show'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.visibility_outlined),
                label: const Text('AFFICHER À L’ÉCRAN'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _loading
                    ? null
                    : () async {
                        final rows = await _load();
                        if (rows == null || !mounted) return;
                        await _exportGrid(
                          context,
                          baseName: 'balance_des_comptes',
                          columns: _columns,
                          rows: rows,
                        );
                      },
                icon: const Icon(Icons.table_chart_rounded),
                label: const Text('EXPORTER VERS EXCEL'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _gridMuted,
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _pair(Widget left, Widget right) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 480
        ? Column(children: [left, const SizedBox(height: 10), right])
        : Row(
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              Expanded(child: right),
            ],
          ),
  );

  Widget _accountField(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
    String key,
  ) => DropdownButtonFormField<String?>(
    key: ValueKey(key),
    isExpanded: true,
    initialValue: value,
    decoration: _inputDecoration(label),
    items: [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Tous les comptes'),
      ),
      for (final a in _accounts)
        DropdownMenuItem<String?>(
          value: a.code,
          child: Text(
            '${a.code} — ${a.libelle}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (v) => setState(() => onChanged(v)),
  );

  Widget _journalField(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String?>(
    isExpanded: true,
    initialValue: value,
    decoration: _inputDecoration(label),
    items: [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Tous les journaux'),
      ),
      for (final j in _journals)
        DropdownMenuItem<String?>(
          value: j.code,
          child: Text(
            '${j.code} — ${j.intitule}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (v) => setState(() => onChanged(v)),
  );

  Future<void> _printTrialBalance(List<BalanceLigne> rows) async {
    final logo = await _loadPdfLogo();
    const headerColor = PdfColor.fromInt(0xFF37474F);
    final debit = rows.fold<double>(0, (s, r) => s + r.debit);
    final credit = rows.fold<double>(0, (s, r) => s + r.credit);
    final period =
        'Période comptable du ${_fr.format(_from!)} au ${_fr.format(_to!)}';
    final doc = pw.Document(
      title: 'Balance des comptes',
      author: 'Sylla Transit & Transport',
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 20),
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
                    pw.Text(period, style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Spacer(),
                pw.Text(
                  'BALANCE DES COMPTES',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Impression provisoire • Tirée le ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9),
            ),
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
              'Numéro de compte',
              'Intitulé des comptes',
              'Mouvements Débit',
              'Mouvements Crédit',
              'Solde',
            ],
            data: [
              for (final r in rows)
                [
                  r.compte,
                  r.intitule,
                  formatCurrency(r.debit),
                  formatCurrency(r.credit),
                  formatCurrency(r.solde),
                ],
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 8.5,
            ),
            headerDecoration: const pw.BoxDecoration(color: headerColor),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 5,
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(80),
              1: const pw.FlexColumnWidth(3.5),
              2: const pw.FlexColumnWidth(1.3),
              3: const pw.FlexColumnWidth(1.3),
              4: const pw.FlexColumnWidth(1.3),
            },
            cellAlignments: {
              for (var i = 2; i < 5; i++) i: pw.Alignment.centerRight,
            },
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF5F5F5),
              border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'TOTAUX DE LA BALANCE',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Spacer(),
                pw.Text(
                  'DÉBIT : ${formatCurrency(debit)} F  |  CRÉDIT : ${formatCurrency(credit)} F  |  NET : ${formatCurrency(debit - credit)} F',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      name: 'Balance des comptes',
      format: PdfPageFormat.a4.landscape,
      onLayout: (_) => doc.save(),
    );
  }
}
