# SoloPM Harness

SoloPM Harness is the repeatable verification layer for Phase 13 automation. It covers provider prompt regression, task mutation flows, document-scoped automation, and MCP compatibility.

## Scenario Schema

The core scenario contract is `SoloPMHarnessScenario`.

Required fields:

- `id`: stable scenario identifier.
- `name`: operator-facing scenario name.
- `kind`: `providerPromptRegression`, `taskMutationFlow`, `documentScopedAutomation`, or `mcpCompatibility`.
- `requiredCapabilities`: provider prompt, task mutation, document automation, or MCP tool call capability.
- `expectedMutations`: platform-neutral `SyncTaskMutationPayload` values when the scenario expects task changes.
- `assertions`: expected output, approval boundary, audit log, redacted log, and diff assertions.

`SoloPMHarnessScenario.templateCatalog()` is the initial smoke catalog. It intentionally includes create, update, complete, due-date update, and project move mutations so conversation and Hosted MCP task changes are covered by the same schema.

## Result Envelope

Local harness runs and cloud-triggered harness runs use the same `SoloPMHarnessResultEnvelope` shape:

- `schemaVersion`
- `trigger`
- `scenarioKind`
- `status`
- `stepCount`
- `hasDiff`
- `hasRedactedLogs`

The trigger value differs, but the persisted result shape does not. This lets the Web app display local and cloud-triggered runs with the same renderer.

## History And Redaction

`RedactingSoloPMHarnessRunStore` stores `SoloPMHarnessRun` values after calling `redacted()`.

The store redacts:

- step expected text
- step actual text
- failure reasons
- diff expected/actual text
- log messages

Harness output often contains provider errors, MCP arguments, or tool traces. The store redacts at the persistence boundary so a future SQLite or cloud-backed store cannot accidentally persist raw API keys or tokens.

## Retention

Harness history is a Pro feature through `FeatureGate.harnessHistory`.

| Plan | History storage | Max runs | Retention |
| --- | --- | ---: | ---: |
| Free | Disabled | 0 | 0 days |
| Sync | Disabled | 0 | 0 days |
| Pro | Cloud-backed | 250 | 30 days |
| Founder | Extended cloud-backed | 1,000 | 365 days |

Sync is for cross-device task data, not paid remote execution diagnostics. Harness history stays Pro because it creates ongoing compute, storage, and support cost.

## Sync Payload

`SoloPMHarnessRun.syncPayload` maps runs to `SyncHarnessRunPayload` with scenario ID, scenario kind, trigger, status, failure reason, diff summary, and redacted log count. Raw logs do not enter the sync payload.
