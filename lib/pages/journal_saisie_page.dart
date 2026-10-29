part of '../main.dart';

// --- SAISIE D'UN JOURNAL (un code journal, un mois) ---
// Écritures générées par la mise à jour comptable et lignes saisies à la main
// par le comptable (jour, N° pièce, N° facture, référence, comptes, débit / crédit).

const _journalBlue = Color(0xFF1A237E);
const _journalOrange = Color(0xFFF57C00);

const _moisLongs = [
  'JANVIER',
  'FÉVRIER',
  'MARS',
  'AVRIL',
  'MAI',
  'JUIN',
  'JUILLET',
  'AOÛT',
  'SEPTEMBRE',
  'OCTOBRE',
  'NOVEMBRE',
  'DÉCEMBRE',
];

class JournalSaisiePage extends StatefulWidget {
  final String journal;
  final String intitule;
  final int year;
  final int month;

  const JournalSaisiePage({
    super.key,
    required this.journal,
    required this.intitule,
    required this.year,
    required this.month,
  });

  @override
  State<JournalSaisiePage> createState() => _JournalSaisiePageState();
}

class _JournalSaisiePageState extends State<JournalSaisiePage> {
  List<EcritureLigne>? _lines;
  String? _error;
  bool _saving = false;
  int _formVersion = 0;

  late final _jour = TextEditingController(text: '${_jourParDefaut()}');
  final _piece = TextEditingController();
  final _facture = TextEditingController();
  final _reference = TextEditingController();
  final _libelle = TextEditingController();
  final _debit = TextEditingController();
  final _credit = TextEditingController();
  PlanAccount? _compte;
  _Tiers? _tiers;

  String get _moisCle =>
      '${widget.year}-${widget.month.toString().padLeft(2, '0')}';
  int get _joursDuMois => DateUtils.getDaysInMonth(widget.year, widget.month);

  int _jourParDefaut() {
    final now = DateTime.now();
    return now.year == widget.year && now.month == widget.month ? now.day : 1;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _jour,
      _piece,
      _facture,
      _reference,
      _libelle,
      _debit,
      _credit,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lines = await erpBackend.ecritures(widget.journal, _moisCle);
      if (mounted) {
        setState(() {
          _lines = lines;
          _error = null;
        });
      }
    } on ErpBackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  // Clients et prestataires, avec leur compte.
  List<_Tiers> get _tousLesTiers => [
    for (final c in _clients) _Tiers(c.id, c.nom, c.compteComptable),
    for (final p in _prestataires)
      _Tiers(p.id, p.entreprise, p.compteComptable),
  ]..sort((a, b) => a.nom.compareTo(b.nom));

  static String _jourDe(EcritureLigne l) => l.date.split('/').first;

