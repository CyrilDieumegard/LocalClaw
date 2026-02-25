#!/usr/bin/env node
const http = require('http');

const port = process.env.PORT ? Number(process.env.PORT) : 8787;

const server = http.createServer((req, res) => {
  if (req.method !== 'POST' || req.url !== '/api/license/activate') {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ ok: false, message: 'Not found' }));
  }

  let body = '';
  req.on('data', (chunk) => { body += chunk; });
  req.on('end', () => {
    try {
      const payload = JSON.parse(body || '{}');
      const email = String(payload.email || '').toLowerCase().trim();
      const key = String(payload.licenseKey || '').toUpperCase().trim();

      // Règle simple de test
      // email: cyril@test.local
      // clé: LOCALCLAW-V1-TEST
      if (email === 'cyril@test.local' && key === 'LOCALCLAW-V1-TEST') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({
          ok: true,
          token: 'mock-token-' + Date.now(),
          message: 'Activated (mock)',
          expiresAt: null
        }));
      }

      res.writeHead(403, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ ok: false, message: 'Invalid license (mock)' }));
    } catch (err) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ ok: false, message: 'Bad JSON' }));
    }
  });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Mock license server running on http://127.0.0.1:${port}`);
  console.log('Valid test credentials:');
  console.log('  Email: cyril@test.local');
  console.log('  License key: LOCALCLAW-V1-TEST');
});
