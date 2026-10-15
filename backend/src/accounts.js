const { conflict } = require('./errors');

// Prochain sous-compte d'un compte général : 65880000 -> 65880001, 41100000 -> 41100002…
// Les sous-comptes occupent au plus les 4 derniers chiffres « à zéro » du compte général.
function nextSubAccount(general, existingCodes) {
  general = general.trim();
  const codes = new Set(existingCodes.map((c) => c.trim().toUpperCase()));
  codes.add(general);
  const trailingZeros = general.length - general.replace(/0+$/, '').length;
  if (!/^\d+$/.test(general) || trailingZeros === 0) {
    for (let n = 1; n < 1000; n++) {
      const candidate = `${general}${String(n).padStart(3, '0')}`;
      if (!codes.has(candidate)) return candidate;
    }
    throw conflict(`Plus de sous-compte disponible sous ${general}.`);
  }
  const base = Number(general);
  const span = 10 ** Math.min(trailingZeros, 4);
  let last = base;
  for (const code of codes) {
    if (code.length !== general.length || !/^\d+$/.test(code)) continue;
    const value = Number(code);
    if (value > base && value < base + span) last = Math.max(last, value);
  }
  let next = last + 1;
  while (codes.has(String(next).padStart(general.length, '0'))) next += 1;
  if (next >= base + span) {
    throw conflict(`Plus de sous-compte disponible sous ${general}.`);
  }
  return String(next).padStart(general.length, '0');
}

module.exports = { nextSubAccount };
