#!/usr/bin/env node
import { spawn } from "node:child_process";
import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.join(__dirname, "stdio-fixture-server.mjs");
const failureModes = ["malformed-json", "mismatched-id", "invalid-schema", "timeout"];

const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const key = process.argv[index];
  const value = process.argv[index + 1];
  if (key.startsWith("--")) {
    args.set(key.slice(2), value || "");
    index += 1;
  }
}

const mode = args.get("mode") || "success";
const expectFailure = args.has("expect-failure");
if (mode !== "success" && !failureModes.includes(mode)) {
  throw new Error(`Unknown smoke mode: ${mode}`);
}
let nextID = 1;

const child = spawn(process.execPath, [serverPath], {
  env: {
    ...process.env,
    SUISUI_MCP_FIXTURE_MODE: mode,
  },
  stdio: ["pipe", "pipe", "pipe"],
});

const lines = [];
const waiters = [];
const rl = readline.createInterface({ input: child.stdout });

rl.on("line", (line) => {
  const waiter = waiters.shift();
  if (waiter) {
    waiter.resolve(line);
  } else {
    lines.push(line);
  }
});

child.stderr.on("data", (chunk) => {
  process.stderr.write(chunk);
});

function nextLine(timeoutMs = 1000) {
  if (lines.length > 0) {
    return Promise.resolve(lines.shift());
  }

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      const index = waiters.findIndex((waiter) => waiter.resolve === resolve);
      if (index !== -1) {
        waiters.splice(index, 1);
      }
      reject(new Error("Timed out waiting for JSON-RPC response."));
    }, timeoutMs);

    waiters.push({
      resolve: (line) => {
        clearTimeout(timer);
        resolve(line);
      },
      reject,
    });
  });
}

async function request(method, params = undefined) {
  const id = nextID;
  nextID += 1;
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  const line = await nextLine();
  let response;
  try {
    response = JSON.parse(line);
  } catch {
    throw new Error("Malformed JSON-RPC response.");
  }

  if (response.jsonrpc !== "2.0") {
    throw new Error("Invalid JSON-RPC version.");
  }
  if (response.id !== id) {
    throw new Error("Mismatched response id.");
  }
  if (response.error) {
    throw new Error(`Protocol error ${response.error.code}: ${response.error.message}`);
  }
  if (!response.result || typeof response.result !== "object" || Array.isArray(response.result)) {
    throw new Error("Missing JSON-RPC result object.");
  }
  return response.result;
}

function notify(method, params = undefined) {
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, params })}\n`);
}

function validateTools(tools) {
  if (!Array.isArray(tools)) {
    throw new Error("tools/list result.tools must be an array.");
  }
  for (const tool of tools) {
    if (!tool || typeof tool !== "object" || Array.isArray(tool)) {
      throw new Error("Tool entry must be an object.");
    }
    if (typeof tool.name !== "string" || tool.name.length === 0) {
      throw new Error("Tool entry missing name.");
    }
    if (tool.title !== undefined && typeof tool.title !== "string") {
      throw new Error("Tool entry title must be a string when present.");
    }
    if (tool.description !== undefined && typeof tool.description !== "string") {
      throw new Error("Tool entry description must be a string when present.");
    }
    if (!tool.inputSchema || typeof tool.inputSchema !== "object" || Array.isArray(tool.inputSchema)) {
      throw new Error("Tool entry inputSchema must be an object.");
    }
    if (tool.inputSchema.required !== undefined) {
      if (!Array.isArray(tool.inputSchema.required) || !tool.inputSchema.required.every((value) => typeof value === "string")) {
        throw new Error("Tool entry inputSchema.required must be an array of strings.");
      }
    }
  }
}

async function runSequence() {
  const initialize = await request("initialize", {
    protocolVersion: "2025-11-25",
    capabilities: {},
    clientInfo: {
      name: "suisui-mcp-smoke",
      version: "0.1.0",
    },
  });
  if (initialize.protocolVersion !== "2025-11-25") {
    throw new Error(`Unsupported result.protocolVersion: ${initialize.protocolVersion}.`);
  }
  console.log(`initialize: protocolVersion=${initialize.protocolVersion}`);

  notify("notifications/initialized");

  const list = await request("tools/list", {});
  validateTools(list.tools);
  console.log(`tools/list: ${list.tools.map((tool) => tool.name).join(", ")}`);

  const call = await request("tools/call", {
    name: "read_status",
    arguments: { project: "suisui" },
  });
  const text = call.content?.[0]?.text;
  if (text !== "status: ok project=suisui") {
    throw new Error("tools/call returned unexpected text content.");
  }
  console.log(`tools/call: ${text}`);
  console.log("result: success initialize -> tools/list -> tools/call");
}

try {
  await runSequence();
  if (expectFailure) {
    throw new Error(`Expected ${mode} to fail, but it succeeded.`);
  }
} catch (error) {
  if (!expectFailure) {
    console.error(`${mode}: ${error.message}`);
    process.exitCode = 1;
  } else {
    console.log(`${mode}: ${error.message}`);
  }
} finally {
  child.stdin.end();
  child.kill("SIGTERM");
}
