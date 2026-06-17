# Public Alpha Notes

SoloPM public alpha is scoped to the completed Phase 0-4 foundation plus Phase 5 release packaging.

## Scope

- Phase 0-4 app foundation
- Menu bar app shell
- voice / text to Action Plan path
- review-before-write execution model
- local Project / Task / Knowledge storage
- deadline watcher foundation
- release signing, notarization, DMG packaging, and Sparkle update foundation

## Out Of Scope

- External MCP runtime
- SaaS connectors
- full RAG indexing
- Team workspaces
- cloud sync
- automatic email sending
- automatic Slack posting
- destructive local file operations

## Sample Workflows

### Workflow 1: Voice To Project Plan

Say or type a rough project goal. SoloPM generates an Action Plan, shows the proposed project and tasks, and waits for approval before writing local data.

### Workflow 2: Deadline Watch

Create a project with a due date. SoloPM tracks overdue candidates and prepares local notification state so the user can see what needs attention.

### Workflow 3: Artifact Draft

Ask SoloPM to create a Markdown draft for a project deliverable. The write action is reviewed first and does not overwrite existing files.

## Known Limitations

- External MCP is planned for a later phase.
- SaaS integrations are planned for a later phase.
- RAG is limited to lightweight Knowledge Frames in the alpha.
- Team features are not implemented.
- Release signing and notarization require local Apple Developer credentials.

## Feedback

Use GitHub Issues for public alpha feedback. Include macOS version, SoloPM version, expected behavior, actual behavior, and whether the report contains private project data.
