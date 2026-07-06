import Foundation

struct PersistenceService {
    private static var fileURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent("workflow_history.json")
    }

    static func save(workflows: [WorkflowRun]) {
        guard let url = fileURL else { return }
        try? (try? JSONEncoder().encode(workflows))?.write(to: url, options: .atomic)
    }

    static func load() -> [WorkflowRun] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let workflows = try? JSONDecoder().decode([WorkflowRun].self, from: data)
        else { return [] }
        return workflows
    }
}
