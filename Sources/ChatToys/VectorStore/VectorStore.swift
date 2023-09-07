import Foundation
import GRDB
import USearch

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif


public struct VectorStoreRecord<RecordData: Equatable & Codable>: Equatable, Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var group: String
    public var date: Date
    public var text: String
    public var data: RecordData
    fileprivate var vectorId: USearchKey?

    // `text` should fit an OpenAI embedding model
    public init(id: String, group: String?, date: Date, text: String, data: RecordData) {
        self.id = id
        self.group = group ?? ""
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

    let vectorStore: USearchIndex
    let url: URL?
    private var vectorStoreURL: URL? {
        url?.appendingPathComponent("vectorstore")
    }

    private var metadataURL: URL? {
        url?.appendingPathComponent("metadata.json")
    }

    private let dbQueue: DatabaseQueue
    private let embedder: any Embedder
    private var notifTokens = [NSObjectProtocol]()
    private let queue = DispatchQueue(label: "VectorStore", qos: .default)

    struct Metadata: Equatable, Codable {
        var nextVectorStoreId: USearchKey = 1
    }

    // Only access these on `self.queue`:
    private var metadata = Metadata()

    // URL points to a directory in which we'll write two files: a sqlite database and a vector store
    public init(url: URL?, embedder: any Embedder) throws {
        self.url = url
        self.embedder = embedder

        // Ensure dir is created for URL
        if let url {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }

        // Open database
        dbQueue = try DatabaseQueue(path: url?.appendingPathComponent("db.sqlite").path ?? ":memory:")
        let tablesExist = try dbQueue.read { db in
            try db.tableExists("record")
        }

        if !tablesExist {
            try dbQueue.write { db in
                // A regular table

                try db.create(table: "record") { t in
                    // primary key is string id
                    t.column("id", .text).primaryKey()
                    t.column("date", .datetime)
                    t.column("group", .text)
                    t.column("text", .text)
                    t.column("data", .blob)
                    t.column("vectorId", .integer)
                }
                // Index on group, and vectorStoreId:
                try db.create(index: "record_group", on: "record", columns: ["group"])
                try db.create(index: "record_vectorStoreId", on: "record", columns: ["vectorId"])

                // A full-text table synchronized with the regular table
                try db.create(virtualTable: "record_ft", using: FTS5()) { t in // or FTS4()
                    t.synchronize(withTable: "record")
                    t.column("text")
                }
            }
        }

        // Setup vector store:
        self.vectorStore = USearchIndex.make(metric: .cos, dimensions: UInt32(embedder.dimensions), connectivity: 16, quantization: .F16)
        if let path = vectorStoreURL?.path, FileManager.default.fileExists(atPath: path) {
            vectorStore.load(path: path) // TODO: properly handle the NSException
        }

        // Setup metadata:
        if let path = metadataURL?.path {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                if let metadata = try? JSONDecoder().decode(Metadata.self, from: data) {
                    self.metadata = metadata
                }
            }
        }

        // Observe app termination to save vector store
        if let notif = NotificationCenter.applicationWillTerminateNotification {
            notifTokens.append(NotificationCenter.default.addObserver(forName: notif, object: nil, queue: nil) { [weak self] _ in
                self?.save(sync: true)
            })
        }
    }

    // MARK: - API

    public func save(sync: Bool) {
        func actuallySave() {
            if let path = vectorStoreURL?.path {
                vectorStore.save(path: path)
            }
            if let path = metadataURL?.path {
                let data = try? JSONEncoder().encode(metadata)
                try? data?.write(to: URL(fileURLWithPath: path))
            }
        }
        if sync {
            queue.sync { actuallySave() }
        } else {
            queue.async { actuallySave() }
        }
    }

    public func insert(records: [Record]) async throws {
        // TODO: Check to see if this data matches existing data before embedding

        let embeddings = try await embedder.embed(documents: records.map { $0.text })
        let vectorStoreIds = await assignVectorStoreIds(count: embeddings.count)

        try await dbQueue.write { db in
            // Remove existing records with IDs
            for record in records {
                try Record.deleteOne(db, key: record.id)
            }

            for (i, record) in records.enumerated() {
                var r2 = record
                r2.vectorId = vectorStoreIds[i]
                try r2.insert(db)
            }
        }

        await queue.performAsync {
            self.vectorStore.reserve(UInt32(self.vectorStore.count) + UInt32(embeddings.count))

            for (i, embedding) in embeddings.enumerated() {
                self.vectorStore.add(key: vectorStoreIds[i], vector: embedding.vectors)
            }
        }
    }

    public func deleteRecords(ids: [String]) async throws {
        if ids.count == 0 { return }
        // Find all records with these IDs and fetch their vectorIds
        let vectorIds = try await dbQueue.write { db in
            let vectorIds = try Record.filter(keys: ids).fetchAll(db).compactMap { $0.vectorId }
            // now delete
            try Record.deleteAll(db, keys: ids)
            return vectorIds
        }
        await queue.performAsync {
            for vecId in vectorIds {
                self.vectorStore.remove(key: vecId)
            }
        }
    }

    public func deleteRecords(groups: [String]) async throws {
        let recordIds = try await dbQueue.read { db in
            var ids = [String]()
            for group in groups {
                ids.append(contentsOf: try Record.filter(Column("group") == group).fetchAll(db).map { $0.id })
            }
            return ids
        }
        try await deleteRecords(ids: recordIds)
    }

    public func deleteOldestRecords(keep: Int) async throws {
        // Select num_records - keep oldest record IDs and delete them
        let ids = try await dbQueue.read { db in
            let ids = try Record.order(Column("date").desc).limit(1_000_000, offset: keep).fetchAll(db).map { $0.id }
            return ids
        }
        try await deleteRecords(ids: ids)
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

    public func embeddingSearch(query: String, limit: Int = 10) async throws -> [Record] {
        let embedding = try await embedder.embed(documents: [query])[0]
        let (vectorIds, _) = await queue.performAsync { self.vectorStore.search(vector: embedding.vectors, count: limit) }
        return try await dbQueue.read { db in
            let matches = vectorIds.compactMap { vectorId in
                // Use sql to find the record matching vectorId
                try? Record.fetchOne(db, sql: "SELECT * FROM record WHERE vectorId = ? LIMIT 1", arguments: [vectorId])
            }
            return matches
        }
    }

    // MARK: - Internal
    func assignVectorStoreIds(count: Int) async -> [USearchKey] {
        await queue.performAsync {
            let nextId = self.metadata.nextVectorStoreId
            let newIds = (0..<count).map { nextId + USearchKey($0) }
            self.metadata.nextVectorStoreId += USearchKey(count)
            return newIds
        }
    }
}

public extension String {
    func chunkForEmbedding() -> [String] {
        let maxChunkLength = 2048 * 3 // 2048 tokens, roughly
        var chunks = [[String]]() // groups of lines
        var currentChunk = [String]()
        var currentChunkLength = 0

        func appendCurrentChunk() {
            if currentChunk.count > 0 {
                chunks.append(currentChunk)
                currentChunk = []
                currentChunkLength = 0
            }
        }

        for line in self.split(separator: "\n") {
            if line.count + currentChunkLength > maxChunkLength {
                appendCurrentChunk()
            }
            // Do not allow single lines to exceed chunk length
            currentChunk.append(String(line).truncateTail(maxLen: maxChunkLength))
            currentChunkLength += line.count
        }
        appendCurrentChunk()

        return chunks.map { $0.joined(separator: "\n") }
    }
}

extension NotificationCenter {
    static var applicationWillTerminateNotification: Notification.Name? {
        #if os(macOS)
        return NSApplication.willTerminateNotification
        #elseif os(iOS)
        return UIApplication.willTerminateNotification
        #else
        return nil
        #endif
    }
}
