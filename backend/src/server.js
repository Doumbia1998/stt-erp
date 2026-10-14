const { createApp } = require('./app');
const { createPool } = require('./db');
const { migrate } = require('./migrate');
const { ensureInitialAdmin } = require('./auth');

const port = Number(process.env.PORT || 3000);
const pool = createPool();

async function start() {
  if (pool) {
    await migrate(pool);
    await ensureInitialAdmin(pool);
  } else {
    console.warn('DATABASE_URL absent : l’API démarre sans base de données.');
  }

  const server = createApp({ pool }).listen(port, '0.0.0.0', () => {
    console.log(`API Sylla Transit à l’écoute sur le port ${port}`);
  });

  const shutdown = () => {
    server.close(async () => {
      if (pool) {
        await pool.end();
      }
      process.exit(0);
    });
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

start().catch((error) => {
  console.error('Démarrage impossible :', error);
  process.exit(1);
});
