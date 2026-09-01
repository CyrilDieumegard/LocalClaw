import assert from "node:assert/strict";
import { handleRequest } from "../Sources/Resources/goal-controller.mjs";

const sessionKey = "agent:writer:explicit:localclaw-goal-contract";
let entry = {
  sessionId: "fixture-session",
  updatedAt: 1,
  goal: {
    id: "fixture-goal",
    objective: "Original objective",
    status: "active",
    createdAt: 1,
    updatedAt: 1,
    tokensUsed: 0,
    continuationTurns: 0,
  },
};
const receipts = new Map();

const clone = (value) => value == null ? value : structuredClone(value);
const controller = {
  resolveStorePath: () => "/fixture/openclaw-agent.sqlite",
  getSessionEntry: () => clone(entry),
  patchSessionEntry: async () => clone(entry),
  getSessionGoal: async () => ({ goal: clone(entry?.goal ?? null) }),
  lookupSessionGoalOperation: (options) => {
    const previous = receipts.get(options.operation.operationId);
    if (!previous) return undefined;
    assert.equal(previous.fingerprint, options.operation.requestFingerprint);
    return clone(previous.result);
  },
  mutateSessionGoal: async (options) => {
    if (options.operation.operationId === "different-operation") {
      entry.goal.objective = "External edit";
      entry.goal.updatedAt += 1;
    }
    options.assertCurrent?.();
    const previous = receipts.get(options.operation.operationId);
    if (previous) {
      assert.equal(previous.fingerprint, options.operation.requestFingerprint);
      return { result: clone(previous.result), replayed: true };
    }
    assert.equal(options.expectedSessionId, entry.sessionId);
    const operation = options.operation;
    if (operation.action === "clear") {
      entry.goal = null;
    } else if (operation.action === "edit") {
      entry.goal.objective = operation.objective;
      entry.goal.updatedAt += 1;
    } else {
      const status = operation.action === "resume" ? "active"
        : operation.action === "pause" ? "paused"
          : operation.action === "block" ? "blocked" : operation.action;
      entry.goal.status = status;
      entry.goal.lastStatusNote = operation.note ?? null;
      entry.goal.updatedAt += 1;
    }
    const result = { goal: clone(entry.goal) };
    receipts.set(operation.operationId, {
      fingerprint: operation.requestFingerprint,
      result: clone(result),
    });
    return { result, replayed: false, sessionEntry: clone(entry) };
  },
};

const edit = {
  id: "edit-response",
  operationId: "durable-edit-operation",
  issuedAtMs: 10,
  action: "edit",
  sessionKey,
  goalId: "fixture-goal",
  expectedUpdatedAt: 1,
  objective: "Committed objective",
};
const first = await handleRequest(controller, edit);
assert.equal(first.ok, true);
assert.equal(first.goal.objective, "Committed objective");
const replay = await handleRequest(controller, edit);
assert.match(replay.message, /replayed safely/i);
assert.equal(replay.goal.updatedAt, first.goal.updatedAt);

// A different stale operation must never be accepted merely because another
// actor happened to commit the same requested post-state.
await assert.rejects(
  handleRequest(controller, {
    ...edit,
    id: "coincident-state-response",
    operationId: "coincident-state-operation",
    expectedUpdatedAt: 1,
    objective: "Committed objective",
  }),
  /stale revision was rejected/i,
);
assert.equal(entry.goal.updatedAt, first.goal.updatedAt);

await assert.rejects(
  handleRequest(controller, {
    ...edit,
    id: "stale-response",
    operationId: "different-operation",
    expectedUpdatedAt: first.goal.updatedAt,
    objective: "Stale overwrite",
  }),
  /stale revision was rejected/i,
);
assert.equal(entry.goal.objective, "External edit");

const clear = {
  id: "clear-response",
  operationId: "durable-clear-operation",
  issuedAtMs: 20,
  action: "clear",
  sessionKey,
  goalId: "fixture-goal",
  expectedUpdatedAt: entry.goal.updatedAt,
};
const cleared = await handleRequest(controller, clear);
assert.equal(cleared.goal, null);
const clearReplay = await handleRequest(controller, clear);
assert.match(clearReplay.message, /replayed safely/i);

console.log("PASS Goal atomic revision guard and durable lost-response replay");
