part of '../main.dart';

// --- RÈGLEMENTS : clients, fournisseurs, transitaires et transporteurs ---
// Un tiers est choisi une seule fois (sans doublon) ; ses factures (échéances)
// sont listées avec leur solde et un règlement se répartit entre elles. Côté
// clients, la comptabilité impute aussi les encaissements pointés par la caisse.

// Un compte tiers : client ou prestataire.
class _Tiers {
  final String id;
  final String nom;
  final String compte;

  const _Tiers(this.id, this.nom, this.compte);

  String get label => compte.isEmpty ? nom : '$compte  $nom';

  @override
  bool operator ==(Object other) => other is _Tiers && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// Une facture à régler du tiers.
class _Echeance {
  final String id;
  final String date;
  final String piece;
  final String detail;
  final double aPayer;
  final double regle;
  // Client : dossier de la facture (imputation des encaissements de caisse).
  final TransitDossier? dossier;
  final FactureTransitaire? factureTransitaire;
  final FactureTransporteur? factureTransporteur;

  const _Echeance({
    required this.id,
    required this.date,
    required this.piece,
    this.detail = '',
    required this.aPayer,
    required this.regle,
    this.dossier,
    this.factureTransitaire,
    this.factureTransporteur,
  });

  double get solde => aPayer - regle;
}

// Un règlement déjà enregistré pour le tiers.
class _ReglementLigne {
  final String date;
  final String piece;
  final String libelle;
  final String mode;
  final double montant;
  final String journal;
  final String etat;
  final Future<bool> Function(BuildContext context)? supprimer;

  const _ReglementLigne({
    required this.date,
    required this.piece,
    required this.libelle,
    required this.mode,
    required this.montant,
    required this.journal,
    this.etat = '',
    this.supprimer,
  });
}

// Saisie validée dans la sélection des échéances.
typedef _Repartition = ({
  Map<String, double> montants,
  String journal,
  String mode,
});

class ReglementsTiersPage extends StatefulWidget {
  final SettlementKind kind;
  // Ouvert dans un onglet de l'ERP (sans flèche de retour).
  final bool embedded;

  const ReglementsTiersPage({
    super.key,
    required this.kind,
    this.embedded = false,
  });

  @override
  State<ReglementsTiersPage> createState() => _ReglementsTiersPageState();
}

class _ReglementsTiersPageState extends State<ReglementsTiersPage> {
  _Tiers? _tiers;
  int _pickerVersion = 0;
  String? _journal;
  String _mode = 'Espèces';
  DateTime _date = DateTime.now();
  final _piece = TextEditingController();
  final _label = TextEditingController();
  final _amount = TextEditingController();

  bool get _isClient => widget.kind == SettlementKind.client;

  String get _title => switch (widget.kind) {
    SettlementKind.client => 'Saisie des règlements clients',
    SettlementKind.supplier => 'Saisie des règlements fournisseurs',
    SettlementKind.forwarder => 'Saisie des règlements transitaires',
    SettlementKind.carrier => 'Saisie des règlements transporteurs',
  };

  String get _categorie => switch (widget.kind) {
    SettlementKind.client => 'Règlement Client',
    SettlementKind.supplier => 'Règlement Fournisseur',
    SettlementKind.forwarder => 'Règlement Transitaire',
    SettlementKind.carrier => 'Règlement Transporteur',
  };

  @override
  void initState() {
    super.initState();
    final principale = _caisseParametres.principale;
    if (_isClient && _journalCodes.any((j) => j.code == principale)) {
      _journal = principale;
    }
  }

