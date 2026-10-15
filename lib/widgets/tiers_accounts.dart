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

// Création rapide d'un compte de tiers depuis la fiche client ou fournisseur.
Future<PlanAccount?> _quickCreateAccount(
  BuildContext context, {
  required List<PlanAccount> comptes,
  required String nature,
  required String prefix,
  required String suggestedName,
}) async {
  final name = suggestedName.trim();
  final letters = name
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '')
      .padRight(3, 'X');
  final code = TextEditingController(
    text: '$prefix${letters.substring(0, math.min(8, letters.length))}',
  );
  final label = TextEditingController(text: name.toUpperCase());
  final formKey = GlobalKey<FormState>();
  final account = await showDialog<PlanAccount>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Nouveau compte $nature'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('quick-account-code'),
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: _inputDecoration(
                  'Numéro de compte *',
                  icon: Icons.tag_rounded,
                  hint: '${prefix}CLIENT',
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Champ obligatoire';
                  if (!text.startsWith(prefix.substring(0, 2))) {
                    return 'Un compte $nature commence par ${prefix.substring(0, 2)}';
                  }
                  final exists = comptes.any(
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
                controller: label,
                decoration: _inputDecoration(
                  'Intitulé *',
                  icon: Icons.short_text_rounded,
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Champ obligatoire' : null,
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
        FilledButton(
          key: const ValueKey('quick-account-save'),
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              PlanAccount(
                id: newLocalId('compte'),
                code: code.text.trim().toUpperCase(),
                libelle: label.text.trim(),
                nature: nature,
              ),
            );
          },
          child: const Text('Créer le compte'),
        ),
      ],
    ),
  );
  code.dispose();
  label.dispose();
  if (account == null || !context.mounted) return null;
  if (!await _persist(context, () => erpBackend.saveAccount(account))) {
    return null;
  }
  comptes.add(account);
  return account;
}
