// Opt-in integration test: real npm update in a disposable prefix, never the host installation.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { once } from "node:events";
import { mkdirSync, readFileSync, writeFileSync, appendFileSync, realpathSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";

const root = realpathSync(process.argv[2]);
assert.ok(root.startsWith("/private/tmp/localclaw-full-migration-"));
const target = process.argv[3] ?? "2026.10.1";
assert.match(target, /^\d{4}\.\d+\.\d+$/);
const prefix = join(root, "prefix");
const pkg = join(prefix, "lib/node_modules/openclaw");
assert.ok(realpathSync(pkg).startsWith(root + "/"), "The fixture package must remain inside its disposable root.");
const cli = join(pkg, "openclaw.mjs");
const home = join(root, "home");
const state = join(home, ".openclaw");
const configPath = join(state, "openclaw.json");
const workspace = join(home, "workspace");
const evidence = join(root, "evidence");
for (const p of [state, workspace, evidence, join(root, "tmp")]) mkdirSync(p, {recursive: true});
assert.equal(JSON.parse(readFileSync(join(pkg, "package.json"))).version, "2026.9.7");
const controller = fileURLToPath(new URL("../Sources/Resources/goal-controller.mjs", import.meta.url));
const preload = join(root, "fixture-account.mjs");
writeFileSync(preload, `import os from 'node:os';
import {syncBuiltinESMExports} from 'node:module';
import assert from 'node:assert/strict';
assert.ok(process.env.HOME?.startsWith(${JSON.stringify(root + "/")}));
// Native update rehearsals deliberately select another disposable state.
assert.ok(process.env.OPENCLAW_STATE_DIR?.startsWith(${JSON.stringify(root + "/")}) ||
  /^\\/private\\/tmp\\/openclaw\\/openclaw-update-artifact-[A-Za-z0-9_-]+\\/state$/.test(process.env.OPENCLAW_STATE_DIR ?? ''));
const account=os.userInfo(); os.userInfo=()=>({...account,homedir:process.env.HOME});
syncBuiltinESMExports();\n`);
const env = {
  PATH: `${join(prefix,"bin")}:${dirname(process.execPath)}:/usr/bin:/bin:/usr/sbin:/sbin`,
  HOME: home, OPENCLAW_HOME: home, OPENCLAW_STATE_DIR: state, OPENCLAW_CONFIG_PATH: configPath,
  OPENCLAW_DIST_DIR: join(pkg,"dist"), OPENCLAW_NO_AUTO_UPDATE: "1",
  OPENCLAW_SUPERVISOR_MODE: "external", OPENCLAW_SERVICE_REPAIR_POLICY: "external",
  OPENCLAW_LAUNCHD_LABEL: "io.localclaw.full-migration-fixture",
  NPM_CONFIG_PREFIX: prefix, npm_config_prefix: prefix, npm_config_cache: join(root,"npm-cache"),
  npm_config_legacy_peer_deps: "true", TMPDIR: join(root,"tmp"), SQLITE_TMPDIR: join(root,"tmp"),
  XDG_CACHE_HOME: join(root,"cache"), NODE_COMPILE_CACHE: join(root,"compile-cache"),
  NODE_OPTIONS: `--import=${preload}`, NO_COLOR: "1",
};
async function run(name, args, {input, timeout=90000, executable=process.execPath}={}) {
  const stdoutPath = join(evidence,`${name}.stdout`);
  const stderrPath = join(evidence,`${name}.stderr`);
  writeFileSync(stdoutPath, ""); writeFileSync(stderrPath, "");
  const child = spawn(executable,args,{env,cwd:root,stdio:["pipe","pipe","pipe"]});
  let stdout="",stderr="";
  child.stdout.on("data",b=>{ stdout+=b; appendFileSync(stdoutPath,b); });
  child.stderr.on("data",b=>{ stderr+=b; appendFileSync(stderrPath,b); });
  child.stdin.end(input);
  const timer=setTimeout(()=>child.kill("SIGKILL"),timeout);
  const [code]=await once(child,"close");clearTimeout(timer);
  assert.equal(code,0,`${name}: exit ${code}\n${stdout.slice(-6000)}\n${stderr.slice(-3000)}`);
  console.log(`PASS ${name}`);return stdout;
}
function json(output) {
  try {return JSON.parse(output);} catch {}
  for(let start=output.indexOf("{");start>=0;start=output.indexOf("{",start+1)) {
    try {return JSON.parse(output.slice(start));} catch {}
  }
  throw new Error(`No JSON result: ${output.slice(-1000)}`);
}
async function goal(name, request) {
  const out=await run(name,[controller],{input:JSON.stringify({id:name,sessionKey:"agent:writer:explicit:migration-proof",...request})+"\n"});
  const values=out.split("\n").flatMap(line=>{try{return [JSON.parse(line)];}catch{return [];}});
  const response=values.find(v=>v.type==="response");assert.equal(response?.ok,true,out);return response;
}
function dbFacts() {
  const db=new DatabaseSync(join(state,"state/openclaw.sqlite"),{readOnly:true});
  const result={schema:db.prepare("PRAGMA user_version").get().user_version,integrity:db.prepare("PRAGMA integrity_check").get().integrity_check};db.close();return result;
}
let gateway;
let requests=0;
const server=createServer(async(req,res)=>{
  for await (const _ of req) {}
  requests++;
  res.writeHead(200,{"Content-Type":"text/event-stream"});
  const base={id:"migration-fixture",object:"chat.completion.chunk",created:1,model:"fixture"};
  res.write(`data: ${JSON.stringify({...base,choices:[{index:0,delta:{role:"assistant",content:"Migration preserved the local agent."},finish_reason:null}]})}\n\n`);
  res.end(`data: ${JSON.stringify({...base,choices:[{index:0,delta:{},finish_reason:"stop"}]})}\n\ndata: [DONE]\n\n`);
});
try {
  await run("old-postinstall",[join(pkg,"scripts/postinstall-bundled-plugins.mjs")]);
  server.listen(0,"127.0.0.1");await once(server,"listening");
  const probe=createServer();probe.listen(0,"127.0.0.1");await once(probe,"listening");
  const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
  writeFileSync(configPath,JSON.stringify({
    gateway:{mode:"local",bind:"loopback",port,auth:{mode:"token",token:"localclaw-migration-test-only"}},
    agents:{ownership:"explicit",entries:{writer:{}},defaults:{workspace,systemAgent:{agentId:"writer"},model:{primary:"lmstudio/fixture"},models:{"lmstudio/fixture":{agentRuntime:{id:"openclaw"}}}}},
    models:{providers:{lmstudio:{baseUrl:`http://127.0.0.1:${server.address().port}/v1`,apiKey:"fixture-only",api:"openai-completions",models:[{id:"fixture",name:"Fixture",contextWindow:32768,maxTokens:4096,reasoning:false,input:["text"],cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}]}}},
    tools:{allow:["read","write"]},
  }));
  writeFileSync(join(workspace,"preserve.txt"),"user workspace fixture\n");
  await run("old-doctor",[cli,"doctor","--fix","--yes","--non-interactive"],{timeout:180000});
  await run("old-config",[cli,"config","validate","--json"]);
  await run("old-credential",[cli,"models","auth","paste-api-key","--agent","writer","--provider","lmstudio"],{input:"migration-fixture-not-a-secret\n"});
  const originalGoal=await goal("old-goal",{action:"start",objective:"Preserve this Goal through the update",tokenBudget:5000});
  const before=dbFacts();assert.equal(before.schema,19);assert.equal(before.integrity,"ok");
  await run("verified-backup",[cli,"backup","create","--no-include-workspace","--verify","--output",join(root,`before-update-${Date.now()}.tar.gz`),"--json"]);
  // Match LocalClaw: service repair is external, but core self-update is allowed.
  delete env.OPENCLAW_SUPERVISOR_MODE;
  const update=await run("native-update",[cli,"update","--tag",target,"--yes","--json","--no-restart","--timeout","600"],{timeout:660000});
  const receipt=json(update);writeFileSync(join(evidence,"update-result.json"),JSON.stringify(receipt,null,2));
  assert.ok(["ok","warning"].includes(receipt.status));
  if (process.env.LOCALCLAW_MIGRATION_CHECK_BINARY) {
    const parsed=json(await run("localclaw-receipt",["--check-update-output",join(evidence,"update-result.json")],{
      executable:realpathSync(process.env.LOCALCLAW_MIGRATION_CHECK_BINARY),
    }));
    assert.equal(parsed.ok,true);
    assert.equal(parsed.mode,"npm");
    assert.equal(parsed.pluginRepairPending,false);
    assert.equal(parsed.needsPluginApproval,false);
    if(receipt.postUpdate?.plugins?.status === "warning") assert.equal(parsed.requiresAdvisoryVerification,true);
  }
  assert.equal(JSON.parse(readFileSync(join(pkg,"package.json"))).version,target);
  const doctor=json(await run("new-doctor",[cli,"doctor","--post-upgrade","--json"],{timeout:180000}));
  assert.deepEqual(doctor.findings,[]);
  for(const probe of ["plugin.index_unavailable","plugin.entry_unresolved","plugin.manifest_unavailable","plugin.manifest_drift","plugin.version_drift"]) {
    assert.ok(doctor.probesRun.includes(probe),probe);
  }
  const database=new DatabaseSync(join(state,"state/openclaw.sqlite"),{readOnly:true});
  try {
    assert.equal(database.prepare("SELECT COUNT(*) AS pending FROM migration_runs WHERE id LIKE 'deferred-plugin-migration:%' AND status = 'pending'").get().pending,0);
  } finally { database.close(); }
  await run("new-config",[cli,"config","validate","--json"]);
  const after=dbFacts();assert.equal(after.schema,20);assert.equal(after.integrity,"ok");
  const kept=await goal("new-goal",{action:"status"});assert.equal(kept.goal.id,originalGoal.goal.id);assert.equal(kept.goal.objective,originalGoal.goal.objective);
  const auth=json(await run("new-credential-status",[cli,"models","status","--agent","writer","--json"]));
  assert.ok(auth.auth.providers.some(p=>p.provider==="lmstudio"&&p.profiles.apiKey>0));
  assert.equal(readFileSync(join(workspace,"preserve.txt"),"utf8"),"user workspace fixture\n");
  gateway=spawn(process.execPath,[cli,"gateway","run","--port",String(port)],{env,cwd:root,stdio:["ignore","pipe","pipe"]});
  let gatewayLog="";gateway.stdout.on("data",b=>gatewayLog+=b);gateway.stderr.on("data",b=>gatewayLog+=b);
  let ready=false;
  for(let i=0;i<90;i++) {try {const r=await fetch(`http://127.0.0.1:${port}/healthz`);if(r.ok){ready=true;break;}}catch{} await new Promise(r=>setTimeout(r,500));}
  assert.ok(ready,gatewayLog);
  for(let i=1;i<=2;i++) await run(`gateway-health-${i}`,[cli,"health","--json"]);
  const chat=await run("post-migration-chat",[cli,"agent","--agent","writer","--session-id","localclaw-migration-chat","--message","Confirm migration fixture","--json"],{timeout:90000});
  assert.ok(chat.includes("Migration preserved the local agent."),chat);assert.ok(requests>0);
  writeFileSync(join(evidence,"gateway.log"),gatewayLog);
  writeFileSync(join(evidence,"summary.json"),JSON.stringify({from:"2026.9.7",to:target,before,after,goalPreserved:true,credentialPreserved:true,workspacePreserved:true,verifiedBackup:true,gatewayHealthChecks:2,chatPassed:true,modelRequests:requests},null,2));
  console.log("PASS complete native update, schema 19 -> 20, preserved Goal/credentials/workspace, restarted Gateway, two health checks and chat");
} finally {
  if(gateway&&gateway.exitCode===null){gateway.kill("SIGTERM");await Promise.race([once(gateway,"close"),new Promise(r=>setTimeout(r,10000))]);if(gateway.exitCode===null)gateway.kill("SIGKILL");}
  server.closeAllConnections();await new Promise(r=>server.close(r));
}