  @override
  void dispose() {
    _piece.dispose();
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  Prestataire? _prestataire(String id) =>
      _prestataires.where((p) => p.id == id).firstOrNull;

  _Tiers _tiersPrestataire(Prestataire p) =>
      _Tiers(p.id, p.entreprise, p.compteComptable);

  // Tiers ayant au moins une facture ou un règlement, chacun une seule fois.
  List<_Tiers> get _tousLesTiers {
    final tiers = <String, _Tiers>{};
    switch (widget.kind) {
      case SettlementKind.client:
        for (final d in _dossiers) {
          if (d.totalFacturesClient <= 0 && d.totalReglementsClient <= 0) {
            continue;
          }
          tiers[d.client.id] = _Tiers(
            d.client.id,
            d.client.nom,
            d.client.compteComptable,
          );
        }
      case SettlementKind.supplier:
        for (final d in _dossiers) {
          final p = d.prestataire;
          if (p != null) tiers[p.id] = _tiersPrestataire(p);
        }
      case SettlementKind.forwarder:
        for (final f in _facturesTransitaire) {
          final p = _prestataire(f.transitaireId);
          if (p != null) tiers[p.id] = _tiersPrestataire(p);
        }
      case SettlementKind.carrier:
        for (final f in _facturesTransporteur) {
          final p = _prestataire(f.transporteurId);
          if (p != null) tiers[p.id] = _tiersPrestataire(p);
        }
    }
    return tiers.values.toList()..sort((a, b) => a.nom.compareTo(b.nom));
  }

  // Ajustement des soldes : l'encaissement en cours d'imputation est retiré.
  List<_Echeance> _echeances(_Tiers tiers, {CaisseMouvement? enImputation}) {
    final rows = <_Echeance>[];
    switch (widget.kind) {
      case SettlementKind.client:
        for (final d in _dossiers.where((d) => d.client.id == tiers.id)) {
          if (d.totalFacturesClient <= 0) continue;
          final retour = enImputation != null && enImputation.dossierId == d.id
              ? enImputation.montant
              : 0;
          rows.add(
            _Echeance(
              id: d.id,
              date: d.factureClient.dateEmission,
              piece: d.factureClient.reference,
              detail: 'Dossier ${d.numDossier} • BL ${d.numBL}',
              aPayer: d.totalFacturesClient,
              regle: d.totalReglementsClient - retour,
              dossier: d,
            ),
          );
        }
      case SettlementKind.supplier:
        for (final d in _dossiers.where((d) => d.prestataire?.id == tiers.id)) {
          final f = d.facturePrestataire;
          if (!f.estValidee || f.montant <= 0) continue;
          rows.add(
            _Echeance(
              id: d.id,
              date: f.dateEmission,
              piece: f.reference,
              detail: 'Dossier ${d.numDossier}',
              aPayer: f.montant,
              regle: d.totalRegleDe(DossierInvoiceKind.provider),
              dossier: d,
            ),
          );
        }
      case SettlementKind.forwarder:
        for (final f in _facturesTransitaire.where(
          (f) => f.transitaireId == tiers.id,
        )) {
          rows.add(
            _Echeance(
              id: f.id,
              date: f.dateEmission,
              piece: f.reference,
              detail: '${f.lignes.length} ligne(s)',
              aPayer: f.montant,
              regle: f.totalRegle,
              factureTransitaire: f,
            ),
          );
        }
      case SettlementKind.carrier:
        for (final f in _facturesTransporteur.where(
          (f) => f.transporteurId == tiers.id,
        )) {
          rows.add(
            _Echeance(
              id: f.id,
              date: f.dateEmission,
              piece: f.reference,
              detail: f.plaque,
              aPayer: f.netAPayer,
              regle: f.totalRegle,
              factureTransporteur: f,
            ),
          );
        }
    }
    rows.sort(
      (a, b) => (_parseFrDate(a.date) ?? DateTime(0)).compareTo(
        _parseFrDate(b.date) ?? DateTime(0),
      ),
    );
    return rows;
  }

  // Encaissements de la caisse principale pas encore imputés pour ce client.
  List<CaisseMouvement> _aImputer(_Tiers? tiers) => _caisseMouvements
      .where(
        (m) =>
            m.type == CaisseMouvement.encaissement &&
            !m.estImpute &&
            (tiers == null || _dossierById(m.dossierId)?.client.id == tiers.id),
      )
      .toList();

  bool _estAImputer(TransitDossier d, DossierOperation op) =>
      _caisseMouvements.any(
        (m) =>
            m.type == CaisseMouvement.encaissement &&
            !m.estImpute &&
            m.dossierId == d.id &&
            m.operationUid == op.id,
      );

  bool _vientDeLaCaisse(DossierOperation op) =>
      _caisseMouvements.any((m) => op.id.startsWith(m.id));

  List<_ReglementLigne> _reglements(_Tiers tiers) {
    final rows = <(DateTime, _ReglementLigne)>[];
    void addOp(TransitDossier d, DossierOperation op) {
      final parts = op.titre.split(' • ');
      final caisse = _vientDeLaCaisse(op);
      rows.add((
        _parseFrDate(op.date) ?? DateTime(0),
        _ReglementLigne(
          date: op.date.split(' ').first,
          piece: parts.first,
          libelle: [
            if (parts.length > 1) parts[1] else op.categorie,
            d.numDossier,
          ].join(' • '),
          mode: op.modePaiement.isNotEmpty
              ? op.modePaiement
              : (parts.length > 2 ? parts[2] : ''),
          montant: op.montant,
          journal: op.codeJournal,
          etat: !_isClient
              ? ''
              : _estAImputer(d, op)
              ? 'À imputer'
              : 'Imputé',
          supprimer: caisse || d.estCloture
              ? null
              : (context) async {
                  d.operations.remove(op);
                  if (await _persist(
                    context,
                    () => erpBackend.saveDossier(d),
                  )) {
                    return true;
                  }
                  d.operations.add(op);
                  return false;
                },
        ),
      ));
    }

    void addReglement(
      String piece,
      ReglementFacture r,
      Future<void> Function() save,
      List<ReglementFacture> list,
    ) {
      rows.add((
        _parseFrDate(r.date) ?? DateTime(0),
        _ReglementLigne(
          date: r.date.split(' ').first,
          piece: piece,
          libelle: r.observations.isEmpty ? _categorie : r.observations,
          mode: r.modePaiement,
          montant: r.montant,
          journal: r.codeJournal,
          supprimer: (context) async {
            list.remove(r);
            if (await _persist(context, save)) return true;
            list.add(r);
            return false;
          },
        ),
      ));
    }

    switch (widget.kind) {
      case SettlementKind.client:
        for (final d in _dossiers.where((d) => d.client.id == tiers.id)) {
          for (final op in d.reglementsDe(DossierInvoiceKind.client)) {
            addOp(d, op);
          }
        }
      case SettlementKind.supplier:
        for (final d in _dossiers.where((d) => d.prestataire?.id == tiers.id)) {
          for (final op in d.reglementsDe(DossierInvoiceKind.provider)) {
            addOp(d, op);
          }
        }
      case SettlementKind.forwarder:
        for (final f in _facturesTransitaire.where(
          (f) => f.transitaireId == tiers.id,
        )) {
          for (final r in [...f.reglements]) {
            addReglement(
              f.reference,
              r,
              () => erpBackend.saveFactureTransitaire(f),
              f.reglements,
            );
          }
        }
      case SettlementKind.carrier:
        for (final f in _facturesTransporteur.where(
          (f) => f.transporteurId == tiers.id,
        )) {
          for (final r in [...f.reglements]) {
            addReglement(
              f.reference,
              r,
              () => erpBackend.saveFactureTransporteur(f),
              f.reglements,
            );
          }
        }
    }
    rows.sort((a, b) => b.$1.compareTo(a.$1));
    return rows.map((r) => r.$2).toList();
  }

  ({double du, double regle}) _totaux(_Tiers tiers) {
    final echeances = _echeances(tiers);
    return (
      du: echeances.fold(0, (s, e) => s + e.aPayer),
      regle: _reglements(tiers).fold(0, (s, r) => s + r.montant),
    );
  }

  static final _reglementColumns = <ErpGridColumn<_ReglementLigne>>[
    ErpGridColumn(label: 'Date', width: 105, value: (r) => r.date),
    ErpGridColumn(label: 'N° pièce', width: 190, value: (r) => r.piece),
    ErpGridColumn(label: 'Libellé', width: 280, value: (r) => r.libelle),
    ErpGridColumn(label: 'Mode règlement', width: 150, value: (r) => r.mode),
    ErpGridColumn(
      label: 'Montant',
      width: 140,
      numeric: true,
      value: (r) => formatCurrency(r.montant),
      sortValue: (r) => r.montant,
      builder: (r) => Text(
        formatCurrency(r.montant),
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    ErpGridColumn(label: 'Journal', width: 100, value: (r) => r.journal),
  ];

  @override
  Widget build(BuildContext context) {
    final tiers = _tiers;
    final all = _tousLesTiers;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(_title, style: const TextStyle(fontSize: 18)),
        backgroundColor: const Color(0xFF424247),
        foregroundColor: Colors.white,
        actions: [
          if (tiers != null)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => _print(tiers),
              icon: const Icon(Icons.print_rounded),
              label: const Text('Imprimer'),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 520,
                  child: SearchableDropdownFormField<_Tiers>(
                    key: ValueKey('reglement-tiers-$_pickerVersion'),
                    options: all,
                    value: tiers,
                    label: _isClient ? 'Compte client' : 'Compte fournisseur',
                    emptyText: 'Aucun tiers',
                    required: false,
                    displayString: (t) => t.label,
                    onChanged: (t) => setState(() => _tiers = t),
                  ),
                ),
                if (tiers != null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _tiers = null;
                      _pickerVersion++;
                    }),
                    icon: const Icon(Icons.clear_rounded),
                    label: const Text('Effacer'),
                  ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('reglement-journal'),
                    isExpanded: true,
                    initialValue: _journal,
                    decoration: _inputDecoration(
                      'Journal',
                      icon: Icons.menu_book_rounded,
                    ),
                    items: [
                      for (final j in _journalCodes)
                        DropdownMenuItem(
                          value: j.code,
                          child: Text(
                            '${j.code} • ${j.intitule}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _journal = v),
                  ),
                ),
              ],
            ),
          ),
          if (tiers != null) _saisie(tiers),
          Expanded(child: tiers == null ? _apercu(all) : _detail(tiers)),
          _footer(tiers),
        ],
      ),
    );
  }

  // Ligne de saisie d'un nouveau règlement (réparti ensuite sur les factures).
  Widget _saisie(_Tiers tiers) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton(
          onPressed: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (date != null && mounted) setState(() => _date = date);
          },
          child: Text(DateFormat('ddMMyy').format(_date)),
        ),
        SizedBox(
          width: 150,
          child: TextField(
            key: const ValueKey('reglement-piece'),
            controller: _piece,
            decoration: _inputDecoration('N° pièce'),
          ),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            key: const ValueKey('reglement-label'),
            controller: _label,
            decoration: _inputDecoration(
              'Libellé',
            ).copyWith(hintText: 'RÈGLEMENT ${tiers.nom}'),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _mode,
            decoration: _inputDecoration('Mode de règlement'),
            items: [
              for (final mode in _modesPaiement)
                DropdownMenuItem(value: mode, child: Text(mode)),
            ],
            onChanged: (v) => setState(() => _mode = v ?? _mode),
          ),
        ),
        SizedBox(
          width: 150,
          child: TextField(
            key: const ValueKey('reglement-amount'),
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration('Montant'),
          ),
        ),
        FilledButton(
          key: const ValueKey('reglement-save'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2E8B57),
          ),
          onPressed: () => _enregistrer(tiers),
          child: const Text('ENREGISTRER'),
        ),
      ],
    ),
  );

  static List<String> get _modesPaiement => {
    'Espèces',
    'Chèque',
    'Virement',
    ..._modesReglement.map((m) => m.intitule),
  }.toList();

  // Sans tiers choisi : soldes de tous les tiers.
  Widget _apercu(List<_Tiers> all) {
    final rows = [
      for (final t in all) (t, _totaux(t), _isClient ? _aImputer(t).length : 0),
    ];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: ErpGrid<(_Tiers, ({double du, double regle}), int)>(
        key: const ValueKey('reglement-soldes-grid'),
        columns: [
          ErpGridColumn(label: 'Compte', width: 130, value: (r) => r.$1.compte),
          ErpGridColumn(label: 'Tiers', width: 260, value: (r) => r.$1.nom),
          ErpGridColumn(
            label: 'Total dû',
            width: 150,
            numeric: true,
            value: (r) => formatCurrency(r.$2.du),
            sortValue: (r) => r.$2.du,
          ),
          ErpGridColumn(
            label: 'Total réglé',
            width: 150,
            numeric: true,
            value: (r) => formatCurrency(r.$2.regle),
            sortValue: (r) => r.$2.regle,
          ),
          ErpGridColumn(
            label: 'Solde',
            width: 150,
            numeric: true,
            value: (r) => formatCurrency(r.$2.du - r.$2.regle),
            sortValue: (r) => r.$2.du - r.$2.regle,
            builder: (r) => Text(
              formatCurrency(r.$2.du - r.$2.regle),
              style: TextStyle(
                color: r.$2.du - r.$2.regle > 0
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF15803D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_isClient)
            ErpGridColumn(
              label: 'À imputer',
              width: 110,
              numeric: true,
              value: (r) => r.$3 == 0 ? '' : '${r.$3}',
            ),
        ],
        rows: rows,
        rowId: (r) => r.$1.id,
        filterable: true,
        onSelect: (r) => setState(() {
          _tiers = r.$1;
          _pickerVersion++;
        }),
        emptyText: 'Aucun tiers avec des factures.',
      ),
    );
  }

  Widget _detail(_Tiers tiers) {
    final aImputer = _isClient ? _aImputer(tiers) : const <CaisseMouvement>[];
    final reglements = _reglements(tiers);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (aImputer.isNotEmpty) ...[
          Container(
            key: const ValueKey('reglement-a-imputer'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Encaissements de la caisse à imputer',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC2410C),
                  ),
                ),
                const SizedBox(height: 6),
                for (final m in aImputer)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.point_of_sale_rounded),
                    title: Text(
                      '${m.recu} du ${m.date} • ${_amountText(m.montant)}',
                    ),
                    subtitle: Text(
                      'Pointé « ${m.statutReglement} » sur ${_dossierById(m.dossierId)?.factureClient.reference ?? ''} par ${m.auteur}${m.modePaiement.isEmpty ? '' : ' • ${m.modePaiement}'}',
                    ),
                    trailing: FilledButton(
                      key: ValueKey('imputer-${m.id}'),
                      onPressed: () => _imputer(tiers, m),
                      child: const Text('Imputer'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 420,
          child: ErpGrid<_ReglementLigne>(
            key: const ValueKey('reglements-grid'),
            columns: [
              ..._reglementColumns,
              if (_isClient)
                ErpGridColumn(
                  label: 'État',
                  width: 110,
                  value: (r) => r.etat,
                  builder: (r) => Text(
                    r.etat,
                    style: TextStyle(
                      color: r.etat == 'À imputer'
                          ? const Color(0xFFC2410C)
                          : const Color(0xFF15803D),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ErpGridColumn(
                label: 'Action',
                width: 80,
                value: (_) => '',
                builder: (r) => r.supprimer == null
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: 'Supprimer le règlement',
                        icon: const Icon(
                          Icons.delete_rounded,
                          color: Color(0xFFDC2626),
                        ),
                        onPressed: () => _supprimer(r),
                      ),
              ),
            ],
            rows: reglements,
            rowId: (r) => '${r.piece}|${r.date}|${r.montant}|${r.libelle}',
            emptyText: 'Aucun règlement pour ce tiers.',
          ),
        ),
      ],
    );
  }

  Widget _footer(_Tiers? tiers) {
    final totaux = tiers == null ? (du: 0.0, regle: 0.0) : _totaux(tiers);
    Widget total(String label, double value, Color color, String key) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: _gridMuted, fontSize: 12)),
        Text(
          formatCurrency(value),
          key: ValueKey(key),
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
    return Container(
      color: const Color(0xFFF0FDF4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 40,
        runSpacing: 8,
        children: [
          total(
            'Total réglé',
            totaux.regle,
            const Color(0xFF15803D),
            'total-regle',
          ),
          total('Total dû', totaux.du, const Color(0xFF15803D), 'total-du'),
          total(
            _isClient ? 'Solde client' : 'Solde fournisseur',
            totaux.du - totaux.regle,
            const Color(0xFFDC2626),
            'total-solde',
          ),
        ],
      ),
    );
  }

  Future<void> _supprimer(_ReglementLigne r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce règlement ?'),
        content: Text('${r.piece} du ${r.date} • ${_amountText(r.montant)}'),
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
    if (ok != true || !mounted) return;
    await r.supprimer!(context);
    if (mounted) setState(() {});
  }

  Future<_Repartition?> _selectionEcheances(
    _Tiers tiers, {
    required double montant,
    required bool montantFixe,
    CaisseMouvement? enImputation,
    String? mode,
  }) => showDialog<_Repartition>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EcheancesDialog(
      echeances: _echeances(tiers, enImputation: enImputation),
      montant: montant,
      montantFixe: montantFixe,
      journal: _journal,
      mode: mode ?? _mode,
      modes: _modesPaiement,
    ),
  );

  Future<void> _enregistrer(_Tiers tiers) async {
    final montant = _parseMontant(_amount.text) ?? 0;
    if (montant <= 0) {
      await _showInfoAlert(
        context,
        title: 'Montant requis',
        message: 'Saisissez le montant du règlement.',
      );
      return;
    }
    final repartition = await _selectionEcheances(
      tiers,
      montant: montant,
      montantFixe: false,
    );
    if (repartition == null || !mounted) return;
    final piece = _piece.text.trim().isEmpty
        ? 'REG-${DateFormat('ddMMyyHHmm').format(DateTime.now())}'
        : _piece.text.trim();
    final libelle = _label.text.trim().isEmpty
        ? 'RÈGLEMENT ${tiers.nom}'
        : _label.text.trim();
    final date = DateFormat('dd/MM/yyyy HH:mm').format(
      DateTime(
        _date.year,
        _date.month,
        _date.day,
        DateTime.now().hour,
        DateTime.now().minute,
      ),
    );
    final echeances = _echeances(tiers);
    for (final MapEntry(key: id, value: value)
        in repartition.montants.entries) {
      final e = echeances.firstWhere((e) => e.id == id);
      final bool saved;
      if (e.dossier != null) {
        final op = DossierOperation(
          type: _isClient
              ? DossierOperationType.clientPayment
              : DossierOperationType.providerPayment,
          titre: '$piece • $libelle • ${repartition.mode}',
          categorie: _categorie,
          montant: value,
          date: date,
          codeJournal: repartition.journal,
          modePaiement: repartition.mode,
        );
        e.dossier!.operations.add(op);
        saved = await _persist(
          context,
          () => erpBackend.saveDossier(e.dossier!),
        );
        if (!saved) e.dossier!.operations.remove(op);
      } else {
        final r = ReglementFacture(
          date: date,
          montant: value,
          codeJournal: repartition.journal,
          modePaiement: repartition.mode,
          observations: '$piece • $libelle',
        );
        final f = e.factureTransitaire;
        final t = e.factureTransporteur;
        final list = f?.reglements ?? t!.reglements;
        list.add(r);
        saved = await _persist(
          context,
          () => f != null
              ? erpBackend.saveFactureTransitaire(f)
              : erpBackend.saveFactureTransporteur(t!),
        );
        if (!saved) list.remove(r);
      }
      if (!saved || !mounted) break;
    }
    if (!mounted) return;
    setState(() {
      _piece.clear();
      _label.clear();
      _amount.clear();
    });
  }

  Future<void> _imputer(_Tiers tiers, CaisseMouvement m) async {
    final repartition = await _selectionEcheances(
      tiers,
      montant: m.montant,
      montantFixe: true,
      enImputation: m,
      mode: _modesPaiement.contains(m.modePaiement) ? m.modePaiement : null,
    );
    if (repartition == null || !mounted) return;
    final dossiers = {for (final d in _dossiers) d.id: d};
    await _persist(
      context,
      () => erpBackend.imputerEncaissement(
        m,
        imputations: [
          for (final MapEntry(key: id, value: value)
              in repartition.montants.entries)
            (dossiers[id]!, value),
        ],
        codeJournal: repartition.journal,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _print(_Tiers tiers) async {
    final logo = await _loadPdfLogo();
    final reglements = _reglements(tiers);
    final echeances = _echeances(tiers);
    final totaux = _totaux(tiers);
    final doc = pw.Document(title: _title, author: 'Sylla Transit & Transport');
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
                _title.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            tiers.label,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Factures',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          _pdfTable(
            ['Date', 'N° pièce', 'Détail', 'À payer', 'Réglé', 'Solde'],
            [
              for (final e in echeances)
                [
                  e.date,
                  e.piece,
                  e.detail,
                  formatCurrency(e.aPayer),
                  formatCurrency(e.regle),
                  formatCurrency(e.solde),
                ],
            ],
            numericColumns: {3, 4, 5},
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Règlements',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          _pdfTable(
            ['Date', 'N° pièce', 'Libellé', 'Mode', 'Journal', 'Montant'],
            [
              for (final r in reglements)
                [
                  r.date,
                  r.piece,
                  r.libelle.replaceAll('•', '-'),
                  r.mode,
                  r.journal,
                  formatCurrency(r.montant),
                ],
            ],
            numericColumns: {5},
          ),
          pw.SizedBox(height: 10),
          _pdfTotals([
            ('Total réglé', formatCurrency(totaux.regle)),
            ('Total dû', formatCurrency(totaux.du)),
            ('Solde', formatCurrency(totaux.du - totaux.regle)),
          ]),
        ],
      ),
    );
    await Printing.layoutPdf(name: _title, onLayout: (_) => doc.save());
  }
}