  List<ErpGridColumn<EcritureLigne>> get _columns => [
    ErpGridColumn(
      label: 'Jour',
      width: 60,
      value: _jourDe,
      sortValue: (l) => int.tryParse(_jourDe(l)) ?? 0,
    ),
    ErpGridColumn(label: 'N° Pièce', width: 150, value: (l) => l.piece),
    ErpGridColumn(
      label: 'N° Facture',
      width: 130,
      value: (l) => l.numeroFacture,
    ),
    ErpGridColumn(label: 'Référence', width: 130, value: (l) => l.reference),
    ErpGridColumn(label: 'Compte Gén.', width: 120, value: (l) => l.compte),
    ErpGridColumn(
      label: 'Compte Tiers',
      width: 180,
      value: (l) => l.tiers,
      builder: (l) => Text(
        l.tiers,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF3949AB),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    ErpGridColumn(
      label: 'Libellé écriture',
      width: 400,
      value: (l) => l.libelleLigne.isEmpty ? l.libelle : l.libelleLigne,
      builder: (l) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.libelleLigne.isEmpty ? l.libelle : l.libelleLigne,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (l.auteur.isNotEmpty)
            Text(
              'Fait par: ${l.auteur}${l.estManuelle ? '' : ' (mise à jour comptable)'}',
              style: const TextStyle(
                color: _gridMuted,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    ),
    ErpGridColumn(
      label: 'Débit',
      width: 130,
      numeric: true,
      value: (l) => l.debit == 0 ? '' : formatCurrency(l.debit),
      sortValue: (l) => l.debit,
    ),
    ErpGridColumn(
      label: 'Crédit',
      width: 130,
      numeric: true,
      value: (l) => l.credit == 0 ? '' : formatCurrency(l.credit),
      sortValue: (l) => l.credit,
    ),
    ErpGridColumn(
      label: 'Actions',
      width: 80,
      value: (_) => '',
      builder: (l) => l.estManuelle
          ? IconButton(
              key: ValueKey('journal-delete-${l.ligne}'),
              tooltip: 'Supprimer la ligne',
              icon: const Icon(Icons.delete_rounded, color: Colors.red),
              onPressed: () => _supprimer(l),
            )
          : const Tooltip(
              message:
                  'Écriture de la mise à jour comptable : corrigez le document d’origine.',
              child: Icon(Icons.lock_outline_rounded, color: _gridMuted),
            ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final lines = _lines ?? const <EcritureLigne>[];
    final debit = lines.fold<double>(0, (s, l) => s + l.debit);
    final credit = lines.fold<double>(0, (s, l) => s + l.credit);
    final ecart = debit - credit;
    final equilibre = ecart.abs() < 0.5;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _journalBlue,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.intitule.isEmpty
                  ? widget.journal
                  : widget.intitule.toUpperCase(),
              style: const TextStyle(fontSize: 19),
            ),
            Text(
              '${_moisLongs[widget.month - 1]} ${widget.year} • ${widget.journal}',
              style: const TextStyle(fontSize: 12.5, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _load,
            icon: const Icon(Icons.sync_rounded),
          ),
          IconButton(
            tooltip: 'Imprimer',
            onPressed: lines.isEmpty ? null : () => _print(lines),
            icon: const Icon(Icons.print_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFFE3F2FD),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                _total('TOTAL DÉBIT', debit, const Color(0xFF1E88E5)),
                _total('TOTAL CRÉDIT', credit, _journalOrange),
                _total(
                  equilibre ? 'ÉQUILIBRÉ' : 'ÉCART',
                  ecart.abs(),
                  equilibre ? const Color(0xFF2E7D32) : Colors.red,
                ),
              ],
            ),
          ),
          _saisie(),
          Expanded(
            child: _lines == null && _error == null
                ? const Center(child: CircularProgressIndicator())
                : ErpGrid<EcritureLigne>(
                    key: const ValueKey('journal-lines-grid'),
                    columns: _columns,
                    rows: lines,
                    rowId: (l) => '${l.ecriture}-${l.ligne}-${l.compte}',
                    rowHeight: 56,
                    emptyText:
                        _error ??
                        'Aucune écriture : saisissez une ligne ci-dessus.',
                  ),
          ),
          Container(
            color: const Color(0xFFF1F5FB),
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 20,
              runSpacing: 10,
              children: [
                Container(
                  key: const ValueKey('journal-balance'),
                  constraints: const BoxConstraints(minWidth: 320),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBDEFB)),
                  ),
                  child: Text(
                    equilibre
                        ? 'Journal équilibré'
                        : 'Écart de ${formatCurrency(ecart.abs())} à équilibrer (${ecart > 0 ? 'débit' : 'crédit'} supérieur)',
                    style: TextStyle(
                      color: equilibre ? const Color(0xFF2E7D32) : Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Totaux journal',
                          style: TextStyle(color: _gridMuted),
                        ),
                        Text(
                          'Solde à équilibrer',
                          style: TextStyle(color: _gridMuted),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    _footerTotal('Débit', debit, const Color(0xFF1E88E5)),
                    const SizedBox(width: 24),
                    _footerTotal('Crédit', credit, _journalOrange),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _total(String label, double value, Color color) => Expanded(
    child: Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _gridMuted)),
        Text(
          formatCurrency(value),
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _footerTotal(String label, double value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(
        formatCurrency(value),
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  InputDecoration _field(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
  );

  // Ligne de saisie, sur fond bleu.
  Widget _saisie() => Container(
    color: const Color(0xFF283593),
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 60,
          child: TextField(
            key: const ValueKey('journal-jour'),
            controller: _jour,
            keyboardType: TextInputType.number,
            decoration: _field('Jour'),
          ),
        ),
        SizedBox(
          width: 130,
          child: TextField(
            key: const ValueKey('journal-piece'),
            controller: _piece,
            decoration: _field('N° Pièce'),
          ),
        ),
        SizedBox(
          width: 130,
          child: TextField(
            key: const ValueKey('journal-facture'),
            controller: _facture,
            decoration: _field('N° Facture'),
          ),
        ),
        SizedBox(
          width: 130,
          child: TextField(
            key: const ValueKey('journal-reference'),
            controller: _reference,
            decoration: _field('Référence'),
          ),
        ),
        Container(
          width: 220,
          color: Colors.white,
          child: SearchableDropdownFormField<PlanAccount>(
            key: ValueKey('journal-compte-$_formVersion'),
            options: [..._planAccounts]
              ..sort((a, b) => a.code.compareTo(b.code)),
            value: _compte,
            label: 'Compte Gén.',
            emptyText: 'Aucun compte',
            required: false,
            displayString: (a) => '${a.code} ${a.libelle}',
            onChanged: (a) {
              if (a != null) setState(() => _compte = a);
            },
          ),
        ),
        Container(
          width: 220,
          color: Colors.white,
          child: SearchableDropdownFormField<_Tiers>(
            key: ValueKey('journal-tiers-$_formVersion'),
            options: _tousLesTiers,
            value: _tiers,
            label: 'Compte Tiers',
            emptyText: 'Aucun tiers',
            required: false,
            displayString: (t) => t.label,
            onChanged: (t) {
              if (t == null) return;
              setState(() {
                _tiers = t;
                // Le compte du tiers devient le compte général de la ligne.
                final account = _planAccounts
                    .where((a) => a.code == t.compte)
                    .firstOrNull;
                if (account != null) {
                  _compte = account;
                  _formVersion++;
                }
              });
            },
          ),
        ),
        SizedBox(
          width: 320,
          child: TextField(
            key: const ValueKey('journal-libelle'),
            controller: _libelle,
            decoration: _field('Libellé écriture'),
          ),
        ),
        SizedBox(
          width: 130,
          child: TextField(
            key: const ValueKey('journal-debit'),
            controller: _debit,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            decoration: _field('Débit'),
          ),
        ),
        SizedBox(
          width: 130,
          child: TextField(
            key: const ValueKey('journal-credit'),
            controller: _credit,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            decoration: _field('Crédit'),
          ),
        ),
        FilledButton.icon(
          key: const ValueKey('journal-add'),
          style: FilledButton.styleFrom(
            backgroundColor: _journalOrange,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          ),
          onPressed: _saving ? null : _ajouter,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Ajouter'),
        ),
      ],
    ),
  );

  Future<void> _ajouter() async {
    final jour = int.tryParse(_jour.text.trim());
    final debit = _parseMontant(_debit.text) ?? 0;
    final credit = _parseMontant(_credit.text) ?? 0;
    String? erreur;
    if (jour == null || jour < 1 || jour > _joursDuMois) {
      erreur = 'Le jour doit être compris entre 1 et $_joursDuMois.';
    } else if (_piece.text.trim().isEmpty) {
      erreur = 'Saisissez le N° de pièce.';
    } else if (_compte == null) {
      erreur = 'Choisissez le compte général.';
    } else if (_libelle.text.trim().isEmpty) {
      erreur = 'Saisissez le libellé de l’écriture.';
    } else if ((debit > 0) == (credit > 0)) {
      erreur = 'Saisissez un montant au débit ou au crédit (pas les deux).';
    }
    if (erreur != null) {
      await _showInfoAlert(context, title: 'Ligne incomplète', message: erreur);
      return;
    }
    final date =
        '${jour!.toString().padLeft(2, '0')}/${widget.month.toString().padLeft(2, '0')}/${widget.year}';
    setState(() => _saving = true);
    EcritureLigne? saved;
    final ok = await _persist(context, () async {
      saved = await erpBackend.ajouterLigneEcriture(
        journal: widget.journal,
        date: date,
        piece: _piece.text.trim(),
        numeroFacture: _facture.text.trim(),
        reference: _reference.text.trim(),
        compte: _compte!.code,
        tiers: _tiers?.nom ?? '',
        libelle: _libelle.text.trim(),
        debit: debit,
        credit: credit,
      );
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) return;
      _lines = [...?_lines, saved!];
      // La contrepartie reste sur la même pièce : on garde jour, pièce,
      // facture, référence et libellé ; on vide comptes et montants.
      _debit.clear();
      _credit.clear();
      _compte = null;
      _tiers = null;
      _formVersion++;
    });
  }

  Future<void> _supprimer(EcritureLigne ligne) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette ligne ?'),
        content: Text(
          '${ligne.piece} • ${ligne.compte} • ${formatCurrency(ligne.debit + ligne.credit)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('journal-delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await _persist(
      context,
      () => erpBackend.supprimerLigneEcriture(ligne),
    )) {
      return;
    }
    if (mounted) {
      setState(() => _lines = [...?_lines]..remove(ligne));
    }
  }

  Future<void> _print(List<EcritureLigne> lines) async {
    final logo = await _loadPdfLogo();
    final debit = lines.fold<double>(0, (s, l) => s + l.debit);
    final credit = lines.fold<double>(0, (s, l) => s + l.credit);
    final title =
        '${widget.intitule.toUpperCase()} • ${_moisLongs[widget.month - 1]} ${widget.year}';
    final doc = pw.Document(title: title, author: 'Sylla Transit & Transport');
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
                ],
              ),
              pw.Spacer(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'JOURNAL ${widget.journal}',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(title, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
        build: (context) => [
          _pdfTable(
            [
              'Jour',
              'N° pièce',
              'N° facture',
              'Référence',
              'Compte',
              'Tiers',
              'Libellé',
              'Débit',
              'Crédit',
            ],
            [
              for (final l in lines)
                [
                  _jourDe(l),
                  l.piece,
                  l.numeroFacture,
                  l.reference,
                  l.compte,
                  l.tiers,
                  (l.libelleLigne.isEmpty ? l.libelle : l.libelleLigne)
                      .replaceAll('•', '-'),
                  l.debit == 0 ? '' : formatCurrency(l.debit),
                  l.credit == 0 ? '' : formatCurrency(l.credit),
                ],
              [
                '',
                '',
                '',
                '',
                '',
                '',
                'TOTAUX JOURNAL',
                formatCurrency(debit),
                formatCurrency(credit),
              ],
            ],
            numericColumns: {7, 8},
            fontSize: 8.5,
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      name: 'Journal ${widget.journal} $_moisCle',
      format: PdfPageFormat.a4.landscape,
      onLayout: (_) => doc.save(),
    );
  }
}
