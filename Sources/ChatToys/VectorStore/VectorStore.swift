import Foundation
import GRDB

public struct VectorStoreRecord<RecordData: Equatable & Codable>: Equatable, Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var date: Date
    public var text: String
    public var data: RecordData

    public init(id: String, date: Date, text: String, data: RecordData) {
        self.id = id
        self.date = date
        self.text = text
        self.data = data
    }

    public static var databaseTableName: String { "record" }
}

enum VectorStoreError: Error {
    case sqliteError(message: String)
}

public class VectorStore<RecordData: Codable & Equatable> {
    public typealias Record = VectorStoreRecord<RecordData>

    // We'll store our records in a sqlite full-text database, and later, a vector store
    // TODO: Add vector store

    private let dbQueue: DatabaseQueue

    // URL points to a directory in which we'll write two files: a sqlite database and a vector store
    public init(url: URL?) throws {
        // Ensure dir is created for URL
        if let url {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }

        // Open database
        dbQueue = try DatabaseQueue(path: url?.appendingPathComponent("db.sqlite").path ?? ":memory:")

        try dbQueue.write { db in
            // A regular table

            try db.create(table: "record") { t in
                // primary key is string id
                t.column("id", .text).primaryKey()
                t.column("date", .datetime)
                t.column("text", .text)
                t.column("data", .blob)
            }

             // A full-text table synchronized with the regular table
             try db.create(virtualTable: "record_ft", using: FTS5()) { t in // or FTS4()
                 t.synchronize(withTable: "record")
                 t.column("text")
             }
        }
    }

    public func insert(records: [Record]) async throws {
        try await dbQueue.write { db in
            for record in records {
                try record.insert(db)
            }
        }
    }

    public func record(forId id: String) async throws -> Record? {
        try await dbQueue.read { db in
            try Record.fetchOne(db, key: id)
        }
    }

    public func fullTextSearch(query: String, limit: Int = 10) async throws -> [Record] {
        try await dbQueue.read { db in
            let sql = """
            SELECT record.*
            FROM record
            JOIN record_ft
                ON record_ft.rowid = record.rowid
                AND record_ft MATCH ?
                ORDER by bm25(record_ft)
                LIMIT ?
            """
            let pattern = FTS5Pattern(matchingAnyTokenIn: query)
            let records = try Record.fetchAll(db, sql: sql, arguments: [pattern, limit])
            return records
        }
    }

    public func embeddingSearch(query: String) async throws -> [Record] {
        // TODO
        return []
    }
}
