# Public Alpha Validation

## Status

The local validation contract and the operator runbook are prepared. The
four-week design-partner program has **not started** in this repository:
there are no participant records, interview notes, or Go/No-Go results here.
This document and `PublicAlphaValidation.swift` therefore do not close Issue
[#407](https://github.com/albert-einshutoin/Suisui/issues/407).

## Purpose

Validate the MVP 0 value loop with the target cohort rather than treating task
creation or screen coverage as product-market evidence:

```text
signed/notarized install
  -> first launch
  -> readiness complete or explicit skip
  -> first voice/text capture
  -> clarification when required
  -> reviewable Action Plan
  -> approved local action
  -> follow-up/waiting
  -> user-confirmed or evidence-backed Outcome
```

The product invariant remains `Capture -> Interpret -> Review -> Move ->
Evidence`. External writes are not part of this validation contract; they keep
the existing explicit Review boundary.

## Target cohort and cadence

- Japanese individual contractors, small Web/app studios, or one-person/small
  businesses with multiple client projects.
- Mac is the primary device; other personas are recorded as out of cohort and
  never mixed into the primary gate.
- Invite 20--30 people, target 10--20 activated users, observe for at least
  four weeks, and run a 15--30 minute weekly interview in `ja-JP`.

## Closed data contract

`PublicAlphaStageEvent` stores only a pseudonymous participant digest, an
opaque work-reference digest, one closed stage/mark, a timestamp, and closed
failure/abandonment categories. The work reference links stages from one local
job without persisting its source identifier.
`PublicAlphaValidationSnapshot` stores the weekly counts and coded categories:

| Field | Contract |
| --- | --- |
| Participant | `sha256:` digest of a random opaque participant seed; never use an email or other guessable identifier |
| Persona | `PublicAlphaPersonaFlag` set |
| Build | validated app version and source commit |
| Stage timing | `PublicAlphaStage` + started/completed/failed/abandoned + timestamp |
| Weekly activity | active days, captured items, confirmed commitments |
| Outcomes | outcome-tracked and outcome-closed counts; Task completion is not a substitute |
| Replanning | manual replanning count |
| Feedback | `proactiveFeedbackCounts` preserves each category count; report `feedbackCount` is the denominator |
| Trust | `PublicAlphaTrustIncidentCategory` set |
| Interview | `PublicAlphaInterviewCode` set |
| Continuation | active, paused, stopped, or completed |

The types have no fields for customer names, email addresses, raw transcript,
raw prompt/output, local path, repository name, private source text, or
free-form analytics metadata. Interview notes remain in a separate encrypted
research store and are never part of the product ledger.

`PublicAlphaValidationLedger` is a local Codable append-only snapshot. Replaying
the same event ID, snapshot ID, or participant/UTC ISO-week is a no-op; the snapshot can be recovered
after a crash/offline period and a participant deletion removes all pending
records. `remotePayload(consent:)` returns no payload for local-only or
research-dataset consent. Only explicit aggregated-diagnostics opt-in can
produce a raw-free aggregate report. This is an opt-in diagnostics summary,
not a claim of anonymity: a device may hold only one participant. No participant
digest is included in that payload. The local `report().participantCount`
includes participants in either stage events or weekly snapshots, including
early drop-offs and every recorded persona, and must not be used as the qualified cohort
size for the gate. Record target-excluded participants with `out_of_cohort`;
exclude that flag (even alongside another persona flag) and unqualified records
from primary metrics. The operator computes gate metrics from qualified,
four-week participants only; this pure contract does not infer them from totals.

Weekly timestamps are normalized to the start of the ISO week in UTC. Both
JSON decoding and crash recovery reject duplicate logical weeks. Counts must
be nonnegative; a count overflow fails aggregation with an error. Feedback
frequency is retained rather than deduplicated, including `not_delivered`;
the operator must state which categories form the helpful numerator and the
feedback denominator in the ADR.

## Local runtime measurement (#630)

Settings > Privacy > Local measurement enables collection explicitly; it is
off by default and never sends data remotely. Normal text, recorded speech and
hands-free finalized utterances record `first_capture`. Clarification retains
the same opaque work reference; session references in the existing ledger allow
conversation restoration to recover it. A durably published Review records
`reviewable_action_plan`; Queue approval, the persisted execution receipt and
the visible receipt row record `approved_local_action`, `local_execution` and
`result_displayed`. Execution failure uses a closed reliability category and
does not count as success. Task Done never creates an Outcome event.

Receipt history reconciles the receipts it already loads after a crash between
execution and measurement. Event identities make replay a no-op. No additional
repository or task scan is performed. Unreadable measurement data is preserved;
storage failure emits a fixed, content-free diagnostic and does not stop work.
An event that could not be persisted is unobserved, not a successful sample.

The development app bundle embeds `SuisuiSourceCommit` only for a clean
checkout. Events include the validated bundle version and commit when present.
Dirty/unidentified builds keep build identity absent and cannot establish the
candidate-version evidence required by #407.

Choose a date in Settings and export that UTC ISO week to local JSON. It
contains the existing closed events and snapshots so counts can be recalculated
by decoding `PublicAlphaValidationLedger`. Missing snapshots and build identities
are unknown; an empty export is not evidence of zero outcomes or a Go decision.

The same confirmed-record import also accepts a `PublicAlphaStageEvent` for
`confirmed_commitment`, `outcome_tracked`, or `outcome_closed` with a completed
mark, fresh event UUID, current participant digest and an existing opaque work
reference from the export. The operator must obtain participant confirmation;
no task/receipt status creates these events automatically. Unknown work references,
another participant, automatic stages and deleted participants are rejected.
Reimporting the same event ID is a no-op. Event and snapshot identity fields
select the existing closed record type; failed decoding never falls back.

The operator can import a `PublicAlphaValidationSnapshot` JSON file through
Settings after explicitly confirming its counts with the participant. Use the
participant digest from the export, a fresh snapshot UUID, the observed build,
and the selected week's timestamp. Foundation JSON dates are seconds since
2001-01-01 UTC; the contract normalizes the week to Monday UTC. Required fields
are those of `PublicAlphaValidationSnapshot`; feedback retains category counts,
not a category set. Import rejects another participant and invalid counts.
Interview text stays outside this file. A repeated participant/week is a replay,
not a second sample. This connects operator-confirmed outcomes and feedback
without inferring achievement from Task Done.

Delete local measurement removes the participant's events and snapshots and
stops collection. A persisted deletion marker rejects replay from existing
windows. Re-enabling measurement starts a new participant in newly opened
windows; old windows cannot resurrect the deleted records. Work data and
execution receipts are retained. Session/work/source references are hashes;
no transcript, source identifier, path, or arbitrary metadata is stored.

## Weekly operator flow

1. Screen the target persona and record consent separately from product
   analytics consent.
2. Distribute the signed/notarized candidate and record only the closed stage
   events from the First Value Loop.
3. Export a weekly snapshot from local diagnostics; do not copy task, client,
   transcript, prompt, or interview prose into the ledger.
4. Run the interview using the ten coded questions in Issue #407. Keep notes
   in the encrypted research store, then record only the matching closed
   interview codes.
5. Review drop-off categories (`persona_fit`, `onboarding`, `workflow`,
   `reliability`, `positioning`, or `unknown`) and trust incident categories.
6. At week four, calculate the gate metrics and check in one ADR with the
   resulting `Go`, `Iterate`, `Narrow`, or `Stop` decision. A missing sample is
   `insufficient_sample`, never `Go`.

## Initial gate (internal, not a market benchmark)

`PublicAlphaGateEvaluator` applies these fail-closed thresholds:

```text
four-week activated users >= 10
week-four retention >= 35%
median commitments per active user/week >= 2
commitments with Outcome tracking >= 50%
helpful proactive feedback >= 50%
critical trust incidents = 0
concrete non-substitutable reason >= 30%
willingness to pay 1,500--3,000 JPY/month >= 20%
```

Any critical trust incident returns `stop`, even with an insufficient
sample; otherwise insufficient sample returns `insufficient_sample`; all thresholds pass returns `go`. A sufficiently
large cohort with evidence of a differentiated but too-narrow fit returns
`narrow`; other misses return `iterate`. No future feature request is PMF
evidence until it is observed in this program and tracked as a new Issue.

## Evidence required to close #407

- At least ten qualified design partners had a four-week usage opportunity.
- Every First Value Loop stage has classified drop-off reasons.
- Multiple concrete Commitment/Outcome examples are recorded without raw
  content in product telemetry.
- The differentiated value versus ChatGPT/Claude/Reminders/Todoist is coded
  from participant interviews, not inferred from feature plans.
- A checked-in ADR records the gate result and the next scoped issues.

Until these external observations exist, #407 remains open even when the local
contract tests pass.
