# SoloPM Pricing and Packaging

Verified: 2026-06-21

## Positioning

SoloPM should keep the local Mac app useful without a subscription, then charge for cloud-backed convenience and safety controls.

The strongest paid message is:

> Create and capture tasks even when your Mac is offline or sleeping.

This is not just "remote MCP." The user-facing value is that SoloPM can receive a voice command, mobile shortcut, webhook, or LLM tool request while the primary Mac is unavailable, then sync the resulting task or pending action back to every device.

## Packaging Principles

- Local-first remains the default. The app, local database, BYOK LLM providers, and local review flow should work without an account.
- SoloPM should not pay for general LLM inference. Users bring provider keys unless a later hosted AI plan is explicitly introduced.
- Paid value should map to real operating cost: encrypted sync storage, relay uptime, audit logs, remote execution controls, and support.
- Paid status must never bypass approval, dangerous-tool blocking, or audit requirements.
- Remote execution should be framed as Cloud Relay and Hosted MCP, not as the default local MCP path.

## Plan Proposal

| Plan | Price proposal | Included value | Boundary |
| --- | ---: | --- | --- |
| Free | $0 | Local Mac app, local Project/Task/Knowledge storage, BYOK LLM providers, local SoloPM-mediated tool execution, local MCP registration and diagnostics, manual export/import | No device sync, no cloud relay, no hosted MCP endpoint |
| Sync | $5/month or $48/year | End-to-end encrypted iOS/Web/macOS sync, offline-first merge, version history, deleted item recovery, settings sync, unlimited personal devices within fair use | No externally reachable Hosted MCP endpoint |
| Pro | $10/month or $96/year | Sync plus Cloud Relay, Hosted MCP endpoint, PC-off task capture, document-scoped automation, remote pending-action inbox, execution audit log, SoloPM Harness, higher history/retention limits | Remote write actions still require policy and approval rules |
| Founder | $99 one-time or $120/year | Pro during early access, beta features, feedback channel, supporter badge/license metadata | Do not promise lifetime cloud cost unless the entitlement is explicitly capped |
| Team | $12-15/user/month | Shared projects, team sync spaces, admin controls, organization audit log, shared relay policies | Later; requires RBAC and organization billing |

## Implementation Gate Map

The current app-level entitlement model mirrors the packaging boundary with these `FeatureGate` values:

| FeatureGate | Minimum plan | UI/product meaning |
| --- | --- | --- |
| `externalSync` | Sync | End-to-end encrypted device sync for iOS, Web, and macOS. |
| `advancedMCPExecution` | Pro | SoloPM calling registered external MCP tools after approval. |
| `cloudRelay` | Pro | Always-available request capture when the primary Mac is not running. |
| `hostedMCPEndpoint` | Pro | User-owned HTTPS endpoint for approved external LLM/MCP clients. |
| `documentScopedAutomation` | Pro | AI-assisted preparation and artifact drafting from approved app/project docs. |
| `harnessHistory` | Pro | Harness runs, execution history, and diffable regression evidence. |
| `externalConnectorWrite` | Pro | External side effects such as calendar writes or SaaS connector writes. |
| `providerPresets` | Pro | Paid presets/support metadata; BYOK provider configuration remains Free. |

Free users must hit the upgrade gate before network-backed sync, Cloud Relay, Hosted MCP, or external connector writes start. Sync users can sync personal data across devices, but they still need Pro before any externally reachable endpoint or third-party write action is executed.

Obsidian's current public model is a useful reference point: the core app is free, and Sync is a paid add-on starting at $4/month billed annually or $5/month billed monthly, with end-to-end encryption and version history. SoloPM should use the same mental model but charge Pro for remote relay and harness features because those create a larger security and infrastructure burden.

References:
- https://obsidian.md/pricing
- https://obsidian.md/sync

## Free

Free should be valuable enough for OSS users and local-first users:

- Create, edit, complete, move, and schedule tasks locally.
- Use BYOK Gemini, OpenAI, Claude, Groq, OpenRouter, Ollama, or local providers when configured.
- Use SoloPM's internal tool registry and approval flow.
- Register and diagnose external MCP servers without sending `tools/call`.
- Run local-only smoke checks and export data.

Free should not include:

- Device sync.
- Cloud storage.
- Hosted MCP endpoint.
- PC-off task capture.
- Scheduled remote harness runs.

## Sync

Sync is the first paid product. It should answer:

> I use SoloPM on iOS, Web, and macOS and want the same tasks, projects, conversations, and settings everywhere.

Included data:

- Projects.
- Tasks.
- Conversation metadata.
- Selected document metadata.
- Knowledge Frames metadata and user-created text content.
- Settings that are safe to sync.
- MCP registrations without secrets unless a future encrypted secret-sync design is accepted.

