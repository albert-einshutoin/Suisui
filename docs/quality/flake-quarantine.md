# Flake Quarantine

Status: active
Owner: Suisui quality gate

No indefinite quarantine is allowed. This file may be empty, but any non-empty
entry must be owned, reasoned, expiring, and reproducible.

## Required Entry Shape

| Field | Required | Notes |
| --- | --- | --- |
| owner | yes | Person or role responsible for removing the quarantine. |
| reason | yes | Concrete failure mode, not just "flaky". |
| expiry | yes | Date after which the quarantine is invalid and the gate must fail closed. |
| category | yes | One of build / assertion / crash / timing / environment / manual gate. |
| minimal reproduction command | yes | The shortest command that still shows the failure. |
| automation-backlog | conditional | Required when the fix is not landing immediately. |

## Active Quarantines

None.

## Review Rule

A quarantine entry without owner, reason, expiry, category, and minimal
reproduction command is invalid. Expired entries must be removed or converted
back into a blocking failure before release evidence is accepted.
