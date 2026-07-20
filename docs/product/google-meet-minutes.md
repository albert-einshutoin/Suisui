# Google Calendar And Meet Minutes Product Decision

Status: proposed, July 2026

## Decision

Suisui should ship meeting minutes as a post-meeting, review-before-write
workflow. It should not ship an auto-joining recording bot or depend on the
real-time Meet Media API for the first release.

The recommended flow is:

1. Read upcoming Calendar events and identify Google Meet conference data.
2. Show the meeting in Today and optionally prepare an agenda/briefing.
3. After Meet reports that a transcript file is generated, retrieve the
   conference transcript with the signed-in user's authorization.
4. Generate a local draft containing summary, decisions, open questions,
   owners, due dates, and follow-ups.
5. Let the user edit and approve the draft.
6. Only after approval, create Suisui tasks and optionally attach/export the
   minutes.

This matches the product's core promise: speak, review, then move work forward.

## Current implementation

The current Google Calendar runtime provides OAuth with PKCE, Keychain-backed
tokens, writable-calendar discovery, refresh handling, and an approval-gated,
bounded, idempotent path that creates Calendar events from due Suisui tasks.

It does not yet:

- list incoming Calendar events;
- parse `hangoutLink` or `conferenceData`;
- map Calendar events to Meet spaces/conference records;
- request Meet scopes;
- retrieve transcript artifacts or transcript entries;
- generate or review meeting minutes.

Therefore Calendar task export is implemented, while Calendar-to-Meet minutes
is technically feasible but not implemented.

## API feasibility

Google Calendar event resources expose `hangoutLink` and `conferenceData`,
including the `hangoutsMeet` conference solution and meeting code. The Meet
REST API exposes conference records, participants, transcript metadata, and
transcript entries. Transcript artifacts can be retrieved after a conference,
and transcripts do not require video recording to be enabled.

Meet can also generate smart notes and automatic transcripts for eligible
meeting spaces. Those settings and artifacts depend on the organizer's account,
Workspace policy, product availability, and explicit configuration.

Official references:

- [Google Calendar event resource](https://developers.google.com/workspace/calendar/api/v3/reference/events)
- [Google Meet REST API overview](https://developers.google.com/workspace/meet/api/guides/overview)
- [Work with Meet artifacts](https://developers.google.com/workspace/meet/api/guides/artifacts)
- [Meet authentication and OAuth scopes](https://developers.google.com/workspace/meet/api/guides/authenticate-authorize)
- [Subscribe to Meet events](https://developers.google.com/workspace/events/guides/events-meet)
- [Meet space artifact settings](https://developers.google.com/workspace/meet/api/guides/meeting-spaces-configuration)

## Product boundary

### Build next

- Calendar read model for upcoming events with Meet metadata.
- Local event-to-project/task association.
- Agenda and pre-meeting briefing draft.
- Manual "議事録を取り込む" action after the meeting.
- Meet transcript retrieval using least-privilege user OAuth.
- Japanese-first minutes template: 要約、決定事項、担当、期限、未決事項。
- Review screen and approval-gated task creation.
- Audit receipt recording source event, transcript artifact, generated draft,
  edits, and approved writes without logging OAuth tokens or raw private audio.

### Add after the manual flow is proven

- `transcript.v2.fileGenerated` event subscription for automatic post-meeting
  draft creation. Workspace Events delivery uses Google Cloud Pub/Sub, so this
  introduces a cloud component and operational responsibility beyond the
  current local-first desktop app.
- Participant/owner matching and follow-up reminders.
- Smart notes import when the user's Workspace edition provides it.

### Defer

- Auto-joining Meet as a bot.
- Background or covert audio capture.
- Real-time minutes based on the Meet Media API.

The Meet Media API is currently a Developer Preview surface with enrollment,
participant-consent, codec, meeting-policy, and account constraints. It is a
poor production dependency for a Japanese-first personal launch. Live capture
also creates materially higher consent, privacy, retention, and support risk
than post-meeting artifact import.

## Security and consent

- Request Calendar read and Meet scopes incrementally, only when the user turns
  on meeting minutes.
- Meet REST API uses user authentication. Drive access for transcript files can
  require restricted scopes and Google verification; prefer the narrowest Meet
  artifact API path that satisfies the workflow.
- Never enable recording/transcription silently. Surface organizer eligibility,
  participant notices, and the source artifact before generating a draft.
- Keep raw transcripts local by default, support deletion, and never place them
  in diagnostics, logs, screenshots, or AI requests without explicit provider
  review.
