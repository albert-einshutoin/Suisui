import XCTest
@testable import SoloPMCore

final class ProjectTaskKnowledgeToolTests: XCTestCase {
    func testProjectCreateToolPersistsProjectWithApproval() throws {
        let stores = try makeStores()
        let tool = ProjectTool(name: .projectCreate, store: stores.projects)

        let result = try tool.execute(
            arguments: ["title": .string("  Launch alpha  ")],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(try stores.projects.list().first?.title, "Launch alpha")
        XCTAssertNotNil(result.rollbackMetadata["projectId"])
    }

    func testProjectCreateRejectsNonStringTagsWithoutCreatingProject() throws {
        let stores = try makeStores()
        let tool = ProjectTool(name: .projectCreate, store: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Launch alpha"),
                    "tags": .array([.string("oss"), .number(1)])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.projectCreate, "Argument 'tags[1]' must be string."))
        }

        XCTAssertEqual(try stores.projects.list(), [])
    }

    func testProjectCreateRejectsBlankTagsWithoutCreatingProject() throws {
        let stores = try makeStores()
        let tool = ProjectTool(name: .projectCreate, store: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Launch alpha"),
                    "tags": .array([.string("oss"), .string("  ")])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.projectCreate, "Argument 'tags[1]' cannot be blank."))
        }

        XCTAssertEqual(try stores.projects.list(), [])
    }

    func testProjectUpdateRejectsBlankTitleWithoutMutatingProject() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let tool = ProjectTool(name: .projectUpdate, store: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "id": .number(Double(project.id)),
                    "title": .string("   ")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.projectUpdate, "Argument 'title' cannot be blank."))
        }

        XCTAssertEqual(try stores.projects.get(id: project.id).title, "Launch Readiness")
    }

    func testProjectUpdateToolPersistsEditableMetadata() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let tool = ProjectTool(name: .projectUpdate, store: stores.projects)

        _ = try tool.execute(
            arguments: [
                "id": .number(Double(project.id)),
                "priority": .string("high"),
                "deadline": .string("2026-06-30"),
                "workspacePath": .string("/tmp/solopm-launch"),
                "tags": .array([.string("release"), .string("alpha")])
            ],
            context: approvedContext()
        )

        let updated = try stores.projects.get(id: project.id)
        XCTAssertEqual(updated.priority, "high")
        XCTAssertEqual(updated.deadline, "2026-06-30")
        XCTAssertEqual(updated.workspacePath, "/tmp/solopm-launch")
        XCTAssertEqual(updated.tags, ["release", "alpha"])
    }

    func testProjectUpdateToolClearsEditableMetadataWithNullArguments() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(
            title: "Launch Readiness",
            priority: "high",
            deadline: "2026-06-30",
            workspacePath: "/tmp/solopm-launch",
            tags: ["release", "alpha"]
        )
        let tool = ProjectTool(name: .projectUpdate, store: stores.projects)

        _ = try tool.execute(
            arguments: [
                "id": .number(Double(project.id)),
                "priority": .null,
                "deadline": .null,
                "workspacePath": .null,
                "tags": .null
            ],
            context: approvedContext()
        )

        let updated = try stores.projects.get(id: project.id)
        XCTAssertNil(updated.priority)
        XCTAssertNil(updated.deadline)
        XCTAssertNil(updated.workspacePath)
        XCTAssertEqual(updated.tags, [])
    }

    func testProjectUpdateSchemaAcceptsMetadataUpdateAndClearArguments() throws {
        let stores = try makeStores()
        let update = ProjectTool(name: .projectUpdate, store: stores.projects)

        XCTAssertEqual(update.inputSchema.properties["priority"], "string|null")
        XCTAssertEqual(update.inputSchema.properties["deadline"], "string|null")
        XCTAssertEqual(update.inputSchema.properties["workspacePath"], "string|null")
        XCTAssertEqual(update.inputSchema.properties["tags"], "array|null")

        let issues = update.inputSchema.validate(
            arguments: [
                "id": .number(1),
                "priority": .null,
                "deadline": .null,
                "workspacePath": .null,
                "tags": .null
            ],
            tool: .projectUpdate
        )

        XCTAssertEqual(issues, [])
    }

    func testProjectListToolReturnsPersistentProjectRecords() throws {
        let stores = try makeStores()
        let first = try stores.projects.create(
            title: "Inbox",
            priority: "medium",
            deadline: "2026-06-30",
            workspacePath: "/tmp/inbox",
            tags: ["local", "triage"],
            sourceCommand: "token=project-secret"
        )
        let archived = try stores.projects.create(title: "Archived")
        _ = try stores.projects.archive(id: archived.id)
        let tool = ProjectTool(name: .projectList, store: stores.projects)

        let result = try tool.execute(arguments: [:], context: ToolExecutionContext(source: .developerTool))

        XCTAssertEqual(result.output["count"], .number(1))
        let projects = try XCTUnwrap(result.output["projects"]?.arrayValue)
        XCTAssertEqual(projects.count, 1)
        let project = try XCTUnwrap(projects.first?.objectValue)
        XCTAssertEqual(project["id"], .number(Double(first.id)))
        XCTAssertEqual(project["title"], .string("Inbox"))
        XCTAssertEqual(project["status"], .string("active"))
        XCTAssertEqual(project["priority"], .string("medium"))
        XCTAssertEqual(project["deadline"], .string("2026-06-30"))
        XCTAssertEqual(project["workspacePath"], .string("/tmp/inbox"))
        XCTAssertEqual(project["tags"], .array([.string("local"), .string("triage")]))
        XCTAssertNil(project["sourceCommand"])
    }

    func testTaskBulkCreatePersistsTasksTransactionallyEnoughForMVP() throws {
        let stores = try makeStores()
        let tool = TaskTool(name: .taskBulkCreate, store: stores.tasks)

        let result = try tool.execute(
            arguments: [
                "tasks": .array([
                    .object(["title": .string("Draft")]),
                    .object(["title": .string("Review")])
                ])
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.summary, "Created 2 tasks")
        XCTAssertEqual(try stores.tasks.listAll().map(\.title), ["Draft", "Review"])
    }

    func testTaskListToolReturnsPersistentOpenTaskRecordsWithoutApproval() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let first = try stores.tasks.create(
            title: "Draft release notes",
            projectID: project.id,
            dueAt: "2026-06-22T09:00:00Z",
            priority: "high",
            sourceCommand: "token=task-secret",
            status: "planned",
            detail: "Write user-facing changes."
        )
        let completed = try stores.tasks.create(title: "Already done", status: "completed")
        let tool = TaskTool(name: .taskList, store: stores.tasks)

        let result = try tool.execute(arguments: [:], context: ToolExecutionContext(source: .developerTool))

        XCTAssertEqual(result.output["count"], JSONValue.number(1))
        let tasks = try XCTUnwrap(result.output["tasks"]?.arrayValue)
        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first?.objectValue)
        XCTAssertEqual(task["id"], JSONValue.number(Double(first.id)))
        XCTAssertEqual(task["title"], JSONValue.string("Draft release notes"))
        XCTAssertEqual(task["status"], JSONValue.string("planned"))
        XCTAssertEqual(task["projectId"], JSONValue.number(Double(project.id)))
        XCTAssertEqual(task["dueAt"], JSONValue.string("2026-06-22T09:00:00Z"))
        XCTAssertEqual(task["priority"], JSONValue.string("high"))
        XCTAssertEqual(task["detail"], JSONValue.string("Write user-facing changes."))
        XCTAssertNil(task["sourceCommand"])
        XCTAssertFalse(tasks.contains { $0.objectValue?["id"] == JSONValue.number(Double(completed.id)) })
    }

    func testProjectCompleteToolCompletesOpenProjectTasks() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let task = try stores.tasks.create(
            title: "Prepare release notes",
            projectID: project.id,
            status: "planned"
        )
        let tool = ProjectTool(name: .projectComplete, store: stores.projects, taskStore: stores.tasks)

        let result = try tool.execute(
            arguments: ["id": .number(Double(project.id))],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(try stores.projects.get(id: project.id).status, "completed")
        XCTAssertEqual(try stores.tasks.get(id: task.id).status, "completed")
    }

    func testProjectCompleteToolRollsBackProjectStatusWhenTaskCompletionFails() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Atomic Tool Completion")
        let task = try stores.tasks.create(title: "Must remain planned", projectID: project.id, status: "planned")
        try stores.connection.execute(
            """
            CREATE TRIGGER fail_tool_task_completion
            BEFORE UPDATE OF status ON tasks
            WHEN NEW.status = 'completed'
            BEGIN
                SELECT RAISE(ABORT, 'task completion failed');
            END;
            """
        )
        let tool = ProjectTool(name: .projectComplete, store: stores.projects, taskStore: stores.tasks)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: ["id": .number(Double(project.id))],
                context: approvedContext()
            )
        )

        XCTAssertEqual(try stores.projects.get(id: project.id).status, "active")
        XCTAssertEqual(try stores.tasks.get(id: task.id).status, "planned")
    }

    func testProjectCompleteToolRequiresTaskStore() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let tool = ProjectTool(name: .projectComplete, store: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: ["id": .number(Double(project.id))],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.projectComplete, "Task store is required to complete project tasks.")
            )
        }
        XCTAssertEqual(try stores.projects.get(id: project.id).status, "active")
    }

    func testProjectDeleteToolDeletesPersistentProjectGraphWithApproval() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Stale Initiative")
        let task = try stores.tasks.create(title: "Remove stale task", projectID: project.id)
        let tool = ProjectTool(name: .projectDelete, store: stores.projects, taskStore: stores.tasks)

        let result = try tool.execute(
            arguments: ["id": .number(Double(project.id))],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.summary, "Deleted project Stale Initiative")
        XCTAssertEqual(result.output["projectId"], .number(Double(project.id)))
        XCTAssertEqual(result.output["deletedTaskCount"], .number(1))
        XCTAssertThrowsError(try stores.projects.get(id: project.id))
        XCTAssertThrowsError(try stores.tasks.get(id: task.id))
    }

    func testTaskCreateToolReopensCompletedProjectForNewOpenWork() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        _ = try stores.projects.update(id: project.id, status: "completed")
        let tool = TaskTool(name: .taskCreate, store: stores.tasks, projectStore: stores.projects)

        _ = try tool.execute(
            arguments: [
                "title": .string("  Address release review  "),
                "projectId": .number(Double(project.id))
            ],
            context: approvedContext()
        )

        XCTAssertEqual(try stores.projects.get(id: project.id).status, "active")
        XCTAssertEqual(try stores.tasks.listAll().map(\.title), ["Address release review"])
    }

    func testTaskCreateToolPersistsDetailAndSchedulingMetadata() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let tool = TaskTool(name: .taskCreate, store: stores.tasks, projectStore: stores.projects)

        let result = try tool.execute(
            arguments: [
                "title": .string("Draft release notes"),
                "projectId": .number(Double(project.id)),
                "detail": .string("Summarize working CRUD and local-first data."),
                "dueAt": .string("2026-06-21T09:00:00Z"),
                "priority": .string("high")
            ],
            context: approvedContext()
        )
        let taskID = try XCTUnwrap(result.output["taskId"]?.int64Value)
        let task = try stores.tasks.get(id: taskID)

        XCTAssertEqual(task.projectID, project.id)
        XCTAssertEqual(task.detail, "Summarize working CRUD and local-first data.")
        XCTAssertEqual(task.dueAt, "2026-06-21T09:00:00Z")
        XCTAssertEqual(task.priority, "high")
    }

    func testTaskGetToolReturnsPersistentTaskRecord() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let task = try stores.tasks.create(
            title: "Inspect task",
            projectID: project.id,
            dueAt: "2026-06-21T09:00:00Z",
            priority: "high",
            status: "blocked",
            detail: "Confirm local CRUD read path."
        )
        let tool = TaskTool(name: .taskGet, store: stores.tasks, projectStore: stores.projects)

        let result = try tool.execute(
            arguments: ["id": .number(Double(task.id))],
            context: ToolExecutionContext(source: .developerTool)
        )

        XCTAssertEqual(result.summary, "Inspect task")
        XCTAssertEqual(result.output["id"], .number(Double(task.id)))
        XCTAssertEqual(result.output["projectId"], .number(Double(project.id)))
        XCTAssertEqual(result.output["title"], .string("Inspect task"))
        XCTAssertEqual(result.output["status"], .string("blocked"))
        XCTAssertEqual(result.output["detail"], .string("Confirm local CRUD read path."))
        XCTAssertEqual(result.output["dueAt"], .string("2026-06-21T09:00:00Z"))
        XCTAssertEqual(result.output["priority"], .string("high"))
    }

    func testTaskDeleteToolDeletesPersistentTaskWithApproval() throws {
        let stores = try makeStores()
        let task = try stores.tasks.create(title: "Remove stale task")
        let tool = TaskTool(name: .taskDelete, store: stores.tasks, projectStore: stores.projects)

        let result = try tool.execute(
            arguments: ["id": .number(Double(task.id))],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["taskId"], .number(Double(task.id)))
        XCTAssertEqual(result.output["deletedCalendarLinkCount"], .number(0))
        XCTAssertEqual(result.output["deletedReminderLinkCount"], .number(0))
        XCTAssertEqual(result.output["deletedDeadlineRuleCount"], .number(0))
        XCTAssertEqual(result.output["deletedArtifactCount"], .number(0))
        XCTAssertThrowsError(try stores.tasks.get(id: task.id))
    }

    func testTaskCreateRejectsNonStringOptionalFieldsWithoutCreatingTask() throws {
        let stores = try makeStores()
        let tool = TaskTool(name: .taskCreate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Ship alpha"),
                    "dueAt": .number(1)
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.taskCreate, "Argument 'dueAt' must be string."))
        }

        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskUpdateRejectsBlankTitleWithoutMutatingTask() throws {
        let stores = try makeStores()
        let task = try stores.tasks.create(title: "Draft release notes")
        let tool = TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "id": .number(Double(task.id)),
                    "title": .string("   ")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.taskUpdate, "Argument 'title' cannot be blank."))
        }

        XCTAssertEqual(try stores.tasks.get(id: task.id).title, "Draft release notes")
    }

    func testTaskUpdateRejectsInvalidStatusWithoutReopeningCompletedProject() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Completed Initiative")
        _ = try stores.projects.update(id: project.id, status: "completed")
        let task = try stores.tasks.create(
            title: "Already shipped",
            projectID: project.id,
            status: "completed"
        )
        let tool = TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "id": .number(Double(task.id)),
                    "status": .string("parked")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskUpdate, "Argument 'status' must be one of open, backlog, planned, in_progress, blocked, completed.")
            )
        }

        XCTAssertEqual(try stores.projects.get(id: project.id).status, "completed")
        XCTAssertEqual(try stores.tasks.get(id: task.id).status, "completed")
    }

    func testTaskUpdateToolPersistsEditableTaskMetadataAndMovesProject() throws {
        let stores = try makeStores()
        let sourceProject = try stores.projects.create(title: "Inbox")
        let targetProject = try stores.projects.create(title: "Launch Readiness")
        let task = try stores.tasks.create(
            title: "Draft release notes",
            projectID: sourceProject.id,
            dueAt: "2026-06-20T09:00:00Z",
            priority: "medium",
            detail: "Initial detail"
        )
        let tool = TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)

        _ = try tool.execute(
            arguments: [
                "id": .number(Double(task.id)),
                "title": .string("Finalize release notes"),
                "projectId": .number(Double(targetProject.id)),
                "status": .string("in_progress"),
                "detail": .string("Include rollback evidence and release blockers."),
                "dueAt": .string("2026-06-22T09:00:00Z"),
                "priority": .string("high")
            ],
            context: approvedContext()
        )

        let updated = try stores.tasks.get(id: task.id)
        XCTAssertEqual(updated.title, "Finalize release notes")
        XCTAssertEqual(updated.projectID, targetProject.id)
        XCTAssertEqual(updated.status, "in_progress")
        XCTAssertEqual(updated.detail, "Include rollback evidence and release blockers.")
        XCTAssertEqual(updated.dueAt, "2026-06-22T09:00:00Z")
        XCTAssertEqual(updated.priority, "high")
    }

    func testTaskUpdateToolClearsEditableTaskMetadataWithNullArguments() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let task = try stores.tasks.create(
            title: "Draft release notes",
            projectID: project.id,
            dueAt: "2026-06-20T09:00:00Z",
            priority: "high",
            status: "planned",
            detail: "Initial detail"
        )
        let tool = TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)

        _ = try tool.execute(
            arguments: [
                "id": .number(Double(task.id)),
                "projectId": .null,
                "detail": .null,
                "dueAt": .null,
                "priority": .null
            ],
            context: approvedContext()
        )

        let updated = try stores.tasks.get(id: task.id)
        XCTAssertEqual(updated.title, "Draft release notes")
        XCTAssertEqual(updated.status, "planned")
        XCTAssertNil(updated.projectID)
        XCTAssertNil(updated.detail)
        XCTAssertNil(updated.dueAt)
        XCTAssertNil(updated.priority)
    }

    func testTaskCreateWithProjectIDRequiresProjectStore() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let tool = TaskTool(name: .taskCreate, store: stores.tasks)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Unvalidated project task"),
                    "projectId": .number(Double(project.id))
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.taskCreate, "Project store is required to validate project task mutations.")
            )
        }
        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskCreateToolRejectsArchivedProject() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Paused Initiative")
        _ = try stores.projects.archive(id: project.id)
        let tool = TaskTool(name: .taskCreate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Hidden follow-up"),
                    "projectId": .number(Double(project.id))
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskCreate, "Restore the project before adding tasks.")
            )
        }
        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskBulkCreateRejectsArchivedProjectWithoutReopeningCompletedProject() throws {
        let stores = try makeStores()
        let completedProject = try stores.projects.create(title: "Completed Initiative")
        let archivedProject = try stores.projects.create(title: "Paused Initiative")
        _ = try stores.projects.update(id: completedProject.id, status: "completed")
        _ = try stores.projects.archive(id: archivedProject.id)
        let tool = TaskTool(name: .taskBulkCreate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "tasks": .array([
                        .object([
                            "title": .string("Follow-up work"),
                            "projectId": .number(Double(completedProject.id))
                        ]),
                        .object([
                            "title": .string("Hidden archived work"),
                            "projectId": .number(Double(archivedProject.id))
                        ])
                    ])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskBulkCreate, "Restore the project before adding tasks.")
            )
        }

        XCTAssertEqual(try stores.projects.get(id: completedProject.id).status, "completed")
        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskBulkCreateRejectsInvalidBatchWithoutPartialRows() throws {
        let stores = try makeStores()
        let tool = TaskTool(name: .taskBulkCreate, store: stores.tasks)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "tasks": .array([
                        .object(["title": .string("Draft")]),
                        .object(["dueAt": .string("2026-06-18T09:00:00Z")])
                    ])
                ],
                context: approvedContext()
            )
        )

        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskBulkCreateRejectsNonObjectItemsWithoutPartialRows() throws {
        let stores = try makeStores()
        let tool = TaskTool(name: .taskBulkCreate, store: stores.tasks)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "tasks": .array([
                        .object(["title": .string("Draft")]),
                        .string("Review")
                    ])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.taskBulkCreate, "Argument 'tasks[1]' must be object."))
        }

        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskBulkCreatePersistsDetailAndSchedulingMetadata() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let tool = TaskTool(name: .taskBulkCreate, store: stores.tasks, projectStore: stores.projects)

        _ = try tool.execute(
            arguments: [
                "tasks": .array([
                    .object([
                        "title": .string("Draft checklist"),
                        "projectId": .number(Double(project.id)),
                        "detail": .string("Cover signing and notarization."),
                        "dueAt": .string("2026-06-21T09:00:00Z"),
                        "priority": .string("high")
                    ])
                ])
            ],
            context: approvedContext()
        )

        let task = try XCTUnwrap(stores.tasks.listAll().first)
        XCTAssertEqual(task.projectID, project.id)
        XCTAssertEqual(task.detail, "Cover signing and notarization.")
        XCTAssertEqual(task.dueAt, "2026-06-21T09:00:00Z")
        XCTAssertEqual(task.priority, "high")
    }

    func testTaskToolSchemasExposeEditableTaskMetadata() throws {
        let stores = try makeStores()
        let create = TaskTool(name: .taskCreate, store: stores.tasks, projectStore: stores.projects)
        let bulkCreate = TaskTool(name: .taskBulkCreate, store: stores.tasks, projectStore: stores.projects)
        let update = TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)
        let get = TaskTool(name: .taskGet, store: stores.tasks, projectStore: stores.projects)
        let delete = TaskTool(name: .taskDelete, store: stores.tasks, projectStore: stores.projects)

        XCTAssertEqual(create.inputSchema.properties["detail"], "string")
        XCTAssertEqual(create.inputSchema.properties["dueAt"], "string")
        XCTAssertEqual(create.inputSchema.properties["priority"], "string")

        let taskItemSchema = try XCTUnwrap(bulkCreate.inputSchema.arrayItems["tasks"])
        XCTAssertEqual(taskItemSchema.properties["detail"], "string")
        XCTAssertEqual(taskItemSchema.properties["dueAt"], "string")
        XCTAssertEqual(taskItemSchema.properties["priority"], "string")

        XCTAssertEqual(update.inputSchema.properties["projectId"], "integer|null")
        XCTAssertEqual(update.inputSchema.properties["detail"], "string|null")
        XCTAssertEqual(update.inputSchema.properties["dueAt"], "string|null")
        XCTAssertEqual(update.inputSchema.properties["priority"], "string|null")
        XCTAssertEqual(get.inputSchema.required, ["id"])
        XCTAssertEqual(delete.inputSchema.required, ["id"])
    }

    func testTaskListDueAndOverdueToolsReturnPersistentTaskRecords() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let due = try stores.tasks.create(
            title: "Due release task",
            projectID: project.id,
            dueAt: "2026-06-18T09:00:00Z",
            priority: "high",
            sourceCommand: "token=task-secret",
            status: "planned",
            detail: "Ship a readable task list."
        )
        _ = try stores.tasks.create(
            title: "Future task",
            projectID: project.id,
            dueAt: "2026-06-20T09:00:00Z",
            priority: "low"
        )
        let listDue = TaskTool(name: .taskListDue, store: stores.tasks, projectStore: stores.projects)
        let listOverdue = TaskTool(name: .taskListOverdue, store: stores.tasks, projectStore: stores.projects)

        let dueResult = try listDue.execute(
            arguments: ["cutoff": .string("2026-06-18T09:00:00Z")],
            context: ToolExecutionContext(source: .developerTool)
        )
        let overdueResult = try listOverdue.execute(
            arguments: ["cutoff": .string("2026-06-19T00:00:00Z")],
            context: ToolExecutionContext(source: .developerTool)
        )

        for result in [dueResult, overdueResult] {
            XCTAssertEqual(result.output["count"], .number(1))
            let tasks = try XCTUnwrap(result.output["tasks"]?.arrayValue)
            XCTAssertEqual(tasks.count, 1)
            let task = try XCTUnwrap(tasks.first?.objectValue)
            XCTAssertEqual(task["id"], .number(Double(due.id)))
            XCTAssertEqual(task["projectId"], .number(Double(project.id)))
            XCTAssertEqual(task["title"], .string("Due release task"))
            XCTAssertEqual(task["status"], .string("planned"))
            XCTAssertEqual(task["detail"], .string("Ship a readable task list."))
            XCTAssertEqual(task["dueAt"], .string("2026-06-18T09:00:00Z"))
            XCTAssertEqual(task["priority"], .string("high"))
            XCTAssertNil(task["sourceCommand"])
        }
    }

    func testTaskUpdateSchemaAcceptsNullForClearableTaskMetadata() throws {
        let stores = try makeStores()
        let update = TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)

        let issues = update.inputSchema.validate(
            arguments: [
                "id": .number(1),
                "projectId": .null,
                "detail": .null,
                "dueAt": .null,
                "priority": .null
            ],
            tool: .taskUpdate
        )

        XCTAssertEqual(issues, [])
    }

    func testKnowledgeFrameCreateAndSearchUseSameStore() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)
        let search = KnowledgeFrameTool(name: .frameSearch, store: stores.knowledge)

        _ = try create.execute(
            arguments: [
                "name": .string("Release checklist"),
                "body": .string("Use notarization and checksum before alpha release.")
            ],
            context: approvedContext()
        )
        let result = try search.execute(arguments: ["query": .string("notarization")], context: ToolExecutionContext(source: .developerTool))

        XCTAssertEqual(result.output["count"], .number(1))
    }

    func testKnowledgeFrameListAndSearchToolsReturnPersistentFrameRecords() throws {
        let stores = try makeStores()
        let release = try stores.knowledge.create(
            name: "Release readiness frame",
            body: "Use notarization and checksum before alpha release.",
            triggers: ["release", "alpha"]
        )
        _ = try stores.knowledge.create(
            name: "Meeting notes frame",
            body: "Capture meeting outcomes.",
            triggers: ["meeting"]
        )
        let list = KnowledgeFrameTool(name: .frameList, store: stores.knowledge)
        let search = KnowledgeFrameTool(name: .frameSearch, store: stores.knowledge)

        let listResult = try list.execute(arguments: [:], context: ToolExecutionContext(source: .developerTool))
        let searchResult = try search.execute(
            arguments: ["query": .string("notarization")],
            context: ToolExecutionContext(source: .developerTool)
        )

        XCTAssertEqual(listResult.output["count"], .number(2))
        XCTAssertEqual(listResult.output["frames"]?.arrayValue?.count, 2)
        XCTAssertEqual(searchResult.output["count"], .number(1))
        let frames = try XCTUnwrap(searchResult.output["frames"]?.arrayValue)
        let frame = try XCTUnwrap(frames.first?.objectValue)
        XCTAssertEqual(frame["id"], .number(Double(release.id)))
        XCTAssertEqual(frame["name"], .string("Release readiness frame"))
        XCTAssertEqual(frame["body"], .string("Use notarization and checksum before alpha release."))
        XCTAssertEqual(frame["triggers"], .array([.string("release"), .string("alpha")]))
    }

    func testKnowledgeFrameDeleteToolDeletesFrameAndSearchIndexWithApproval() throws {
        let stores = try makeStores()
        let frame = try stores.knowledge.create(
            name: "Stale frame",
            body: "Remove this stale launch note.",
            triggers: ["release"]
        )
        let delete = KnowledgeFrameTool(name: .frameDelete, store: stores.knowledge)
        let search = KnowledgeFrameTool(name: .frameSearch, store: stores.knowledge)

        let result = try delete.execute(
            arguments: ["id": .number(Double(frame.id))],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["frameId"], .number(Double(frame.id)))
        XCTAssertThrowsError(try stores.knowledge.get(id: frame.id))
        let searchResult = try search.execute(
            arguments: ["query": .string("stale")],
            context: ToolExecutionContext(source: .developerTool)
        )
        XCTAssertEqual(searchResult.output["count"], .number(0))
        XCTAssertEqual(searchResult.output["frames"], .array([]))
    }

    func testKnowledgeFrameCreateRejectsNonStringTriggersWithoutCreatingFrame() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)

        XCTAssertThrowsError(
            try create.execute(
                arguments: [
                    "name": .string("Release checklist"),
                    "body": .string("Use notarization."),
                    "triggers": .array([.string("release"), .number(1)])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameCreate, "Argument 'triggers[1]' must be string."))
        }

        XCTAssertEqual(try stores.knowledge.list(), [])
    }

    func testKnowledgeFrameUpdatePreservesTriggersWhenOmitted() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)
        let update = KnowledgeFrameTool(name: .frameUpdate, store: stores.knowledge)

        let created = try create.execute(
            arguments: [
                "name": .string("Writing frame"),
                "body": .string("Initial"),
                "triggers": .array([.string("writing")])
            ],
            context: approvedContext()
        )
        let frameID = try XCTUnwrap(created.output["frameId"]?.int64Value)

        _ = try update.execute(
            arguments: [
                "id": .number(Double(frameID)),
                "body": .string("Updated")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(try stores.knowledge.get(id: frameID).triggers, ["writing"])
    }

    func testKnowledgeFrameUpdateRejectsBlankTriggersWithoutMutatingFrame() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)
        let update = KnowledgeFrameTool(name: .frameUpdate, store: stores.knowledge)

        let created = try create.execute(
            arguments: [
                "name": .string("Writing frame"),
                "body": .string("Initial"),
                "triggers": .array([.string("release")])
            ],
            context: approvedContext()
        )
        let frameID = try XCTUnwrap(created.output["frameId"]?.int64Value)

        XCTAssertThrowsError(
            try update.execute(
                arguments: [
                    "id": .number(Double(frameID)),
                    "triggers": .array([.string("writing"), .string("  ")])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameUpdate, "Argument 'triggers[1]' cannot be blank."))
        }

        XCTAssertEqual(try stores.knowledge.get(id: frameID).triggers, ["release"])
    }

    func testKnowledgeFrameUpdateRejectsBlankBodyWithoutMutatingFrame() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)
        let update = KnowledgeFrameTool(name: .frameUpdate, store: stores.knowledge)
        let created = try create.execute(
            arguments: [
                "name": .string("Release frame"),
                "body": .string("Initial content")
            ],
            context: approvedContext()
        )
        let frameID = try XCTUnwrap(created.output["frameId"]?.int64Value)

        XCTAssertThrowsError(
            try update.execute(
                arguments: [
                    "id": .number(Double(frameID)),
                    "body": .string("   ")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameUpdate, "Argument 'body' cannot be blank."))
        }

        XCTAssertEqual(try stores.knowledge.get(id: frameID).body, "Initial content")
    }

    func testPhase2CoreRegistryContainsProjectTaskAndKnowledgeTools() throws {
        let stores = try makeStores()
        let registry = try ToolRegistry.phase2Core(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            knowledgeStore: stores.knowledge
        )

        XCTAssertTrue(registry.contains(.projectCreate))
        XCTAssertTrue(registry.contains(.projectDelete))
        XCTAssertTrue(registry.contains(.taskGet))
        XCTAssertTrue(registry.contains(.taskCreate))
        XCTAssertTrue(registry.contains(.taskDelete))
        XCTAssertTrue(registry.contains(.frameSearch))
        XCTAssertTrue(registry.contains(.frameDelete))
    }

    private func makeStores() throws -> (
        connection: SQLiteConnection,
        projects: SQLiteProjectStore,
        tasks: SQLiteTaskStore,
        knowledge: SQLiteKnowledgeFrameStore
    ) {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
        return (
            connection,
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteKnowledgeFrameStore(connection: connection)
        )
    }

    private func approvedContext() -> ToolExecutionContext {
        ToolExecutionContext(approvalToken: ApprovalToken(id: "approval-1", sessionID: "session-1"), source: .developerTool)
    }
}

private enum TestMigrationRunner {
    static func migrate(connection: SQLiteConnection, migrations: [DatabaseMigration]) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )
        let alreadyApplied = Set(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;"))
        for migration in migrations where !alreadyApplied.contains(migration.id) {
            try migration.apply(connection)
            try connection.execute("INSERT INTO schema_migrations (id) VALUES ('\(migration.id)');")
        }
    }
}

private extension JSONValue {
    var int64Value: Int64? {
        guard case .number(let value) = self else {
            return nil
        }
        return Int64(value)
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let values) = self else {
            return nil
        }
        return values
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let values) = self else {
            return nil
        }
        return values
    }
}
