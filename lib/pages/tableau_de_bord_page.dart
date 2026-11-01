part of '../main.dart';

// --- TABLEAU DE BORD (accueil) ---
// Indicateurs de la période avec tendance, facturation / encaissements sur
// 12 mois, chiffre d'affaires par client, encours clients, circuit des
// dossiers, trésorerie des caisses et derniers documents.

const _tbNavy = Color(0xFF14213D);
const _tbBlue = Color(0xFF1A237E);
const _tbTeal = Color(0xFF0F9D8A);
const _tbAmber = Color(0xFFF59E0B);
const _tbCoral = Color(0xFFE5484D);
const _tbViolet = Color(0xFF7C3AED);
const _tbSky = Color(0xFF0EA5E9);
const _tbMuted = Color(0xFF6B7A90);
const _tbBorder = Color(0xFFE6EAF2);
const _tbPalette = [_tbBlue, _tbTeal, _tbAmber, _tbViolet, _tbSky, _tbCoral];

const _moisCourts = [
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

enum _Periode { mois, trimestre, annee }

// Un document récent : facture, reçu ou bon de caisse.
class _DocumentRecent {
  final DateTime date;
  final String type;
  final IconData icon;
  final Color color;
  final String numero;
  final String tiers;
  final String statut;
  final Color statutColor;
  final double montant;

  const _DocumentRecent({
    required this.date,
    required this.type,
    required this.icon,
    required this.color,
    required this.numero,
    required this.tiers,
    required this.statut,
    required this.statutColor,
    required this.montant,
  });
}

class HomePage extends StatefulWidget {
  final List<TransitDossier> dossiers;
  final List<Client> clients;
  final void Function(int moduleIndex, ErpMenuItem item) onSelectMenu;
  final List<int> availableModuleIndexes;

  const HomePage({
    super.key,
    required this.dossiers,
    required this.clients,
    required this.onSelectMenu,
    required this.availableModuleIndexes,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _Periode _periode = _Periode.mois;

  DateTime get _now => DateTime.now();

  // Début et fin de la période choisie, et de la période précédente.
  (DateTime, DateTime) _bornes({int decalage = 0}) {
    final now = _now;
    switch (_periode) {
      case _Periode.mois:
        final start = DateTime(now.year, now.month - decalage, 1);
        return (start, DateTime(start.year, start.month + 1, 0));
      case _Periode.trimestre:
        final q = (now.month - 1) ~/ 3;
        final start = DateTime(now.year, q * 3 + 1 - decalage * 3, 1);
        return (start, DateTime(start.year, start.month + 3, 0));
      case _Periode.annee:
        final start = DateTime(now.year - decalage, 1, 1);
        return (start, DateTime(start.year, 12, 31));
    }
  }

  String get _libellePeriode => switch (_periode) {
    _Periode.mois => 'ce mois',
    _Periode.trimestre => 'ce trimestre',
    _Periode.annee => 'cette année',
  };

  String get _libellePrecedente => switch (_periode) {
    _Periode.mois => 'vs mois précédent',
    _Periode.trimestre => 'vs trimestre précédent',
    _Periode.annee => 'vs année précédente',
  };

  // --- Montants datés ---

  Iterable<(DateTime, double)> get _facturations sync* {
    for (final d in widget.dossiers) {
      if (d.factureClient.estValidee) {
        final date = _parseFrDate(d.factureClient.dateEmission);
        if (date != null) yield (date, d.factureClient.montant);
      }
      for (final op in d.operations) {
        if (op.type != DossierOperationType.clientInvoice) continue;
        final date = _parseFrDate(op.date);
        if (date != null) yield (date, op.montant);
      }
    }
  }

  Iterable<(DateTime, double)> get _encaissements sync* {
    for (final d in widget.dossiers) {
      for (final op in d.operations) {
        if (op.type != DossierOperationType.clientPayment) continue;
        final date = _parseFrDate(op.date);
        if (date != null) yield (date, op.montant);
      }
    }
  }

  // Charges : factures transitaires et transporteurs, bons de caisse.
  Iterable<(DateTime, double)> get _charges sync* {
    for (final f in _facturesTransitaire) {
      final date = _parseFrDate(f.dateEmission);
      if (date != null) yield (date, f.montant);
    }
    for (final f in _facturesTransporteur) {
      final date = _parseFrDate(f.dateEmission);
      if (date != null) yield (date, f.montant);
    }
    for (final b in _bonsCaisse) {
      final date = _parseFrDate(b.date);
      if (date != null) yield (date, b.montant);
    }
  }

  double _somme(Iterable<(DateTime, double)> rows, (DateTime, DateTime) p) =>
      rows
          .where((r) => _inPeriod(r.$1, p.$1, p.$2))
          .fold(0, (s, r) => s + r.$2);

  // Les 12 derniers mois, du plus ancien au mois en cours.
  List<DateTime> get _douzeMois => [
    for (var i = 11; i >= 0; i--) DateTime(_now.year, _now.month - i, 1),
  ];

  List<double> _parMois(Iterable<(DateTime, double)> rows) {
    final mois = _douzeMois;
    final values = List<double>.filled(12, 0);
    for (final (date, montant) in rows) {
      for (var i = 0; i < 12; i++) {
        if (date.year == mois[i].year && date.month == mois[i].month) {
          values[i] += montant;
        }
      }
    }
    return values;
  }

  void _ouvrir(String module, String item) {
    final index = _MainNavigationPageState._modules.indexWhere(
      (m) => m.title == module,
    );
    if (index < 0 || !widget.availableModuleIndexes.contains(index)) return;
    final entry = _MainNavigationPageState._modules[index].items
        .where((i) => i.title == item)
        .firstOrNull;
    if (entry != null) widget.onSelectMenu(index, entry);
  }

  @override
  Widget build(BuildContext context) {
    final periode = _bornes();
    final precedente = _bornes(decalage: 1);
    final facturations = _facturations.toList();
    final encaissements = _encaissements.toList();
    final charges = _charges.toList();

    final ca = _somme(facturations, periode);
    final caPrec = _somme(facturations, precedente);
    final enc = _somme(encaissements, periode);
    final encPrec = _somme(encaissements, precedente);
    final chg = _somme(charges, periode);
    final chgPrec = _somme(charges, precedente);
    final creances = widget.dossiers.fold<double>(
      0,
      (s, d) => s + math.max(0, d.soldeClient),
    );
    final principale = soldeCaisse(caissePrincipale, _caisseMouvements);
    final depenses = soldeCaisse(caisseDepenses, _caisseMouvements);

    return Container(
      color: const Color(0xFFF3F5FA),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final pad = compact ? 14.0 : 26.0;
          final width = math.min(constraints.maxWidth, 1440.0) - pad * 2;
          final kpiWidth = compact ? (width - 12) / 2 : (width - 4 * 14) / 5;
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(pad),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _entete(compact),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 14,
                        runSpacing: 12,
                        children: [
                          _KpiCard(
                            width: kpiWidth,
                            label: 'Chiffre d’affaires',
                            value: ca,
                            precedent: caPrec,
                            note: _libellePrecedente,
                            color: _tbBlue,
                            icon: Icons.trending_up_rounded,
                            serie: _parMois(facturations),
                          ),
                          _KpiCard(
                            width: kpiWidth,
                            label: 'Encaissements',
                            value: enc,
                            precedent: encPrec,
                            note: _libellePrecedente,
                            color: _tbTeal,
                            icon: Icons.savings_rounded,
                            serie: _parMois(encaissements),
                          ),
                          _KpiCard(
                            width: kpiWidth,
                            label: 'Charges',
                            value: chg,
                            precedent: chgPrec,
                            note: _libellePrecedente,
                            color: _tbAmber,
                            icon: Icons.local_shipping_rounded,
                            serie: _parMois(charges),
                            hausseFavorable: false,
                          ),
                          _KpiCard(
                            width: kpiWidth,
                            label: 'Créances clients',
                            value: creances,
                            note: 'Reste à encaisser',
                            color: _tbCoral,
                            icon: Icons.pending_actions_rounded,
                            onTap: () =>
                                _ouvrir('Recouvrement', 'Etat des Impayés'),
                          ),
                          _KpiCard(
                            width: kpiWidth,
                            label: 'Trésorerie caisses',
                            value: principale + depenses,
                            note:
                                'Principale ${formatCurrency(principale)} • Dépenses ${formatCurrency(depenses)}',
                            color: _tbViolet,
                            icon: Icons.account_balance_wallet_rounded,
                            onTap: () => _ouvrir('Caisse', 'Relevé de Caisse'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ligne(compact, [
                        (2, _evolution(facturations, encaissements)),
                        (1, _caParClient(periode)),
                      ]),
                      const SizedBox(height: 16),
                      _ligne(compact, [
                        (3, _encours()),
                        (2, _circuitDossiers()),
                      ]),
                      const SizedBox(height: 16),
                      _documentsRecents(compact),
                      const SizedBox(height: 16),
                      _accesRapide(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Panneaux côte à côte (flex), empilés sur petit écran.
  Widget _ligne(bool compact, List<(int, Widget)> panels) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (_, w)) in panels.indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            w,
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (flex, w)) in panels.indexed) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(flex: flex, child: w),
          ],
        ],
      ),
    );
  }

  Widget _entete(bool compact) {
    final nom = _currentUser?.name ?? '';
    const jours = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche',
    ];
    final now = _now;
    final date =
        '${jours[now.weekday - 1]} ${now.day} ${_moisLongs[now.month - 1].toLowerCase()} ${now.year}';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tableau de bord',
              style: TextStyle(
                color: _tbNavy,
                fontSize: compact ? 24 : 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${nom.isEmpty ? 'Bonjour' : 'Bonjour $nom'} • ${date[0].toUpperCase()}${date.substring(1)}',
              style: const TextStyle(color: _tbMuted, fontSize: 14),
            ),
          ],
        ),
        SegmentedButton<_Periode>(
          key: const ValueKey('dashboard-period'),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            backgroundColor: Colors.white,
            selectedBackgroundColor: _tbBlue,
            selectedForegroundColor: Colors.white,
          ),
          segments: const [
            ButtonSegment(value: _Periode.mois, label: Text('Mois')),
            ButtonSegment(value: _Periode.trimestre, label: Text('Trimestre')),
            ButtonSegment(value: _Periode.annee, label: Text('Année')),
          ],
          selected: {_periode},
          onSelectionChanged: (s) => setState(() => _periode = s.first),
        ),
      ],
    );
  }

  Widget _evolution(
    List<(DateTime, double)> facturations,
    List<(DateTime, double)> encaissements,
  ) {
    final mois = _douzeMois;
    final factures = _parMois(facturations);
    final encaisse = _parMois(encaissements);
    final vide = factures.every((v) => v == 0) && encaisse.every((v) => v == 0);
    return _TbPanel(
      title: 'Facturation et encaissements',
      subtitle: '12 derniers mois',
      trailing: const Wrap(
        spacing: 14,
        children: [
          _Legende(color: _tbBlue, label: 'Facturé', barre: true),
          _Legende(color: _tbTeal, label: 'Encaissé'),
        ],
      ),
      child: vide
          ? const _TbEmpty(
              message:
                  'Les montants apparaîtront après les premières factures clients.',
            )
          : SizedBox(
              height: 250,
              child: CustomPaint(
                painter: _BarLinePainter(
                  labels: [for (final m in mois) _moisCourts[m.month - 1]],
                  bars: factures,
                  line: encaisse,
                ),
                size: Size.infinite,
              ),
            ),
    );
  }

  Widget _caParClient((DateTime, DateTime) periode) {
    final parClient = <String, double>{};
    for (final d in widget.dossiers) {
      if (!d.factureClient.estValidee) continue;
      final date = _parseFrDate(d.factureClient.dateEmission);
      if (!_inPeriod(date, periode.$1, periode.$2)) continue;
      parClient.update(
        d.client.nom,
        (v) => v + d.totalFacturesClient,
        ifAbsent: () => d.totalFacturesClient,
      );
    }
    final sorted = parClient.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<double>(0, (s, e) => s + e.value);
    final parts = <(String, double)>[
      for (final e in sorted.take(4)) (e.key, e.value),
      if (sorted.length > 4)
        ('Autres', sorted.skip(4).fold<double>(0, (s, e) => s + e.value)),
    ];
    return _TbPanel(
      title: 'Chiffre d’affaires par client',
      subtitle: 'Factures validées $_libellePeriode',
      child: total == 0
          ? _TbEmpty(message: 'Aucune facture client validée $_libellePeriode.')
          : Column(
              children: [
                SizedBox(
                  height: 170,
                  child: CustomPaint(
                    painter: _DonutPainter([
                      for (final p in parts) p.$2,
                    ], _tbPalette),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _compact(total),
                            style: const TextStyle(
                              color: _tbNavy,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'FCFA',
                            style: TextStyle(color: _tbMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final (i, (nom, montant)) in parts.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _tbPalette[i % _tbPalette.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            nom,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '${(montant / total * 100).round()} %',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _encours() {
    final parClient = <String, (Client, double, int, DateTime?)>{};
    for (final d in widget.dossiers) {
      if (d.soldeClient <= 0) continue;
      final date = _parseFrDate(d.factureClient.dateEmission);
      final current = parClient[d.client.id];
      final oldest = current?.$4 == null
          ? date
          : (date != null && date.isBefore(current!.$4!) ? date : current!.$4);
      parClient[d.client.id] = (
        d.client,
        (current?.$2 ?? 0) + d.soldeClient,
        (current?.$3 ?? 0) + 1,
        oldest,
      );
    }
    final rows = parClient.values.toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    TextStyle head = const TextStyle(
      color: _tbMuted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return _TbPanel(
      title: 'Encours clients',
      subtitle: 'Factures non soldées, du plus gros au plus petit',
      trailing: TextButton(
        key: const ValueKey('dashboard-impayes'),
        onPressed: () => _ouvrir('Recouvrement', 'Etat des Impayés'),
        child: const Text('Voir l’état des impayés →'),
      ),
      child: rows.isEmpty
          ? const _TbEmpty(
              message: 'Aucune créance : tous les clients sont à jour.',
            )
          : Table(
              columnWidths: const {
                0: FlexColumnWidth(2.4),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(0.8),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _tbBorder)),
                  ),
                  children: [
                    for (final h in [
                      'Client',
                      'Solde dû',
                      'Plus ancienne',
                      'Fact.',
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(h, style: head),
                      ),
                  ],
                ),
                for (final (client, solde, nb, oldest) in rows.take(6))
                  TableRow(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: _tbBorder)),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: _tbBlue.withValues(alpha: 0.1),
                              child: Text(
                                client.nom.isEmpty ? '?' : client.nom[0],
                                style: const TextStyle(
                                  color: _tbBlue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                client.nom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatCurrency(solde),
                        style: const TextStyle(
                          color: _tbCoral,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        oldest == null
                            ? '-'
                            : '${DateFormat('dd/MM/yy').format(oldest)} (${_now.difference(oldest).inDays} j)',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      Text('$nb', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
              ],
            ),
    );
  }

  Widget _circuitDossiers() {
    final dossiers = widget.dossiers;
    final clotures = dossiers.where((d) => d.estCloture).length;
    final soldes = dossiers
        .where((d) => !d.estCloture && d.estFacture && d.soldeClient <= 0)
        .length;
    final factures = dossiers
        .where((d) => !d.estCloture && d.estFacture && d.soldeClient > 0)
        .length;
    final ouverts = dossiers
        .where((d) => !d.estCloture && !d.estFacture)
        .length;
    final parts = [
      ('En cours (non facturés)', ouverts, _tbSky),
      ('Facturés, à encaisser', factures, _tbAmber),
      ('Soldés', soldes, _tbTeal),
      ('Clôturés', clotures, _tbBlue),
    ];
    final conteneurs = dossiers.fold<int>(0, (s, d) => s + d.nbConteneurs);
    return _TbPanel(
      title: 'Circuit des dossiers',
      subtitle: '${dossiers.length} dossier(s) • $conteneurs conteneur(s)',
      child: dossiers.isEmpty
          ? const _TbEmpty(message: 'Aucun dossier pour le moment.')
          : Row(
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      [for (final p in parts) p.$2.toDouble()],
                      [for (final p in parts) p.$3],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${dossiers.length}',
                            style: const TextStyle(
                              color: _tbNavy,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'dossiers',
                            style: TextStyle(color: _tbMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (label, n, color) in parts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Text(
                                '$n',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  List<_DocumentRecent> get _documents {
    final docs = <_DocumentRecent>[];
    for (final d in widget.dossiers.where((d) => d.estFacture)) {
      final date = _parseFrDate(d.factureClient.dateEmission);
      if (date == null) continue;
      final statut = d.soldeClient <= 0
          ? 'Payée'
          : d.totalReglementsClient > 0
          ? 'Commencement'
          : 'Non payée';
      docs.add(
        _DocumentRecent(
          date: date,
          type: 'Facture client',
          icon: Icons.request_quote_rounded,
          color: _tbBlue,
          numero: d.factureClient.reference,
          tiers: d.client.nom,
          statut: statut,
          statutColor: statut == 'Payée'
              ? _tbTeal
              : statut == 'Commencement'
              ? _tbAmber
              : _tbCoral,
          montant: d.totalFacturesClient,
        ),
      );
    }
    for (final m in _caisseMouvements) {
      if (m.type != CaisseMouvement.encaissement) continue;
      final date = _parseFrDate(m.date);
      if (date == null) continue;
      docs.add(
        _DocumentRecent(
          date: date,
          type: 'Reçu de caisse',
          icon: Icons.point_of_sale_rounded,
          color: _tbTeal,
          numero: m.recu,
          tiers: _dossierById(m.dossierId)?.client.nom ?? '',
          statut: m.estImpute ? 'Imputé' : 'À imputer',
          statutColor: m.estImpute ? _tbTeal : _tbAmber,
          montant: m.montant,
        ),
      );
    }
    for (final b in _bonsCaisse) {
      final date = _parseFrDate(b.date);
      if (date == null) continue;
      final paye = _caisseMouvements.any((m) => m.bonId == b.id);
      docs.add(
        _DocumentRecent(
          date: date,
          type: 'Bon de caisse',
          icon: Icons.receipt_long_rounded,
          color: _tbViolet,
          numero: b.reference,
          tiers: b.beneficiaire,
          statut: paye ? 'Payé' : 'À payer',
          statutColor: paye ? _tbTeal : _tbAmber,
          montant: b.montant,
        ),
      );
    }
    for (final f in _facturesTransitaire) {
      final date = _parseFrDate(f.dateEmission);
      if (date == null) continue;
      docs.add(
        _DocumentRecent(
          date: date,
          type: 'Facture transitaire',
          icon: Icons.directions_boat_rounded,
          color: _tbSky,
          numero: f.reference,
          tiers: _partnerLabel(f.transitaireId),
          statut: f.estAcquittee ? 'Réglée' : 'À régler',
          statutColor: f.estAcquittee ? _tbTeal : _tbCoral,
          montant: f.montant,
        ),
      );
    }
    for (final f in _facturesTransporteur) {
      final date = _parseFrDate(f.dateEmission);
      if (date == null) continue;
      docs.add(
        _DocumentRecent(
          date: date,
          type: 'Facture transporteur',
          icon: Icons.local_shipping_rounded,
          color: _tbAmber,
          numero: f.reference,
          tiers: _partnerLabel(f.transporteurId),
          statut: f.estPayee ? 'Réglée' : 'À régler',
          statutColor: f.estPayee ? _tbTeal : _tbCoral,
          montant: f.montant,
        ),
      );
    }
    docs.sort((a, b) => b.date.compareTo(a.date));
    return docs;
  }

  Widget _documentsRecents(bool compact) {
    final docs = _documents.take(8).toList();
    return _TbPanel(
      title: 'Derniers documents',
      subtitle: 'Factures, reçus et bons de caisse les plus récents',
      child: docs.isEmpty
          ? const _TbEmpty(message: 'Aucun document pour le moment.')
          : Column(
              key: const ValueKey('dashboard-documents'),
              children: [
                for (final doc in docs)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: _tbBorder)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: doc.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(doc.icon, size: 18, color: doc.color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                doc.numero,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                doc.type,
                                style: const TextStyle(
                                  color: _tbMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!compact)
                          Expanded(
                            flex: 3,
                            child: Text(
                              doc.tiers,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        if (!compact)
                          SizedBox(
                            width: 90,
                            child: Text(
                              DateFormat('dd/MM/yy').format(doc.date),
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: doc.statutColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            doc.statut,
                            style: TextStyle(
                              color: doc.statutColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: compact ? 100 : 130,
                          child: Text(
                            formatCurrency(doc.montant),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _accesRapide() => _TbPanel(
    title: 'Accès rapide',
    subtitle: 'Modules auxquels vous avez accès',
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final index in widget.availableModuleIndexes)
          if (_MainNavigationPageState._modules[index].title != 'Gestion')
            PopupMenuButton<ErpMenuItem>(
              tooltip:
                  'Accès rapide : ${_MainNavigationPageState._modules[index].title}',
              onSelected: (item) => widget.onSelectMenu(index, item),
              itemBuilder: (context) => [
                for (final item
                    in _MainNavigationPageState._modules[index].items.where(
                      _menuVisible,
                    ))
                  PopupMenuItem(
                    value: item,
                    child: Row(
                      children: [
                        Icon(item.icon, size: 18, color: _tbBlue),
                        const SizedBox(width: 10),
                        Text(item.title),
                      ],
                    ),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _tbBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _MainNavigationPageState._modules[index].icon,
                      size: 18,
                      color: _tbBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _MainNavigationPageState._modules[index].title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
      ],
    ),
  );
}

// 12,4 M / 850 K pour les centres de graphiques.
String _compact(double value) {
  final abs = value.abs();
  if (abs >= 1e9) return '${(value / 1e9).toStringAsFixed(1)} Md';
  if (abs >= 1e6) return '${(value / 1e6).toStringAsFixed(1)} M';
  if (abs >= 1e3) return '${(value / 1e3).toStringAsFixed(0)} K';
  return value.toStringAsFixed(0);
}

class _TbPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _TbPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _tbBorder),
      boxShadow: [
        BoxShadow(
          color: _tbNavy.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _tbNavy,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: _tbMuted, fontSize: 12),
                ),
              ],
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _TbEmpty extends StatelessWidget {
  final String message;

  const _TbEmpty({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 26),
    child: Row(
      children: [
        const Icon(Icons.insights_rounded, color: _tbMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: const TextStyle(color: _tbMuted)),
        ),
      ],
    ),
  );
}

class _Legende extends StatelessWidget {
  final Color color;
  final String label;
  final bool barre;

  const _Legende({
    required this.color,
    required this.label,
    this.barre = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: barre ? 12 : 16,
        height: barre ? 12 : 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: _tbMuted)),
    ],
  );
}

// Indicateur : montant de la période, évolution et courbe des 12 mois.
class _KpiCard extends StatelessWidget {
  final double width;
  final String label;
  final double value;
  final double? precedent;
  final String note;
  final Color color;
  final IconData icon;
  final List<double>? serie;
  // Pour les charges, une hausse est défavorable (en rouge).
  final bool hausseFavorable;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.width,
    required this.label,
    required this.value,
    this.precedent,
    required this.note,
    required this.color,
    required this.icon,
    this.serie,
    this.hausseFavorable = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final prev = precedent;
    double? variation;
    if (prev != null && prev > 0) variation = (value - prev) / prev * 100;
    final hausse = (variation ?? 0) >= 0;
    final bon = hausse == hausseFavorable;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _tbBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _tbMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 17, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${formatCurrency(value)} F',
                  style: const TextStyle(
                    color: _tbNavy,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (prev != null)
                    Text(
                      variation == null
                          ? '—  '
                          : '${hausse ? '▲' : '▼'} ${variation.abs().toStringAsFixed(1)} %  ',
                      style: TextStyle(
                        color: variation == null
                            ? _tbMuted
                            : bon
                            ? _tbTeal
                            : _tbCoral,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _tbMuted, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
              if (serie != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: CustomPaint(painter: _SparklinePainter(serie!, color)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  const _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = maxV - minV == 0 ? 1 : maxV - minV;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          size.height - (values[i] - minV) / range * (size.height - 4) - 2,
        ),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;

  const _DonutPainter(this.values, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    final stroke = radius * 0.32;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = const Color(0xFFEEF1F7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      if (sweep <= 0) continue;
      canvas.drawArc(
        rect,
        start,
        math.max(sweep - 0.03, 0.01),
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.values != values;
}

// Barres (facturé) et courbe (encaissé) sur les mêmes axes.
class _BarLinePainter extends CustomPainter {
  final List<String> labels;
  final List<double> bars;
  final List<double> line;

  const _BarLinePainter({
    required this.labels,
    required this.bars,
    required this.line,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 54.0;
    const bottom = 24.0;
    final chartW = size.width - left;
    final chartH = size.height - bottom - 6;
    final maxV = [...bars, ...line, 1.0].reduce(math.max) * 1.1;
    final grid = Paint()
      ..color = const Color(0xFFEDF0F6)
      ..strokeWidth = 1;
    final textStyle = const TextStyle(color: _tbMuted, fontSize: 10.5);

    for (var i = 0; i <= 4; i++) {
      final y = 6 + chartH - chartH * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      final tp = TextPainter(
        text: TextSpan(text: _compact(maxV * i / 4), style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 8, y - tp.height / 2));
    }

    final slot = chartW / bars.length;
    final barW = math.min(26.0, slot * 0.55);
    for (var i = 0; i < bars.length; i++) {
      final x = left + slot * i + slot / 2;
      final h = bars[i] / maxV * chartH;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x - barW / 2, 6 + chartH - h, barW, h),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = i == bars.length - 1
              ? _tbBlue
              : _tbBlue.withValues(alpha: 0.55),
      );
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - tp.height));
    }

    final points = [
      for (var i = 0; i < line.length; i++)
        Offset(
          left + slot * i + slot / 2,
          6 + chartH - line[i] / maxV * chartH,
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _tbTeal
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in points) {
      canvas.drawCircle(p, 4, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..color = _tbTeal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_BarLinePainter old) =>
      old.bars != bars || old.line != line;
}
