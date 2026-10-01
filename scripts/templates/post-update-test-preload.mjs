import assert from "node:assert/strict";
import childProcess from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import os from "node:os";

// sandbox-exec cannot let /bin/ps inspect even its own process. OpenClaw 9.6
// uses that result as its update-driver identity. Supply only the fixture's own
// identity; every other process inspection keeps the sandbox's normal behavior.
assert.ok(process.argv.includes("repair"));
assert.ok(process.env.HOME?.startsWith("/private/tmp/localclaw-post-update-"));
assert.ok(process.env.OPENCLAW_STATE_DIR?.startsWith(process.env.HOME + "/"));
const originalExecFileSync = childProcess.execFileSync;
const account = os.userInfo();
os.userInfo = () => ({ ...account, homedir: process.env.HOME });
const fixtureStartTime = new Date().toUTCString() + "\n";
childProcess.execFileSync = function (file, args, options) {
  if (file === "/bin/ps" && Array.isArray(args) && args.join(" ") === `-o lstart= -p ${process.pid}`) {
    return fixtureStartTime;
  }
  return originalExecFileSync.call(this, file, args, options);
};
syncBuiltinESMExports();
