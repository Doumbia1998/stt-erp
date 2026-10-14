const { Pool, types } = require('pg');

// DATE et TIMESTAMP restent des chaînes : pas de conversion de fuseau horaire.
types.setTypeParser(1082, (value) => value);
types.setTypeParser(1114, (value) => value);
// NUMERIC -> nombre JavaScript (montants en FCFA, largement dans la précision d'un double).
types.setTypeParser(1700, (value) => Number(value));

function createPool(connectionString = process.env.DATABASE_URL) {
  if (!connectionString) return null;
  return new Pool({
    connectionString,
    connectionTimeoutMillis: 5000,
    max: 10,
    ssl:
      process.env.DATABASE_SSL === 'true'
        ? { rejectUnauthorized: true }
        : undefined,
  });
}

async function withTransaction(pool, work) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = { createPool, withTransaction };
