#!/bin/bash
# LocalClaw Installation Script

clear
echo "=========================================="
echo "  LocalClaw Installation"
echo "=========================================="

rm -f /tmp/localclaw_status
touch /tmp/localclaw_status

echo ""
echo "[1/7] Installing Homebrew..."
if command -v brew &>/dev/null; then
    echo "  ✓ Already installed"
    echo "homebrew:OK" >> /tmp/localclaw_status
else
    echo "  → Installing (requires password)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    echo "homebrew:OK" >> /tmp/localclaw_status
fi

INSTALL_LM_STUDIO_PLACEHOLDER

echo ""
echo "[4/7] Installing Node.js..."
if command -v node &>/dev/null && node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)' &>/dev/null; then
    echo "  ✓ Node $(node --version) ready"
    echo "node:OK" >> /tmp/localclaw_status
else
    echo "  → Installing/upgrading Node.js 22.19+..."
    brew upgrade node || brew install node
    if ! command -v node &>/dev/null || ! node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)' &>/dev/null; then
        echo "  ✗ Node 22.19+ is required for OpenClaw"
        echo "node:FAIL" >> /tmp/localclaw_status
        exit 1
    fi
    echo "node:OK" >> /tmp/localclaw_status
fi

echo ""
echo "[5/7] Installing OpenClaw..."
if command -v openclaw &>/dev/null; then
    echo "  ✓ Already installed"
    echo "openclaw:OK" >> /tmp/localclaw_status
else
    echo "  → Installing..."
    npm i -g openclaw@latest
    echo "openclaw:OK" >> /tmp/localclaw_status
fi

echo ""
echo "[6/7] Configuring OpenClaw..."
mkdir -p ~/.openclaw

# Generate token
GATEWAY_TOKEN=$(openssl rand -hex 32 2>/dev/null || dd if=/dev/urandom bs=32 count=1 2>/dev/null | xxd -p | tr -d '\n' || echo "$(date +%s)$(uuidgen | tr -d '-')" | md5)
export GATEWAY_TOKEN
echo "$GATEWAY_TOKEN" > /tmp/localclaw_token

# Merge config without wiping existing channels/accounts.
export OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
export LOCALCLAW_MODEL_ID="MODEL_PLACEHOLDER"
node <<'NODE'
const fs = require("fs");
const path = process.env.OPENCLAW_CONFIG;
let config = {};
try {
  if (fs.existsSync(path)) config = JSON.parse(fs.readFileSync(path, "utf8"));
} catch {}
config.gateway = {
  ...(config.gateway || {}),
  mode: "local",
  port: 18789,
  bind: "loopback",
  auth: {
    ...((config.gateway && config.gateway.auth) || {}),
    mode: "token",
    token: process.env.GATEWAY_TOKEN || ""
  }
};
config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = {
  ...(config.agents.defaults.model || {}),
  primary: process.env.LOCALCLAW_MODEL_ID || ""
};
fs.writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
NODE

# Create agent directory and auth file BEFORE starting gateway
mkdir -p ~/.openclaw/agents/main/agent
API_KEY_PLACEHOLDER

echo "  ✓ Config saved with token"
echo "config:OK" >> /tmp/localclaw_status

echo ""
echo "[7/7] Installing Gateway service and starting..."
DOCTOR_LOG=/tmp/localclaw_doctor.log
if ! openclaw --no-color doctor --fix --yes --non-interactive > "$DOCTOR_LOG" 2>&1; then
    cat "$DOCTOR_LOG"
    echo "  ✗ OpenClaw doctor repair failed"
    echo "service:FAIL" >> /tmp/localclaw_status
    touch /tmp/localclaw_install_done
    exit 1
fi
cat "$DOCTOR_LOG"

REGISTRY_LOG=/tmp/localclaw_plugin_registry.json
if ! openclaw --no-color plugins registry --refresh --json > "$REGISTRY_LOG" 2>&1; then
    echo "  ✗ OpenClaw plugin registry refresh failed"
    echo "service:FAIL" >> /tmp/localclaw_status
    touch /tmp/localclaw_install_done
    exit 1
fi

