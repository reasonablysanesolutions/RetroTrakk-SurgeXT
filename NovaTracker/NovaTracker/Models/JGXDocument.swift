// RetroTrakk — JGXDocument.swift
// FileDocument och UTType-stöd för .jgx-filer

import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
    /// RetroTrakk Project format (.jgx)
    static var jgx: UTType {
        if let declared = UTType(filenameExtension: "jgx") {
            return declared
        }
        return UTType(exportedAs: "com.retrotrakk.jgx", conformingTo: .data)
    }
}

public struct JGXDocument: FileDocument {
    public static var readableContentTypes: [UTType] {
        [
            UTType.jgx,
            UTType(importedAs: "com.retrotrakk.jgx", conformingTo: .data),
            .json
        ]
    }
    public static var writableContentTypes: [UTType] { [UTType.jgx] }

    public var song: SongModel

    public init(song: SongModel) {
        self.song = song
    }

    public init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            song = try JGXProject.decode(from: data)
        } else {
            song = SongModel()
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let project = JGXProject(song: song)
        let data = try project.encode()
        return FileWrapper(regularFileWithContents: data)
    }
}
