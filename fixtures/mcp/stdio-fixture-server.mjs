#!/usr/bin/env node
import readline from "node:readline";

const mode = process.env.SUISUI_MCP_FIXTURE_MODE || "success";
let initialized = false;

const tools = [
  {
    name: "read_status",
    title: "Read Status",
    description: "Read local project status.",
    inputSchema: {
      type: "object",
      properties: {
        project: {
          type: "string",
          description: "Project name",
        },
      },
      required: ["project"],
      additionalProperties: false,
    },
  },
];

function writeJSON(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

function writeError(id, code, message) {
  writeJSON({
    jsonrpc: "2.0",
    id,
    error: { code, message },
  });
}

function handleInitialize(request) {
  if (mode === "malformed-json") {
    process.stdout.write("{not valid json\n");
    return;
  }

  initialized = true;
  writeJSON({
    jsonrpc: "2.0",
    id: request.id,
    result: {
      protocolVersion: "2025-11-25",
      capabilities: {
        tools: {
          listChanged: false,
        },
      },
      serverInfo: {
        name: "suisui-mcp-fixture",
        title: "Suisui MCP Fixture",
        version: "0.1.0",
      },
    },
  });
}

function handleToolsList(request) {
  if (!initialized) {
    writeError(request.id, -32002, "Server is not initialized.");
    return;
  }

  if (mode === "timeout") {
    return;
  }

  if (mode === "mismatched-id") {
    writeJSON({
      jsonrpc: "2.0",
      id: request.id + 1,
      result: { tools },
    });
    return;
  }

  if (mode === "invalid-schema") {
    writeJSON({
      jsonrpc: "2.0",
      id: request.id,
      result: {
        tools: [
          {
            ...tools[0],
            inputSchema: "not-an-object",
          },
        ],
      },
    });
    return;
  }

  writeJSON({
    jsonrpc: "2.0",
    id: request.id,
    result: { tools },
  });
}

function handleToolsCall(request) {
  if (!initialized) {
    writeError(request.id, -32002, "Server is not initialized.");
    return;
  }

  const name = request.params?.name;
  const project = request.params?.arguments?.project || "unknown";
  if (name !== "read_status") {
    writeError(request.id, -32602, `Unknown tool: ${name}`);
    return;
  }

  writeJSON({
    jsonrpc: "2.0",
    id: request.id,
    result: {
      content: [
        {
          type: "text",
          text: `status: ok project=${project}`,
        },
      ],
      isError: false,
    },
  });
}

function handleRequest(request) {
  switch (request.method) {
    case "initialize":
      handleInitialize(request);
      break;
    case "notifications/initialized":
      initialized = true;
      break;
    case "tools/list":
      handleToolsList(request);
      break;
    case "tools/call":
      handleToolsCall(request);
      break;
    default:
      writeError(request.id ?? null, -32601, `Unknown method: ${request.method}`);
  }
}

const input = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

input.on("line", (line) => {
  if (!line.trim()) {
    return;
  }

  try {
    handleRequest(JSON.parse(line));
  } catch {
    writeError(null, -32700, "Parse error");
  }
});
