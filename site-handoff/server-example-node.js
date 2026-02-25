// Example minimal backend (Node.js, no framework)
// Endpoints:
// - POST /api/license/activate
// - GET /api/download?token=...

const http = require('http');
const crypto = require('crypto');

const PORT = process.env.PORT || 3000;
const SECRET = process.env.DOWNLOAD_SECRET || 'change-me';
const DMG_URL = process.env.DMG_URL || 'https://localclaw.io/downloads/builds/LocalClawInstaller-v1.0.0.dmg';

// fake in-memory db
const licenses = new Map();
licenses.set('LCW-TEST-1234-ABCD', { email: 'cyril@test.local', maxMachines: 2, machines: new Set(), active: true });

function signToken(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  return `${body}.${sig}`;
}

function verifyToken(token) {
  const [body, sig] = token.split('.');
  if (!body || !sig) return null;
  const expected = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  if (sig !== expected) return null;
  const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  if (Date.now() > payload.exp) return null;
  return payload;
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', c => (data += c));
    req.on('end', () => {
      try { resolve(JSON.parse(data || '{}')); }
      catch (e) { reject(e); }
    });
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'POST' && req.url === '/api/license/activate') {
    try {
      const body = await readJson(req);
      const email = String(body.email || '').trim().toLowerCase();
      const licenseKey = String(body.licenseKey || '').trim().toUpperCase();
      const machineId = String(body.machineId || '').trim();

      const row = licenses.get(licenseKey);
      if (!row || !row.active || row.email !== email) {
        res.writeHead(403, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ ok: false, message: 'Invalid license' }));
      }

      row.machines.add(machineId);
      if (row.machines.size > row.maxMachines) {
        row.machines.delete(machineId);
        res.writeHead(403, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ ok: false, message: 'Machine limit reached' }));
      }

      const token = signToken({ email, licenseKey, machineId, exp: Date.now() + 1000 * 60 * 60 * 24 * 30 });
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ ok: true, token, message: 'Activated', expiresAt: null }));
    } catch {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ ok: false, message: 'Bad request' }));
    }
  }

  if (req.method === 'GET' && req.url.startsWith('/api/download?token=')) {
    const token = new URL(req.url, `http://localhost:${PORT}`).searchParams.get('token');
    const payload = token ? verifyToken(token) : null;
    if (!payload) {
      res.writeHead(403, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ ok: false, message: 'Invalid or expired token' }));
    }
    res.writeHead(302, { Location: DMG_URL });
    return res.end();
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ ok: false, message: 'Not found' }));
});

server.listen(PORT, () => {
  console.log(`Server on http://localhost:${PORT}`);
});
