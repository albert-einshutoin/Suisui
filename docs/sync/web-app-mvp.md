# Web App MVP

Verified: 2026-06-21

## Web frontend / backend boundary

Suisui Web is a synced-domain client, not a local execution surface. The first MVP reads `SyncDomainPayload` shaped data and sends task mutations through Cloud Relay compatible endpoints.

| Boundary | MVP choice |
| --- | --- |
| Read model | `SyncDomainPayload` read models for projects, tasks, documents, conversations, automation requests, relay state, and harness runs. |
| Task mutation | Cloud Relay task mutation endpoint using platform-neutral `SyncTaskMutationPayload`. |
| Admin mutation | Account, billing, devices, relay tokens, and Hosted MCP endpoint management. |
| Execution | Cloud-safe actions only. OS-bound actions remain pending until a connected macOS app can approve or execute them. |

## MVP surfaces

- Task board.
- Task list.
- Project documents and artifacts.
- Conversation history.
- Automation review inbox.
- Account and billing.
- Registered devices.
- Relay tokens.
- Hosted MCP endpoint management.
- Harness run history.

## Task management

Web can create tasks, complete tasks, change status, change due dates, and move tasks between projects through the same sync mutation contract used by iOS and Hosted MCP.

Plain task creation can be applied as a low-risk Cloud Relay mutation when the user's policy allows it. Existing-task rewrites, completion, due-date changes, and project moves stay reviewable by default because they can rewrite the user's current plan.

## OS-bound actions

Web must clearly show when an action requires a connected Mac:

- Local filesystem writes.
- Calendar writes.
- Reminders writes.
- Local stdio MCP execution.

These actions should be represented as pending automation requests, not executed directly from Web.

## Security notes

- Relay tokens are represented by display name and suffix only.
- Provider keys, MCP secrets, OAuth tokens, and raw relay tokens must not appear in Web read models or HTML previews.
- User-owned strings rendered in Web previews must be escaped.

## Verification

- `swift test --filter WebAppMVPTests`
- `swift build --target SuisuiWeb`
