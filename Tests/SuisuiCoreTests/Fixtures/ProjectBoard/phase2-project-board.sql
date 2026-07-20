CREATE TABLE schema_migrations (
    id TEXT PRIMARY KEY NOT NULL,
    applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO schema_migrations (id) VALUES
    ('0001_create_settings_and_audit_logs'),
    ('0002_create_projects_tasks_and_knowledge'),
    ('0002b_create_system_tool_state');

CREATE TABLE settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    category TEXT NOT NULL,
    action TEXT NOT NULL,
    status TEXT NOT NULL,
    metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    status TEXT NOT NULL,
    priority TEXT,
    deadline TEXT,
    workspace_path TEXT,
    tags_json TEXT NOT NULL DEFAULT '[]',
    source_command TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER,
    title TEXT NOT NULL,
    status TEXT NOT NULL,
    due_at TEXT,
    priority TEXT,
    source_command TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE knowledge_frames (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    body TEXT NOT NULL,
    triggers_json TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE VIRTUAL TABLE knowledge_frames_fts USING fts5(
    name,
    body,
    content='knowledge_frames',
    content_rowid='id'
);

CREATE TABLE notification_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK(status IN ('pending', 'scheduled', 'failed')),
    title TEXT NOT NULL,
    scheduled_at TEXT NOT NULL,
    external_notification_id TEXT,
    failure_reason TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE calendar_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    project_id INTEGER,
    task_id INTEGER,
    title TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_calendar_links_project ON calendar_links(project_id);
CREATE INDEX idx_calendar_links_task ON calendar_links(task_id);

CREATE TABLE reminder_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    reminder_id TEXT NOT NULL UNIQUE,
    project_id INTEGER,
    task_id INTEGER,
    title TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_reminder_links_project ON reminder_links(project_id);
CREATE INDEX idx_reminder_links_task ON reminder_links(task_id);

INSERT INTO projects (id, title, status, tags_json, source_command, updated_at)
VALUES (1, 'Legacy Launch', 'active', '["legacy"]', 'legacy.fixture', '2026-06-18T08:00:00Z');

INSERT INTO tasks (id, project_id, title, status, due_at, priority, source_command, updated_at)
VALUES
    (1, 1, 'Legacy planned task', 'planned', '2026-06-24', 'high', 'legacy.fixture', '2026-06-18T09:00:00Z'),
    (2, 1, 'Legacy completed task', 'completed', '2026-06-19', 'medium', 'legacy.fixture', '2026-06-18T10:00:00Z');
