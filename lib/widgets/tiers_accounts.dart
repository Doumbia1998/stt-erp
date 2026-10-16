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

// Comptes proposés pour un tiers : les comptes généraux de sa classe
// (41100000 pour tous les clients, 40100000 / 40120000 pour les fournisseurs),
// à défaut tous les comptes de la classe ; plus le compte actuel du tiers.
List<PlanAccount> _accountsForTiers(
  List<PlanAccount> comptes, {
  required String nature,
  required String classPrefix,
  String? currentCode,
}) {
  final ofClass = comptes
      .where((a) => a.nature == nature || a.code.startsWith(classPrefix))
      .toList();
  final generals = ofClass.where((a) => isGeneralAccountCode(a.code)).toList();
  final options = generals.isNotEmpty ? generals : ofClass;
  final current = comptes.where((a) => a.code == currentCode).firstOrNull;
  if (current != null && !options.contains(current)) options.add(current);
  return options..sort((a, b) => a.code.compareTo(b.code));
}
