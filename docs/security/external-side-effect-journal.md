# External Side-Effect Journal

Suisui cannot make one transaction span SQLite, EventKit, UserNotifications,
the filesystem, and future SaaS APIs. The external side-effect journal instead
provides a fail-closed retry contract for approved writes.

## State contract

```text
prepared -> started -> succeeded
                    -> unknown
                    -> failed_before_side_effect
                    -> compensated
```

- `prepared`: the idempotency key has been claimed before any external write.
- `started`: the adapter may now perform the external write.
- `succeeded`: external and local persistence completed; the saved `ToolResult`
  is returned for the same key without executing again.
- `failed_before_side_effect`: the adapter reported a known-safe failure such
  as denied permission or invalid input. This is the only retryable failure.
- `unknown`: the external result is uncertain, or the external write succeeded
  and local persistence failed. Automatic retry is blocked.
- `compensated`: a supported external resource was rolled back after explicit
  reconciliation. Re-execution requires a new idempotency identity.

Any `started` row found after process restart is promoted to `unknown`. This
prefers a visible reconciliation task over a duplicate calendar event,
reminder, notification, or file.

## Identity and privacy

The key binds review session, action ID, tool, and the canonical SHA-256 digest
of resolved arguments. Bulk operations append an item index and persist each
item separately. Raw arguments and file contents are not copied into the
journal.

Execution receipts expose the idempotency key, journal record ID, external
resource ID, and terminal state. The reconciliation read model exposes only
these operational identifiers and guidance; it does not expose raw arguments.

## Adapter rules

Adapters should pass the key to an external idempotency mechanism whenever one
exists. Calendar drafts and notification identifiers already carry it. For
systems without native support, the journal still prevents blind local retry,
but a human or connector-specific lookup must reconcile `unknown`.

Filesystem file creation uses exclusive create semantics. An existing target
is never overwritten, including when concurrent actions race.
