# API Sylla Transit ERP

Ce service fournit la base de l'API à déployer séparément de l'interface Flutter.
Il expose `GET /health` pour le contrôle du processus et `GET /ready` pour vérifier
la connexion PostgreSQL. Les routes métier et l'authentification restent à ajouter
avant de connecter l'ERP aux données réelles.

## Lancer localement

```powershell
npm install
$env:PORT = "3000"
$env:DATABASE_URL = "postgresql://utilisateur:mot-de-passe@hote:5432/base"
npm start
```

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
- Variables : `DATABASE_URL`, `CORS_ORIGINS` (origines web autorisées séparées par des virgules), `DATABASE_SSL` (`false` sur le réseau privé Coolify, sinon `true` si PostgreSQL exige TLS)

Après déploiement, vérifier `https://api.stt-ml.com/health` puis `/ready`.
