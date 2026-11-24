import Foundation

struct Project: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
}

enum PointSource: String, Codable, CaseIterable, Sendable {
    case device, imported

    var title: String {
        switch self {
        case .device: return L.t("source.device")
        case .imported: return L.t("source.imported")
        }
    }
}

struct Waypoint: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let seq: Int
    let projectID: UUID?
    let coordinate: Coordinate
    let accuracy: Double?
    let fixTime: Date?
    let savedTime: Date
    var name: String
    let source: PointSource
    let quality: Quality
    let legacyExport: Bool

    var number: String { String(format: "%03d", seq) }
    var displayName: String {
        if !name.isEmpty { return name }
        return source == .imported ? L.t("source.imported") : L.f("point.numbered", number)
    }
}

struct PointFilter: Equatable {
    var quality: Quality?
    var source: PointSource?
    var since: Date?

    func includes(_ point: Waypoint) -> Bool {
        (quality == nil || point.quality == quality) &&
        (source == nil || point.source == source) &&
        (since.map { point.savedTime >= $0 } ?? true)
    }
}

struct Library: Codable, Sendable {
    var projects: [Project] = []
    var points: [Waypoint] = []
    var activeProjectID: UUID?
    var nextSequence = 1
    var milestones = Milestones()

    func projectName(_ id: UUID?) -> String {
        projects.first { $0.id == id }?.name ?? L.t("project.unfiled")
    }

    func rows(for projectID: UUID?, filter: PointFilter = PointFilter()) -> [Waypoint] {
        points.filter { $0.projectID == projectID && filter.includes($0) }
            .sorted { $0.seq < $1.seq }
    }

    func export(for projectID: UUID?, filter: PointFilter, pro: Bool) -> ExportSnapshot {
        ExportSnapshot(project: projectName(projectID),
                       points: rows(for: projectID, filter: filter).filter { pro || $0.legacyExport })
    }
}

enum LibraryError: Error, Equatable {
    case duplicate, invalidFix, invalidName, unavailable
}

actor WaypointStore {
    private let file: URL?
    private var current: Library?

    init(file: URL?, initial: Library? = nil) {
        self.file = file
        current = initial
    }

    func load() throws -> Library {
        if let current { return current }
        let value: Library
        if let file {
            do {
                value = try JSONDecoder().decode(Library.self, from: Data(contentsOf: file))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                value = Library()
            }
        } else {
            value = Library()
        }
        current = value
        return value
    }

    private func commit(_ change: (inout Library) throws -> Void) throws -> Library {
        var updated = try load()
        try change(&updated)
        if let file {
            try LocalFiles.prepare(file.deletingLastPathComponent())
            try JSONEncoder().encode(updated).write(to: file, options: [.atomic, .completeFileProtection])
        }
        current = updated
        return updated
    }

    func save(_ fix: Fix, now: Date, projectID: UUID?, pro: Bool) throws -> (Library, Waypoint) {
        guard fix.isUsable(at: now) else { throw LibraryError.invalidFix }
        let library = try commit { state in
            let duplicate = state.points.suffix(12).contains {
                $0.source == .device && $0.fixTime == fix.time &&
                $0.coordinate == fix.coordinate && abs(now.timeIntervalSince($0.savedTime)) < 0.8
            }
            guard !duplicate else { throw LibraryError.duplicate }
            state.points.append(Waypoint(seq: state.nextSequence, projectID: pro ? projectID : nil,
                                        coordinate: fix.coordinate, accuracy: fix.accuracy, fixTime: fix.time,
                                        savedTime: now, name: "", source: .device, quality: fix.quality,
                                        legacyExport: pro))
            state.nextSequence += 1
            state.milestones.recordDevicePoint(at: now)
            state.milestones.coreReviewProgress = .recording(state.milestones.coreReviewProgress, at: now)
        }
        guard let point = library.points.last else { throw LibraryError.unavailable }
        return (library, point)
    }

    func add(_ code: ShareCode, now: Date, pro: Bool) throws -> Library {
        guard code.isValid else { throw LibraryError.invalidFix }
        return try commit { state in
            let coordinate = code.coordinate
            let duplicate = state.points.contains {
                $0.source == .imported &&
                ($0.coordinate.latitude * 10_000_000).rounded() == (coordinate.latitude * 10_000_000).rounded() &&
                ($0.coordinate.longitude * 10_000_000).rounded() == (coordinate.longitude * 10_000_000).rounded()
            }
            guard !duplicate else { throw LibraryError.duplicate }
            state.points.append(Waypoint(seq: state.nextSequence, projectID: nil, coordinate: coordinate,
                                        accuracy: code.accuracy, fixTime: nil, savedTime: now,
                                        name: code.name ?? "", source: .imported,
                                        quality: code.quality ?? .unknown, legacyExport: pro))
            state.nextSequence += 1
        }
    }

    func createProject(_ name: String) throws -> Library {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw LibraryError.invalidName }
        return try commit { state in
            let project = Project(name: name)
            state.projects.append(project)
            state.activeProjectID = project.id
        }
    }

    func selectProject(_ id: UUID?) throws -> Library {
        try commit { $0.activeProjectID = id }
    }

    func renameProject(_ id: UUID, name: String) throws -> Library {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw LibraryError.invalidName }
        return try commit { state in
            guard let index = state.projects.firstIndex(where: { $0.id == id }) else { return }
            state.projects[index].name = name
        }
    }

    func renamePoint(_ id: UUID, name: String) throws -> Library {
        guard name.count <= 80 else { throw LibraryError.invalidName }
        return try commit { state in
            guard let index = state.points.firstIndex(where: { $0.id == id }) else { return }
            state.points[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func deletePoint(_ id: UUID) throws -> Library {
        try commit { $0.points.removeAll { $0.id == id } }
    }

    func completeShare() throws -> Library {
        try commit { $0.milestones.completedShare = true }
    }

    func markReview(attemptIfEligible eligible: Bool) throws -> Library {
        try commit { state in
            if eligible && state.milestones.canRequestReview { state.milestones.reviewAttempted = true }
        }
    }
}

enum LocalFiles {
    static func prepare(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
