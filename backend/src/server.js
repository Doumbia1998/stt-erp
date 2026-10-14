const express = require('express');
const { Pool } = require('pg');

const app = express();
const port = Number(process.env.PORT || 3000);
const allowedOrigins = new Set(
  (process.env.CORS_ORIGINS || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
);

app.disable('x-powered-by');
app.use(express.json({ limit: '1mb' }));

app.use((req, res, next) => {
  const origin = req.get('origin');
  if (origin && allowedOrigins.has(origin)) {
    res.set('Access-Control-Allow-Origin', origin);
    res.set('Vary', 'Origin');
    res.set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type,Authorization');
  }

  if (req.method === 'OPTIONS') {
    return res.sendStatus(origin && allowedOrigins.has(origin) ? 204 : 403);
  }

  next();
});

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'stt-erp-api' });
});

const pool = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      connectionTimeoutMillis: 5000,
      max: 10,
      ssl:
        process.env.DATABASE_SSL === 'true'
          ? { rejectUnauthorized: true }
          : undefined,
    })
  : null;

app.get('/ready', async (_req, res, next) => {
  if (!pool) {
    return res.status(503).json({
      status: 'not_ready',
      reason: 'DATABASE_URL is not configured',
    });
  }

  try {
    await pool.query('SELECT 1');
    return res.json({ status: 'ready', database: 'connected' });
  } catch (error) {
    return next(error);
  }
});

app.get('/api/v1', (_req, res) => {
  res.json({ service: 'stt-erp-api', version: 'v1' });
});

app.use((_req, res) => {
  res.status(404).json({ error: 'Route introuvable' });
});

app.use((error, _req, res, _next) => {
  if (error instanceof SyntaxError && 'body' in error) {
    return res.status(400).json({ error: 'Corps JSON invalide' });
  }

  console.error('Erreur API :', error.message);
  return res.status(500).json({ error: 'Erreur interne du serveur' });
});

const server = app.listen(port, '0.0.0.0', () => {
  console.log(`API Sylla Transit à l’écoute sur le port ${port}`);
});

async function shutdown() {
  server.close(async () => {
    if (pool) {
      await pool.end();
    }
    process.exit(0);
  });
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

module.exports = { app, server };
