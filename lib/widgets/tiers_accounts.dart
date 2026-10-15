part of '../main.dart';

// Comptes comptables des tiers (clients 411…, fournisseurs 401…).

// Rattache le compte au tiers après un enregistrement réussi (même règle que le serveur).
void _linkTiersAccount(
  List<PlanAccount> comptes, {
  required String tiersId,
  required String? previousCode,
  required String newCode,
}) {
  if (previousCode != null && previousCode != newCode) {
    for (final account in comptes) {
      if (account.code == previousCode && account.tiersId == tiersId) {
        account.tiersId = null;
      }
    }
  }
  for (final account in comptes) {
    if (account.code == newCode) account.tiersId ??= tiersId;
  }
}

// Comptes proposés pour un tiers : la bonne nature (ou la bonne classe), non
// attribués à un autre tiers.
List<PlanAccount> _accountsForTiers(
  List<PlanAccount> comptes, {
  required String nature,
  required String classPrefix,
  required String? tiersId,
}) =>
    comptes
        .where(
          (a) =>
              (a.nature == nature || a.code.startsWith(classPrefix)) &&
              (a.tiersId == null || a.tiersId == tiersId),
        )
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));

// Comptes généraux d'une classe (41100000 Clients, 40100000 Fournisseurs…).
List<PlanAccount> _generalAccounts(
  List<PlanAccount> comptes,
  String classPrefix,
) =>
    comptes
        .where(
          (a) => a.code.startsWith(classPrefix) && isGeneralAccountCode(a.code),
        )
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));

// Création rapide d'un compte de tiers : sous-compte du compte général choisi.
Future<PlanAccount?> _quickCreateAccount(
  BuildContext context, {
  required List<PlanAccount> comptes,
  required String nature,
  required String prefix,
  required String suggestedName,
}) async {
  final account = await showDialog<PlanAccount>(
    context: context,
    builder: (context) => _QuickAccountDialog(
      comptes: comptes,
      nature: nature,
      prefix: prefix,
      suggestedName: suggestedName,
    ),
  );
  if (account == null || !context.mounted) return null;
  if (!await _persist(context, () => erpBackend.saveAccount(account))) {
    return null;
  }
  comptes.add(account);
  return account;
}

class _QuickAccountDialog extends StatefulWidget {
  final List<PlanAccount> comptes;
  final String nature;
  final String prefix;
  final String suggestedName;

  const _QuickAccountDialog({
    required this.comptes,
    required this.nature,
    required this.prefix,
    required this.suggestedName,
  });

  @override
  State<_QuickAccountDialog> createState() => _QuickAccountDialogState();
}

class _QuickAccountDialogState extends State<_QuickAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _label = TextEditingController();
  late final String _classPrefix = widget.prefix.substring(0, 2);
  late final List<PlanAccount> _generals = _generalAccounts(
    widget.comptes,
    _classPrefix,
  );
  PlanAccount? _general;

  @override
  void initState() {
    super.initState();
    _general =
        _generals.where((a) => a.nature == widget.nature).firstOrNull ??
        _generals.firstOrNull;
    _code.text = _suggestion();
    _label.text = widget.suggestedName.trim().toUpperCase();
  }

  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    super.dispose();
  }

  String _suggestion() {
    final general = _general;
    if (general != null) {
      return nextSubAccountCode(
        general.code,
        widget.comptes.map((a) => a.code),
      );
    }
    final letters = widget.suggestedName
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .padRight(3, 'X');
    return '${widget.prefix}${letters.substring(0, math.min(8, letters.length))}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Nouveau compte ${widget.nature}'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_generals.isNotEmpty) ...[
                DropdownButtonFormField<PlanAccount>(
                  key: const ValueKey('quick-account-general'),
                  isExpanded: true,
                  initialValue: _general,
                  decoration: _inputDecoration(
                    'Compte général',
                    icon: Icons.account_tree_outlined,
                  ),
                  items: [
                    for (final g in _generals)
                      DropdownMenuItem(
                        value: g,
                        child: Text(
                          '${g.code} — ${g.libelle}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _general = value;
                    _code.text = _suggestion();
                  }),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const ValueKey('quick-account-code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    _inputDecoration(
                      'Numéro de compte *',
                      icon: Icons.tag_rounded,
                    ).copyWith(
                      helperText: _general == null
                          ? null
                          : 'Sous-compte suivant de ${_general!.code}',
                    ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Champ obligatoire';
                  if (!text.startsWith(_classPrefix)) {
                    return 'Un compte ${widget.nature} commence par $_classPrefix';
                  }
                  final exists = widget.comptes.any(
                    (a) =>
                        _normalizeUniqueValue(a.code) ==
                        _normalizeUniqueValue(text),
                  );
                  return exists ? 'Ce numéro de compte existe déjà' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('quick-account-label'),
                controller: _label,
                textCapitalization: TextCapitalization.characters,
                decoration: _inputDecoration(
                  'Intitulé *',
                  icon: Icons.short_text_rounded,
                  hint: 'Nom du ${widget.nature.toLowerCase()}',
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Champ obligatoire' : null,
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
      FilledButton(
        key: const ValueKey('quick-account-save'),
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            PlanAccount(
              id: newLocalId('compte'),
              code: _code.text.trim().toUpperCase(),
              libelle: _label.text.trim().toUpperCase(),
              nature: widget.nature,
            ),
          );
        },
        child: const Text('Créer le compte'),
      ),
    ],
  );
}
