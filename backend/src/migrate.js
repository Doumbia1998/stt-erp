const fs = require('node:fs/promises');
const path = require('node:path');
const { withTransaction } = require('./db');

const migrationsDir = path.join(__dirname, '..', 'migrations');

// Applique dans l'ordre les fichiers SQL de migrations/ qui ne l'ont pas encore été.
async function migrate(pool, log = console.log) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      nom TEXT PRIMARY KEY,
      appliquee_le TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
  const files = (await fs.readdir(migrationsDir))
    .filter((file) => file.endsWith('.sql'))
    .sort();
  for (const file of files) {
    const sql = await fs.readFile(path.join(migrationsDir, file), 'utf8');
    await withTransaction(pool, async (client) => {
      // Verrou pour qu'une seule instance applique les migrations à la fois.
      await client.query('SELECT pg_advisory_xact_lock(424242)');
      const { rowCount } = await client.query(
        'SELECT 1 FROM schema_migrations WHERE nom = $1',
        [file],
      );
      if (rowCount > 0) return;
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (nom) VALUES ($1)', [
        file,
      ]);
      log(`Migration appliquée : ${file}`);
    });
  }
}

module.exports = { migrate };