if ! node <<'NODE'
const fs = require("fs");
const path = require("path");
const legacyPath = path.join(process.env.HOME, ".openclaw/plugins/installs.json");
const output = fs.readFileSync("/tmp/localclaw_plugin_registry.json", "utf8");
const starts = [...output.matchAll(/[\[{]/g)].map(match => match.index);
let registry = null;
for (const start of starts) {
  try {
    registry = JSON.parse(output.slice(start));
    break;
  } catch {}
}
if (!registry) throw new Error("Plugin registry JSON was not found");

function archive(sourcePath) {
  let migratedPath = `${sourcePath}.migrated`;
  let suffix = 2;
  while (fs.existsSync(migratedPath)) migratedPath = `${sourcePath}.migrated.${suffix++}`;
  fs.renameSync(sourcePath, migratedPath);
  return migratedPath;
}

if (fs.existsSync(legacyPath)) {
  const legacy = JSON.parse(fs.readFileSync(legacyPath, "utf8"));
  const oldRecords = legacy.installRecords || {};
  const currentRecords = (registry.persisted || registry).installRecords || {};
  const recordIds = Object.keys(oldRecords);

  for (const id of recordIds) {
    const oldRecord = oldRecords[id];
    const currentRecord = currentRecords[id];
    if (!currentRecord || oldRecord.source !== currentRecord.source) {
      throw new Error(`Plugin metadata is not safely reconciled for ${id}`);
    }
    if (oldRecord.source === "npm" && oldRecord.resolvedName !== currentRecord.resolvedName) {
      throw new Error(`Plugin package identity changed for ${id}`);
    }
  }

  const migratedPath = archive(legacyPath);
  console.log(`  ✓ Archived reconciled legacy plugin metadata: ${path.basename(migratedPath)}`);
}

const doctorOutput = fs.readFileSync("/tmp/localclaw_doctor.log", "utf8");
const warning = /Left Codex binding sidecar in place because its session is owned by agent harness [^:\n]+:\s+([^\n]+\.jsonl\.codex-app-server\.json)/g;
const allowedRoot = path.resolve(process.env.HOME, ".openclaw/agents") + path.sep;
for (const match of doctorOutput.matchAll(warning)) {
  const sourcePath = path.resolve(match[1].trim());
  if (!sourcePath.startsWith(allowedRoot) || !sourcePath.endsWith(".jsonl.codex-app-server.json")) {
    throw new Error(`Unsafe Codex binding sidecar path: ${sourcePath}`);
  }
  const sidecar = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
  if (typeof sidecar.sessionFile !== "string") throw new Error(`Invalid Codex binding sidecar: ${sourcePath}`);
  archive(sourcePath);
  console.log(`  ✓ Archived stale Codex binding metadata: ${path.basename(sourcePath)}`);
}
NODE
then
    echo "  ✗ Legacy plugin metadata could not be reconciled safely"
    echo "service:FAIL" >> /tmp/localclaw_status
    touch /tmp/localclaw_install_done
    exit 1
fi

if ! openclaw --no-color doctor --fix --yes --non-interactive 2>&1; then
    echo "  ✗ OpenClaw post-migration repair failed"
    echo "service:FAIL" >> /tmp/localclaw_status
    touch /tmp/localclaw_install_done
    exit 1
fi

if ! openclaw gateway install --force 2>&1 || ! openclaw gateway restart 2>&1; then
    echo "  ✗ Gateway service installation failed"
    echo "service:FAIL" >> /tmp/localclaw_status
    touch /tmp/localclaw_install_done
    exit 1
fi

echo ""
echo "→ Checking Gateway status..."
GATEWAY_READY=0
for attempt in 1 2 3 4 5 6 7 8; do
    if openclaw gateway status --json --require-rpc --timeout 5000 > /tmp/localclaw_gateway_status.json 2>&1; then
        GATEWAY_READY=1
        break
    fi
    sleep 1
done

if [ "$GATEWAY_READY" = "1" ]; then
    echo "  ✓ Gateway is running"
    echo "  ✓ Dashboard: http://localhost:18789"
    echo "service:OK" >> /tmp/localclaw_status
else
    echo "  ✗ Gateway failed to start"
    cat /tmp/localclaw_gateway_status.json
    echo "service:FAIL" >> /tmp/localclaw_status
    touch /tmp/localclaw_install_done
    exit 1
fi

echo "done" >> /tmp/localclaw_status
touch /tmp/localclaw_install_done

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "Gateway URL: http://localhost:18789"
echo "Dashboard: http://localhost:18789/dashboard"
echo ""
read -p "Press Enter to close..."