// Sélection des échéances à régler : le montant réglé est réparti sur les
// factures du tiers (« Imputer » remplit les plus anciennes d'abord).
class _EcheancesDialog extends StatefulWidget {
  final List<_Echeance> echeances;
  final double montant;
  final bool montantFixe;
  final String? journal;
  final String mode;
  final List<String> modes;

  const _EcheancesDialog({
    required this.echeances,
    required this.montant,
    required this.montantFixe,
    required this.journal,
    required this.mode,
    required this.modes,
  });

  @override
  State<_EcheancesDialog> createState() => _EcheancesDialogState();
}

class _EcheancesDialogState extends State<_EcheancesDialog> {
  late final _montant = TextEditingController(
    text: widget.montant.toStringAsFixed(0),
  );
  late final Map<String, TextEditingController> _parts = {
    for (final e in widget.echeances) e.id: TextEditingController(),
  };
  late String? _journal = widget.journal;
  late String _mode = widget.mode;

  @override
  void initState() {
    super.initState();
    _repartir();
  }

  @override
  void dispose() {
    _montant.dispose();
    for (final c in _parts.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _regle => _parseMontant(_montant.text) ?? 0;
  double _part(String id) => _parseMontant(_parts[id]!.text) ?? 0;
  double get _impute => widget.echeances.fold(0, (s, e) => s + _part(e.id));

  void _repartir() {
    var reste = _regle;
    for (final e in widget.echeances) {
      final value = e.solde <= 0 ? 0.0 : math.min(reste, e.solde);
      reste -= value;
      _parts[e.id]!.text = value > 0 ? value.toStringAsFixed(0) : '';
    }
  }

  bool get _valide =>
      _journal != null &&
      _regle > 0 &&
      (_impute - _regle).abs() < 0.01 &&
      widget.echeances.every((e) => _part(e.id) <= e.solde + 0.01);

  @override
  Widget build(BuildContext context) {
    final reste = _regle - _impute;
    TextStyle head = const TextStyle(fontWeight: FontWeight.bold);
    return AlertDialog(
      title: const Text('Sélection des échéances à régler'),
      content: SizedBox(
        width: 900,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  child: TextField(
                    key: const ValueKey('echeances-montant'),
                    controller: _montant,
                    enabled: !widget.montantFixe,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: _inputDecoration('Montant réglé'),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: widget.modes.contains(_mode) ? _mode : null,
                    decoration: _inputDecoration('Mode'),
                    items: [
                      for (final m in widget.modes)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => setState(() => _mode = v ?? _mode),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('echeances-journal'),
                    isExpanded: true,
                    initialValue: _journal,
                    decoration: _inputDecoration('Journal'),
                    items: [
                      for (final j in _journalCodes)
                        DropdownMenuItem(
                          value: j.code,
                          child: Text(
                            '${j.code} • ${j.intitule}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _journal = v),
                  ),
                ),
                OutlinedButton(
                  key: const ValueKey('echeances-imputer'),
                  onPressed: () => setState(_repartir),
                  child: const Text('IMPUTER'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(100),
                    1: FlexColumnWidth(1.6),
                    2: FixedColumnWidth(80),
                    3: FixedColumnWidth(120),
                    4: FixedColumnWidth(120),
                    5: FixedColumnWidth(150),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                      children: [
                        for (final h in [
                          'Échéance / Date',
                          'N° pièce / Dossier',
                          'Type',
                          'À payer',
                          'Solde',
                          'Règlement',
                        ])
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(h, style: head),
                          ),
                      ],
                    ),
                    for (final e in widget.echeances)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(e.date),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.piece,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (e.detail.isNotEmpty)
                                  Text(
                                    e.detail,
                                    style: const TextStyle(
                                      color: _gridMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'FACTURE',
                              style: TextStyle(color: _gridMuted),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(formatCurrency(e.aPayer)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              formatCurrency(e.solde),
                              style: TextStyle(
                                color: e.solde > 0
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF15803D),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: TextField(
                              key: ValueKey('echeance-${e.id}'),
                              controller: _parts[e.id],
                              enabled: e.solde > 0,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                isDense: true,
                                border: const OutlineInputBorder(),
                                errorText: _part(e.id) > e.solde + 0.01
                                    ? 'Max ${formatCurrency(e.solde)}'
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              color: const Color(0xFFF0FDF4),
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 40,
                children: [
                  for (final (label, value) in [
                    ('Montant réglé', _regle),
                    ('Total imputé', _impute),
                    ('Reste à imputer', reste),
                  ])
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(label, style: const TextStyle(color: _gridMuted)),
                        Text(
                          formatCurrency(value),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ANNULER'),
        ),
        FilledButton(
          key: const ValueKey('echeances-valider'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF14532D),
          ),
          onPressed: _valide
              ? () => Navigator.pop<_Repartition>(context, (
                  montants: {
                    for (final e in widget.echeances)
                      if (_part(e.id) > 0) e.id: _part(e.id),
                  },
                  journal: _journal!,
                  mode: _mode,
                ))
              : null,
          child: const Text('VALIDER'),
        ),
      ],
    );
  }
}
