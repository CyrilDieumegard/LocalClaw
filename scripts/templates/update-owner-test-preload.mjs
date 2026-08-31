import assert from "node:assert/strict";
import os from "node:os";
import { syncBuiltinESMExports } from "node:module";

// Test-only OS account fixture. Never preload this in a mutating CLI invocation.
assert.ok(process.argv.includes("--dry-run"));
assert.ok(process.env.HOME.startsWith("/private/tmp/localclaw-update-owner-"));
assert.equal(process.env.OPENCLAW_LAUNCHD_LABEL, "io.localclaw.update-ownership-fixture");
const account = os.userInfo();
os.userInfo = () => ({ ...account, homedir: process.env.HOME });
syncBuiltinESMExports();
