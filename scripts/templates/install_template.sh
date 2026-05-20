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
openclaw gateway stop 2>/dev/null || true
sleep 1
openclaw gateway uninstall 2>/dev/null || true
sleep 1
openclaw gateway install 2>&1
sleep 2
openclaw gateway start 2>&1 &
sleep 6

echo ""
echo "→ Checking Gateway status..."
STATUS=$(openclaw gateway status 2>&1)
echo "  $STATUS"
if echo "$STATUS" | grep -q -E "(running|Online)"; then
    echo "  ✓ Gateway is running"
    echo "  ✓ Dashboard: http://localhost:18789"
    echo "service:OK" >> /tmp/localclaw_status
else
    echo "  ✗ Gateway failed to start"
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
