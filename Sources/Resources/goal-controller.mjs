import { randomUUID } from "node:crypto";
import {
  existsSync,
  readFileSync,
  readdirSync,
  realpathSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import readline from "node:readline";

function findOpenClawDist() {
  const explicit = process.env.OPENCLAW_DIST_DIR?.trim();
  const candidates = explicit ? [explicit] : [];

  for (const directory of (process.env.PATH ?? "").split(":")) {
    if (!directory) continue;
    const executable = join(directory, "openclaw");
    if (!existsSync(executable)) continue;
    try {
      const resolved = realpathSync(executable);
      candidates.push(join(dirname(resolved), "dist"));
      candidates.push(join(dirname(dirname(resolved)), "dist"));
    } catch {
      // Keep checking the known global installation paths below.
    }
  }

  candidates.push(
    "/opt/homebrew/lib/node_modules/openclaw/dist",
    "/usr/local/lib/node_modules/openclaw/dist",
    join(homedir(), ".npm-global/lib/node_modules/openclaw/dist"),
  );

  return candidates.find((candidate) =>
    existsSync(join(candidate, "plugin-sdk/session-store-runtime.js")),
  );
}

function findNamedFunction(module, name) {
  return Object.values(module).find(
    (value) => typeof value === "function" && value.name === name,
  );
}

function goalSnapshot(goal) {
  if (!goal) return null;
  return {
    id: goal.id,
    objective: goal.objective,
    status: goal.status,
    createdAt: goal.createdAt,
    updatedAt: goal.updatedAt,
    tokensUsed: goal.tokensUsed ?? 0,
    tokenBudget: goal.tokenBudget ?? null,
    continuationTurns: goal.continuationTurns ?? 0,
    lastStatusNote: goal.lastStatusNote ?? null,
  };
}

async function loadController() {
  const dist = findOpenClawDist();
  if (!dist) throw new Error("OpenClaw runtime not found. Update or repair OpenClaw first.");

  const embeddedFile = readdirSync(dist).find(
    (name) => name.startsWith("embedded-backend-") && name.endsWith(".js"),
  );
  if (!embeddedFile) throw new Error("This OpenClaw version does not expose Goal control.");

  const source = readFileSync(join(dist, embeddedFile), "utf8");
  const goalModuleName = source.match(
    /clearSessionGoal[^\n]+from "\.\/(sessions-[^"]+\.js)"/,
  )?.[1];
  if (!goalModuleName) throw new Error("OpenClaw Goal controller could not be located.");

  const [goalModule, storeModule] = await Promise.all([
    import(pathToFileURL(join(dist, goalModuleName)).href),
    import(pathToFileURL(join(dist, "plugin-sdk/session-store-runtime.js")).href),
  ]);

  const functions = Object.fromEntries(
    [
      "getSessionGoal",
      "createSessionGoal",
      "updateSessionGoalStatus",
      "updateSessionGoalObjective",
      "clearSessionGoal",
    ].map((name) => [name, findNamedFunction(goalModule, name)]),
  );
  const missing = Object.entries(functions)
    .filter(([, value]) => typeof value !== "function")
    .map(([name]) => name);
  if (missing.length) throw new Error(`OpenClaw Goal API is incomplete: ${missing.join(", ")}`);

  return {
    ...functions,
    getSessionEntry: storeModule.getSessionEntry,
    storePath: storeModule.resolveStorePath(undefined, { agentId: "main" }),
  };
}

async function handleRequest(controller, request) {
  const id = typeof request.id === "string" ? request.id : randomUUID();
  const sessionKey = typeof request.sessionKey === "string" ? request.sessionKey.trim() : "";
  const action = typeof request.action === "string" ? request.action.trim() : "status";
  if (!sessionKey.startsWith("agent:main:explicit:")) {
    throw new Error("Invalid LocalClaw Goal session.");
  }

  const options = { sessionKey, storePath: controller.storePath };
  let goal;
  let message = "";

  switch (action) {
    case "status": {
      const result = await controller.getSessionGoal({ ...options, persist: true });
      goal = result.goal;
      message = goal ? "Goal status refreshed." : "No goal for this discussion.";
      break;
    }
    case "start": {
      const objective = typeof request.objective === "string" ? request.objective.trim() : "";
      if (!objective) throw new Error("Describe the goal before starting it.");
      const entry = controller.getSessionEntry({
        agentId: "main",
        sessionKey,
        storePath: controller.storePath,
      });
      goal = await controller.createSessionGoal({
        ...options,
        objective,
        ...(Number.isInteger(request.tokenBudget) && request.tokenBudget > 0
          ? { tokenBudget: request.tokenBudget }
          : {}),
        fallbackEntry: entry ?? { sessionId: randomUUID(), updatedAt: Date.now() },
      });
      message = "Goal created without using model tokens.";
      break;
    }
    case "edit": {
      const objective = typeof request.objective === "string" ? request.objective.trim() : "";
      if (!objective) throw new Error("The goal objective cannot be empty.");
      goal = await controller.updateSessionGoalObjective({ ...options, objective });
      message = "Goal objective updated.";
      break;
    }
    case "pause":
    case "resume":
    case "complete":
    case "block": {
      const status = action === "resume"
        ? "active"
        : action === "pause"
          ? "paused"
          : action === "block"
            ? "blocked"
            : action;
      const note = typeof request.note === "string" ? request.note.trim() : "";
      goal = await controller.updateSessionGoalStatus({
        ...options,
        status,
        ...(note ? { note } : {}),
      });
      message = `Goal ${status}.`;
      break;
    }
    case "clear": {
      const removed = await controller.clearSessionGoal(options);
      message = removed ? "Goal cleared." : "No goal to clear.";
      goal = null;
      break;
    }
    default:
      throw new Error(`Unsupported Goal action: ${action}`);
  }

  return { type: "response", id, ok: true, message, goal: goalSnapshot(goal) };
}

async function main() {
  const controller = await loadController();
  process.stdout.write(`${JSON.stringify({ type: "ready", ok: true })}\n`);

  const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  let idleTimer;
  const resetIdleTimer = () => {
    clearTimeout(idleTimer);
    idleTimer = setTimeout(() => process.exit(0), 120_000);
    idleTimer.unref?.();
  };
  resetIdleTimer();

  for await (const line of input) {
    resetIdleTimer();
    if (!line.trim()) continue;
    let request;
    try {
      request = JSON.parse(line);
      const response = await handleRequest(controller, request);
      process.stdout.write(`${JSON.stringify(response)}\n`);
    } catch (error) {
      process.stdout.write(`${JSON.stringify({
        type: "response",
        id: request?.id ?? "",
        ok: false,
        message: error instanceof Error ? error.message : String(error),
        goal: null,
      })}\n`);
    }
  }
}

main().catch((error) => {
  process.stdout.write(`${JSON.stringify({
    type: "ready",
    ok: false,
    message: error instanceof Error ? error.message : String(error),
  })}\n`);
  process.exit(1);
});
