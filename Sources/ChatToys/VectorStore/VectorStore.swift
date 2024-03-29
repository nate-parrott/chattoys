import Foundation
import GRDB

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct VectorStoreRecord<RecordData: Equatable & Codable>: Equatable, Codable {
    public var id: String
    public var group: String
    public var date: Date
    public var text: String
    public var data: RecordData

    // `text` should fit an OpenAI embedding model, 8k tokens
    public init(id: String, group: String?, date: Date, text: String, data: RecordData) {
        self.id = id
        self.group = group ?? ""
        self.date = date
        self.text = text
        self.data = data
    }
}

private struct VectorStoreRecordInternal<RecordData: Equatable & Codable>: Equatable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var group: String
    var date: Date
    var text: String
    var embedding: Data
    var data: RecordData

    init(record: VectorStoreRecord<RecordData>, embedding: Embedding) {
        self.id = record.id
        self.group = record.group
        self.date = record.date
        self.text = record.text
        self.embedding = embedding.dataHalfPrecision
        self.data = record.data
    }

    func record() -> VectorStoreRecord<RecordData> {
        VectorStoreRecord(id: id, group: group, date: date, text: text, data: data)
    }

    func loadedEmbedding(provider: String) -> Embedding? {
        Embedding(data: embedding, halfPrecision: true, provider: provider)
    }

    public static var databaseTableName: String { "record" }
}

enum VectorStoreError: Error {
    case sqliteError(message: String)
}

public class VectorStore<RecordData: Codable & Equatable> {
    public typealias Record = VectorStoreRecord<RecordData>
    private typealias InternalRecord = VectorStoreRecordInternal<RecordData>

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
//        var nextVectorStoreId: USearchKey = 1
//        var deletedVectorsCount: Int = 0
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
                    t.column("embedding", .blob)
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
//        self.vectorStore = USearchIndex.make(metric: .cos, dimensions: UInt32(embedder.dimensions), connectivity: 16, quantization: .F16)
//        if let path = vectorStoreURL?.path, FileManager.default.fileExists(atPath: path) {
//            vectorStore.load(path: path) // TODO: properly handle the NSException
//        }

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

    // public func rebuild() {
    //     // TODO: Implement. lock the data structure, clear the vector store and re-insert everything
    // }

    // MARK: - API

    public func save(sync: Bool) {
        func actuallySave() {
//            if let path = vectorStoreURL?.path {
//                vectorStore.save(path: path)
//            }
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

    /// TODO: should we take out a lock when doing this work?
    /// In order for `deletingOldItemsFromGroup` to work properly, there must be no overlap between the IDs that are being added and deleted
    public func insert(records: [Record], deletingOldItemsFromGroup group: String? = nil) async throws {
//        let embeddings = try await embedder.embed(documents: records.map { $0.text })
//        let vectorStoreIds = await assignVectorStoreIds(count: embeddings.count)

        // TODO: Check to see if this data matches existing data before embedding
        let idsToDelete = try await recordIds(forItemsInGroups: group != nil ? [group!] : [])

        let embeddings = try await embedder.embed(documents: records.map { $0.text })
        let internalRecords = records.enumerated().map { VectorStoreRecordInternal(record: $1, embedding: embeddings[$0]) }

        try await dbQueue.write { db in
            // Remove existing records with IDs
            for record in records {
                try InternalRecord.deleteOne(db, key: record.id)
            }

            for record in internalRecords {
                try record.insert(db)
            }
        }

//        await queue.performAsync {
//            self.vectorStore.reserve(UInt32(self.vectorStore.count) + UInt32(embeddings.count) + UInt32(self.metadata.deletedVectorsCount))
//
//            for (i, embedding) in embeddings.enumerated() {
//                self.vectorStore.add(key: vectorStoreIds[i], vector: embedding.vectors)
//            }
//        }

        if idsToDelete.count > 0 {
            try await deleteRecords(ids: idsToDelete)
        }
    }

    public func deleteRecords(ids: [String]) async throws {
        if ids.count == 0 { return }
        // Find all records with these IDs and fetch their vectorIds
        _ = try await dbQueue.write { db in
//            let vectorIds = try Record.filter(keys: ids).fetchAll(db).compactMap { $0.vectorId }
            // now delete
            try InternalRecord.deleteAll(db, keys: ids)
//            return vectorIds
        }

//        await queue.performAsync {
//            self.metadata.deletedVectorsCount += vectorIds.count
//            for vecId in vectorIds {
//                self.vectorStore.remove(key: vecId)
//            }
//        }
    }

    public func deleteRecords(groups: [String]) async throws {
        try await deleteRecords(ids: recordIds(forItemsInGroups: groups))
    }

    private func recordIds(forItemsInGroups groups: [String]) async throws -> [String] {
        if groups.count == 0 { return [] }
        return try await dbQueue.read { db in
            var ids = [String]()
            for group in groups {
                ids.append(contentsOf: try InternalRecord.filter(Column("group") == group).fetchAll(db).map { $0.id })
            }
            return ids
        }
    }

//    private func vectorIds(forRecordIds recordIds: [String]) async throws -> [USearchKey] {
//        try await dbQueue.write { db in
//            let vectorIds = try Record.filter(keys: recordIds).fetchAll(db).compactMap { $0.vectorId }
//            return vectorIds
//        }
//    }

    public func deleteOldestRecords(keep: Int) async throws {
        // Select num_records - keep oldest record IDs and delete them
        let ids = try await dbQueue.read { db in
            let ids = try InternalRecord.order(Column("date").desc).limit(1_000_000, offset: keep).fetchAll(db).map { $0.id }
            return ids
        }
        try await deleteRecords(ids: ids)
    }

    public func record(forId id: String) async throws -> Record? {
        try await dbQueue.read { db in
            try InternalRecord.fetchOne(db, key: id)?.record()
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
            let records = try InternalRecord.fetchAll(db, sql: sql, arguments: [pattern, limit])
            return records.map { $0.record() }
        }
    }

    public func embeddingSearch(query: String, limit: Int = 10) async throws -> [Record] {
        //        let invalidKey: USearchKey = 18446744073709551615
        let embedding = try await embedder.embed(documents: [query])[0]
        let p = embedder.providerString
        // (id, similarity)
        // TODO: Only fetch rows we care about (ignore `data`)
        let itemsToSort: [(String, Float)] = try await dbQueue.read { db in
            return try InternalRecord
//                .fetch
//                .select(Column("id"), Column("embedding"))
                .fetchAll(db)
                .compactMap { ($0.id, $0.loadedEmbedding(provider: p)?.cosineSimilarity(with: embedding) ?? -1) }
        }
        // TODO: Do better than sort
        let ids = itemsToSort.sortedPrefix(limit, by: { $0.1 >= $1.1 }).map { $0.0 }
        let records = try await dbQueue.read { db in
            try InternalRecord.filter(keys: ids).fetchAll(db).map { $0.record() }
        }
        return records.ordered(usingOrderOfIds: ids, id: \.id)
    }
}

extension Array {
    func ordered(usingOrderOfIds ids: [String], id: (Element) -> String) -> [Element] {
        var items = [String: Element]()
        for item in self {
            items[id(item)] = item
        }
        return ids.compactMap { items[$0] }
    }
}

public extension String {
    func chunkForEmbedding(tokenLimit: Int = 2048) -> [String] {
        let maxChunkLength = tokenLimit * 3 // 2048 tokens, roughly
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
