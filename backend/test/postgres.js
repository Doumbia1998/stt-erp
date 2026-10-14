// PostgreSQL temporaire pour les tests (binaires fournis par embedded-postgres).
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { Client } = require('pg');

// pg_ctl laisse le serveur hériter de ses sorties : on les ignore pour ne pas bloquer.
function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: 'ignore', windowsHide: true });
    child.on('error', reject);
    child.on('exit', (code) =>
      code === 0 ? resolve() : reject(new Error(`${path.basename(command)} a échoué (${code})`)),
    );
  });
}

async function startTestPostgres(port) {
  const { default: EmbeddedPostgres } = await import('embedded-postgres');
  const databaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'stt-pg-'));
  const postgres = new EmbeddedPostgres({
    databaseDir,
    user: 'postgres',
    password: 'postgres',
    port,
    persistent: false,
    onLog: () => {},
  });
  await postgres.initialise();

  let stop;
  if (process.platform === 'win32') {
    // Sous Windows, « postgres » refuse un compte administrateur ; pg_ctl abaisse les droits.
    const { pg_ctl: pgCtl } = await import(`@embedded-postgres/windows-${process.arch}`);
    await run(pgCtl, [
      'start', '-w', '-D', databaseDir, '-o', `-p ${port}`,
      '-l', path.join(databaseDir, 'postgres.log'),
    ]);
    stop = () => run(pgCtl, ['stop', '-w', '-m', 'fast', '-D', databaseDir]);
  } else {
    await postgres.start();
    stop = () => postgres.stop();
  }
  const admin = new Client({
    connectionString: `postgresql://postgres:postgres@127.0.0.1:${port}/postgres`,
  });
  try {
    await admin.connect();
    await admin.query('CREATE DATABASE stt_test');
  } catch (error) {
    await stop();
    throw error;
  } finally {
    await admin.end();
  }

  return {
    url: `postgresql://postgres:postgres@127.0.0.1:${port}/stt_test`,
    async stop() {
      await stop();
      fs.rmSync(databaseDir, { recursive: true, force: true });
    },
  };
}

module.exports = { startTestPostgres };
