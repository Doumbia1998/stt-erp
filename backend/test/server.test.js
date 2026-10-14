const { after, before, test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { server } = require('../src/server');

let baseUrl;

before(async () => {
  if (!server.listening) {
    await once(server, 'listening');
  }
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.close();
});

test('health endpoint reports the API status', async () => {
  const response = await fetch(`${baseUrl}/health`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: 'ok',
    service: 'stt-erp-api',
  });
});

test('readiness reports missing database configuration', async () => {
  if (process.env.DATABASE_URL) {
    return;
  }

  const response = await fetch(`${baseUrl}/ready`);
  assert.equal(response.status, 503);
  assert.equal((await response.json()).status, 'not_ready');
});

test('unknown routes return a JSON 404', async () => {
  const response = await fetch(`${baseUrl}/route-inconnue`);
  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { error: 'Route introuvable' });
});
