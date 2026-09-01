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

export function findOpenClawDist() {
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

export async function loadController() {
  const dist = findOpenClawDist();
  if (!dist) throw new Error("OpenClaw runtime not found. Update or repair OpenClaw first.");

  // Bundler import order and chunk hashes are not an API. Locate the small
  // session module by its complete contract, then verify its actual exports.
  const names = ["getSessionGoal", "createSessionGoal", "updateSessionGoalStatus",
    "updateSessionGoalObjective", "clearSessionGoal"];
  const goalModuleName = readdirSync(dist).filter(
    (name) => /^sessions-[\w-]+\.js$/.test(name),
  ).find((name) => {
    const source = readFileSync(join(dist, name), "utf8");
    return names.every((name) => source.includes(`function ${name}(`));
  });
  if (!goalModuleName) throw new Error("OpenClaw Goal controller could not be located.");

  const accessorModuleName = readdirSync(dist).filter(
    (name) => /^session-accessor-[\w-]+\.js$/.test(name),
  ).find((name) => {
    const source = readFileSync(join(dist, name), "utf8");
    return source.includes("async function mutateSessionGoal(") &&
      source.includes("SessionGoalOperationError = class");
  });
  if (!accessorModuleName) {
    throw new Error("OpenClaw's atomic Goal mutation controller could not be located.");
  }

  const [goalModule, accessorModule, storeModule] = await Promise.all([
    import(pathToFileURL(join(dist, goalModuleName)).href),
    import(pathToFileURL(join(dist, accessorModuleName)).href),
    import(pathToFileURL(join(dist, "plugin-sdk/session-store-runtime.js")).href),
  ]);

  const functions = Object.fromEntries(
    names.map((name) => [name, findNamedFunction(goalModule, name)]),
  );
  const missing = Object.entries(functions)
    .filter(([, value]) => typeof value !== "function")
    .map(([name]) => name);
  if (missing.length) throw new Error(`OpenClaw Goal API is incomplete: ${missing.join(", ")}`);
  const mutateSessionGoal = findNamedFunction(accessorModule, "mutateSessionGoal");
  const lookupSessionGoalOperation = findNamedFunction(accessorModule, "lookupSessionGoalOperation");
  if (typeof mutateSessionGoal !== "function" || typeof lookupSessionGoalOperation !== "function") {
    throw new Error("OpenClaw's atomic Goal mutation API is unavailable.");
  }

  return {
    ...functions,
    mutateSessionGoal,
    lookupSessionGoalOperation,
    getSessionEntry: storeModule.getSessionEntry,
    patchSessionEntry: storeModule.patchSessionEntry,
    resolveStorePath: storeModule.resolveStorePath,
  };
}

export async function handleRequest(controller, request) {
  const id = typeof request.id === "string" ? request.id : randomUUID();
  const sessionKey = typeof request.sessionKey === "string" ? request.sessionKey.trim() : "";
  const action = typeof request.action === "string" ? request.action.trim() : "status";
  const agentId = /^agent:([a-z0-9][a-z0-9_-]*):explicit:[\w-]+$/.exec(sessionKey)?.[1];
  if (!agentId) {
    throw new Error("Invalid LocalClaw Goal session.");
  }

  const storePath = controller.resolveStorePath(undefined, { agentId });
  const options = { sessionKey, agentId, storePath };
  const requestedGoalId = typeof request.goalId === "string" ? request.goalId.trim() : "";
  const expectedUpdatedAt = Number.isSafeInteger(request.expectedUpdatedAt)
    ? request.expectedUpdatedAt
    : null;
  const operationId = typeof request.operationId === "string" && request.operationId.trim()
    ? request.operationId.trim()
    : id;
  const issuedAtMs = Number.isSafeInteger(request.issuedAtMs)
    ? request.issuedAtMs
    : Date.now();
  let goal;
  let message = "";

  const ensureSessionEntry = async () => {
    let entry = controller.getSessionEntry({ agentId, sessionKey, storePath });
    if (entry) return entry;
    const fallbackEntry = { sessionId: randomUUID(), updatedAt: Date.now() };
    await controller.patchSessionEntry({
      agentId,
      sessionKey,
      storePath,
      fallbackEntry,
      update: () => ({}),
    });
    entry = controller.getSessionEntry({ agentId, sessionKey, storePath });
    if (!entry?.sessionId) throw new Error("The Goal session could not be initialized safely.");
    return entry;
  };

  const mutateAtomically = async (operation) => {
    if (operation.action !== "start") {
      if (!requestedGoalId) throw new Error("Refresh the Goal before changing it; its identity is required.");
      if (expectedUpdatedAt === null) {
        throw new Error("Refresh the Goal before changing it; its revision is required.");
      }
    }
    const entry = await ensureSessionEntry();
    const requestFingerprint = JSON.stringify({
      action: operation.action,
      agentId,
      sessionKey,
      goalId: operation.goalId ?? null,
      objective: operation.objective ?? null,
      note: operation.note ?? null,
      tokenBudget: operation.tokenBudget ?? null,
    });
    const durableOperation = {
      operationId,
      issuedAtMs,
      requestFingerprint,
      ...operation,
    };
    const receipt = controller.lookupSessionGoalOperation({
      ...options,
      expectedSessionId: entry.sessionId,
      operation: durableOperation,
    });
    if (receipt) return { result: receipt, replayed: true };

    const assertCurrent = requestedGoalId && expectedUpdatedAt !== null
      ? () => {
          const latestEntry = controller.getSessionEntry({ agentId, sessionKey, storePath });
          const latestGoal = latestEntry?.goal;
          if (!latestGoal || latestGoal.id !== requestedGoalId) {
            throw new Error("This Goal was replaced or cleared before the update committed. The stale action was rejected.");
          }
          if (latestGoal.updatedAt !== expectedUpdatedAt) {
            throw new Error("This Goal changed before the update committed. The stale revision was rejected.");
          }
        }
      : undefined;
    return controller.mutateSessionGoal({
      ...options,
      expectedSessionId: entry.sessionId,
      ...(assertCurrent ? { assertCurrent } : {}),
      operation: durableOperation,
    });
  };

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
      if (objective.length > 16_000) throw new Error("The goal objective cannot exceed 16,000 characters.");
      const committed = await mutateAtomically({
        action: "start",
        objective,
        ...(Number.isInteger(request.tokenBudget) && request.tokenBudget > 0
          ? { tokenBudget: request.tokenBudget }
          : {}),
      });
      goal = committed.result.goal;
      message = committed.replayed
        ? "Goal creation receipt replayed safely."
        : "Goal created atomically without using model tokens.";
      break;
    }
    case "edit": {
      const objective = typeof request.objective === "string" ? request.objective.trim() : "";
      if (!objective) throw new Error("The goal objective cannot be empty.");
      if (objective.length > 16_000) throw new Error("The goal objective cannot exceed 16,000 characters.");
      const committed = await mutateAtomically({ action: "edit", goalId: requestedGoalId, objective });
      goal = committed.result.goal;
      message = committed.replayed ? "Goal edit receipt replayed safely." : "Goal objective updated atomically.";
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
      if (note.length > 2_000) throw new Error("A Goal status note cannot exceed 2,000 characters.");
      const committed = await mutateAtomically({
        action,
        goalId: requestedGoalId,
        ...(note ? { note } : {}),
      });
      goal = committed.result.goal;
      message = committed.replayed ? `Goal ${status} receipt replayed safely.` : `Goal ${status} atomically.`;
      break;
    }
    case "clear": {
      const committed = await mutateAtomically({ action: "clear", goalId: requestedGoalId });
      message = committed.replayed ? "Goal clear receipt replayed safely." : "Goal cleared atomically.";
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

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) main().catch((error) => {
  process.stdout.write(`${JSON.stringify({
    type: "ready",
    ok: false,
    message: error instanceof Error ? error.message : String(error),
  })}\n`);
  process.exit(1);
});