Security requirements:

- End-to-end encryption before upload.
- No provider API keys in plaintext.
- Conflict history and restore.
- Deleted item recovery.
- Clear device list and remote logout.

Initial limits can be simple:

- Unlimited personal devices.
- 1 workspace.
- 1 GB encrypted storage.
- 30-day version history.

## Pro

Pro bundles Sync with remote automation features.

The primary Pro promise is:

> SoloPM can accept task capture and automation requests even when your Mac is not running.

Features:

- Cloud Relay receives voice/mobile/shortcut/webhook/LLM requests.
- Hosted MCP exposes a secure HTTPS endpoint for approved remote clients.
- Requests become either tasks or pending actions in the encrypted sync ledger.
- The Mac app later reconciles, reviews, executes, and audits actions according to local policy.
- Document-scoped automation can read approved app/project docs and propose tasks, status changes, prep checklists, or draft artifacts.
- Low-risk `task.create` can support opt-in auto-create; destructive or external writes stay pending until approval.

This makes "LLM API directly calls MCP" a paid Pro capability, but the product wording should be Cloud Relay / Hosted MCP because users buy reliability and safety, not protocol plumbing.

## SoloPM Harness

Harness should be part of Pro because it compounds the value of Cloud Relay and creates ongoing compute/storage/support cost.

Definition:

- A repeatable workflow test and automation harness for SoloPM actions.
- It can run scripted task-creation, update, completion, due-date, and MCP execution scenarios against a controlled workspace.
- It records prompts, tool calls, approvals, outputs, and regressions.
- It helps power users verify that their LLM/provider/MCP setup still behaves as expected after prompt, provider, or app changes.

Initial Pro scope:

- Local harness templates.
- Scheduled cloud-triggered harness runs when Cloud Relay is enabled.
- Execution history and diffable results.
- Provider smoke checks for BYOK configurations without storing raw API keys in logs.
- MCP tool compatibility checks with redacted arguments.

Out of scope until Team:

- Shared team harness libraries.
- Organization-wide policy simulation.
- Multi-user approval workflows.

## Remote MCP Boundary

SoloPM should expose three clearly different modes:

| Mode | Plan | Description |
| --- | --- | --- |
| SoloPM-mediated local tools | Free | LLM output is converted into an Action Plan, reviewed locally, then executed by SoloPM. |
| External MCP client execution | Pro execution gate | SoloPM calls user-registered MCP servers with approval and audit controls. Free can register and diagnose. |
| Hosted MCP / Cloud Relay | Pro | External LLMs or clients call a SoloPM-hosted HTTPS endpoint so requests can be captured while devices are unavailable. |

Remote MCP must not mean "any LLM can mutate local data." The relay should require:

- User-owned endpoint credentials.
- Per-client tokens or OAuth later.
- Rate limits.
- Audit logs.
- Tool allowlists.
- Approval policy.
- Revocation.

## PC-Off Task Capture Flow

Target flow:

```text
User speaks into mobile/TTS shortcut
↓
LLM provider extracts intent
↓
Cloud Relay receives task_create or pending_action request
↓
Encrypted sync ledger stores the result
↓
SoloPM on Mac/iPhone/iPad syncs later
↓
Task appears in Inbox, or pending action waits for approval
```

This is the core paid wedge. It keeps the local-first promise for normal use while giving paying users a reason to trust SoloPM as an always-available personal PM layer.

## Multiplatform Direction

SoloPM's long-term packaging assumes three product surfaces:

- macOS app for local-first power use, local OS integrations, and local MCP execution.
- iOS app for capture, conversation, task status changes, notifications, and approval.
- Web app for cross-device task management, project docs, automation review, billing, device management, and Hosted MCP tokens.

See `docs/product/multiplatform-automation.md` for the full product and implementation direction.

## Messaging

Primary:

- "Capture tasks even when your Mac is asleep."
- "Local-first when you are at your desk. Always-available when you need capture on the go."
- "Bring your own AI key; pay SoloPM only for sync, relay, and safety infrastructure."

Avoid:

- "Cloud agent controls your Mac."
- "LLM directly runs your local tools."
- "Full MCP host" until Resources, Prompts, Streamable HTTP, remote auth, and server-side compliance are intentionally implemented.

## Open Decisions

- Whether Sync and Pro should launch together or Sync should launch first.
- Whether Founder should be a one-time supporter plan or an annual early-access plan.
- Whether PC-off capture auto-creates only plain tasks or can create projects and due dates under a policy.
- Whether Harness history counts against Sync storage or has a separate retention limit.
