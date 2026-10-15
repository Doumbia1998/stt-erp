class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const badRequest = (message) => new ApiError(400, message);
const conflict = (message) => new ApiError(409, message);
const notFound = (message) => new ApiError(404, message);
const forbidden = (message = 'Accès non autorisé') =>
  new ApiError(403, message);

// Traduit les violations de contraintes PostgreSQL en erreurs lisibles.
function fromDatabaseError(error) {
  switch (error.code) {
    case '23505':
      return conflict(uniqueMessages[error.constraint] ?? 'Cette valeur existe déjà.');
    case '23503':
      return conflict(
        error.message.includes('is still referenced')
          ? 'Cet élément est encore utilisé ailleurs et ne peut pas être supprimé.'
          : 'Un élément référencé (client, prestataire, compte ou journal) est introuvable.',
      );
    case '23514':
    case '22P02':
    case '22007':
    case '22008':
      return badRequest('Données invalides.');
    default:
      return null;
  }
}

const uniqueMessages = {
  utilisateurs_identifiant_unique: 'Cet identifiant utilisateur existe déjà.',
  plan_comptable_code_key: 'Ce code de compte comptable existe déjà.',
  journaux_pkey: 'Ce code journal existe déjà.',
  dossiers_num_dossier_key: 'Ce numéro de dossier existe déjà.',
  modes_reglement_intitule_unique: 'Ce mode de règlement existe déjà.',
  factures_reference_key: 'Cette référence de facture existe déjà.',
};

module.exports = {
  ApiError,
  badRequest,
  conflict,
  notFound,
  forbidden,
  fromDatabaseError,
};
