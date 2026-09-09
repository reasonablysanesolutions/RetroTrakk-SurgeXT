// RetroTrakk — JGXProject.swift
// Jimmy Granlund eXtended Tracker format (.jgx)

import Foundation

public struct JGXProject: Codable {
    public static let currentVersion = 1
    public static let formatIdentifier = "jgx"
    public static let defaultAuthor = "Jimmy Granlund"
    public static let defaultAppName = "RetroTrakk"

    public var format: String
    public var version: Int
    public var generator: String
    public var author: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var song: SongModel

    public init(
        song: SongModel,
        author: String = JGXProject.defaultAuthor,
        generator: String = JGXProject.defaultAppName,
        version: Int = JGXProject.currentVersion,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.format = JGXProject.formatIdentifier
        self.version = version
        self.generator = generator
        self.author = author
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.song = song
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> SongModel {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Försök först avkoda som JGXProject
        if let project = try? decoder.decode(JGXProject.self, from: data) {
            return project.song
        }
        // Fallback: Äldre rå JSON SongModel
        return try decoder.decode(SongModel.self, from: data)
    }

    public static func loadProject(from data: Data) throws -> (song: SongModel, project: JGXProject?) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let project = try? decoder.decode(JGXProject.self, from: data) {
            return (project.song, project)
        }
        let song = try decoder.decode(SongModel.self, from: data)
        return (song, nil)
    }

    public static func save(song: SongModel, to url: URL, author: String = JGXProject.defaultAuthor) throws {
        var existingCreatedAt = Date()
        if FileManager.default.fileExists(atPath: url.path),
           let existingData = try? Data(contentsOf: url),
           let existing = try? loadProject(from: existingData).project {
            existingCreatedAt = existing.createdAt
        }
        let project = JGXProject(
            song: song,
            author: author,
            createdAt: existingCreatedAt,
            modifiedAt: Date()
        )
        let data = try project.encode()
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> SongModel {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }
}
