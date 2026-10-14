# API Sylla Transit ERP

API Node.js (Express) qui enregistre les données de l'ERP dans PostgreSQL.
Elle est déployée séparément de l'interface Flutter (`erp.stt-ml.com`).

Au démarrage, l'API :

1. applique les migrations SQL de `migrations/` qui ne l'ont pas encore été ;
2. crée le compte `admin` si la base ne contient encore aucun utilisateur
   (mot de passe : `ADMIN_INITIAL_PASSWORD`, ou un mot de passe temporaire
   affiché une seule fois dans les journaux de déploiement).

## Routes

| Méthode | Route | Rôle |
|---|---|---|
| GET | `/health` | Le processus répond |
| GET | `/ready` | La base PostgreSQL répond |
| POST | `/api/v1/auth/connexion` | Identifiant + mot de passe → jeton de session (12 h) |
| POST | `/api/v1/auth/deconnexion` | Ferme la session |
| GET | `/api/v1/donnees` | Toutes les données de l'ERP (après connexion) |
| PUT | `/api/v1/clients/:id`, `/prestataires/:id`, `/comptes/:id`, `/journaux/:code`, `/voyages/:id`, `/dossiers/:id` | Création ou modification |
| DELETE | `/api/v1/comptes/:id` | Suppression d'un compte non utilisé |
| PUT | `/api/v1/utilisateurs/:id` | Gestion des utilisateurs (administrateur) |

Toutes les routes `/api/v1` sauf la connexion exigent l'en-tête
`Authorization: Bearer <jeton>`. Les droits par module sont vérifiés par l'API.

Règles de gestion appliquées par le serveur :

- mots de passe chiffrés (bcrypt), 8 caractères minimum, blocage 15 minutes après 5 échecs ;
- un dossier enregistré avec une version périmée est refusé (modification simultanée) ;
- une facture clôturée et un dossier clôturé ne peuvent plus être modifiés ;
- les règlements et frais déjà enregistrés ne peuvent être ni supprimés ni modifiés ;
- il reste toujours au moins un administrateur.

## Lancer localement

```powershell
npm install
$env:PORT = "3000"
$env:DATABASE_URL = "postgresql://utilisateur:mot-de-passe@hote:5432/base"
$env:ADMIN_INITIAL_PASSWORD = "un-mot-de-passe-solide"
npm start
```

`npm test` lance les tests, dont un scénario complet sur un PostgreSQL temporaire
(paquet `embedded-postgres`, rien n'est installé sur la machine).

Ne publiez jamais l'URL PostgreSQL réelle dans GitHub. En production, définissez
`DATABASE_URL` comme variable secrète dans Coolify et utilisez le nom interne du
service PostgreSQL sur le réseau Coolify. N'exposez pas directement le port de
PostgreSQL sur Internet.

## Coolify

- Dépôt : `Doumbia1998/stt-erp`
- Répertoire de base : `/backend`
- Pack de construction : Nixpacks
- Port interne : `3000`
- Commande de démarrage : `npm start`
- Domaine API : `https://api.stt-ml.com`
- Variables :
  - `DATABASE_URL` : URL interne PostgreSQL (secrète)
  - `DATABASE_SSL` : `false` sur le réseau privé Coolify, sinon `true` si PostgreSQL exige TLS
  - `CORS_ORIGINS` : `https://erp.stt-ml.com` (origines web autorisées, séparées par des virgules)
  - `ADMIN_INITIAL_PASSWORD` : mot de passe du premier compte `admin` (secret, 8 caractères minimum)

Après déploiement, vérifier `https://api.stt-ml.com/health` puis `/ready`.
