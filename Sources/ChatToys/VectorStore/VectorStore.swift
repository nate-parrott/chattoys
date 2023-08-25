import Foundation
import SQLite3

public struct VectorStoreRecord<RecordData: Equatable & Codable>: Equatable, Codable {
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
}

// struct EmbeddedVectorStoreRecord<T: VectorStoreRecord>: Equatable, Codable {
//     let vector: [Float]
//     let record: T
// }

enum VectorStoreError: Error {
    case sqliteError(message: String)
}

public class VectorStore<RecordData: Codable & Equatable> {
    public typealias Record = VectorStoreRecord<RecordData>

    // We'll store our records in a sqlite full-text database, and later, a vector store
    private let db: OpaquePointer
    // TODO: Add vector store

    // URL points to a directory in which we'll write two files: a sqlite database and a vector store
    public init(url: URL) throws {
        // Ensure dir is created for URL
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // Open sqlite database
        let dbPath = url.appendingPathComponent("db.sqlite").path
        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
        }
        self.db = db!

        // Create table for records, using ID as primary key and full-text indexing on `text`
        // We will store `recordData` as binary data
        // Index on `date`
        let createTableQuery = """
        CREATE TABLE IF NOT EXISTS records (
            id TEXT PRIMARY KEY,
            date REAL,
            text TEXT,
            recordData BLOB
        );
        CREATE INDEX IF NOT EXISTS date_index ON records (date);
        CREATE VIRTUAL TABLE IF NOT EXISTS records_fts USING fts5(text);
        """
        // run create table query
        if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
            throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    public func insert(records: [Record]) async throws {
        // Insert into sqlite
        let insertQuery = "INSERT INTO records (id, date, text, recordData) VALUES (?, ?, ?, ?);"
        for record in records {
            // Serialize record data
            let recordData = try JSONEncoder().encode(record.data)
            // Bind values to query
            let id = record.id
            let date = record.date.timeIntervalSince1970
            let text = record.text
            let recordDataBytes = [UInt8](recordData)
//            let recordDataBytesPointer = UnsafeRawPointer(recordDataBytes)
//            let recordDataBytesLength = recordDataBytes.count
            try recordDataBytes.withUnsafeBytes { bytes in
                // Prepare query
                var statement: OpaquePointer?
                if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) != SQLITE_OK {
                    throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
                }
                // Bind values to query
                if sqlite3_bind_text(statement, 1, id, -1, nil) != SQLITE_OK {
                    throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
                }
                if sqlite3_bind_double(statement, 2, date) != SQLITE_OK {
                    throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
                }
                if sqlite3_bind_text(statement, 3, text, -1, nil) != SQLITE_OK {
                    throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
                }
                if sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), nil) != SQLITE_OK {
                    throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
                }
                // Run query
                if sqlite3_step(statement) != SQLITE_DONE {
                    throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
                }
                // Finalize query
                if sqlite3_finalize(statement) != SQLITE_OK {
                    throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
                }
            }
        }
    }

    public func record(forId id: String) async throws -> Record? {
        return nil
//        // Prepare query
//        let query = "SELECT id, date, text, recordData FROM records WHERE id = ?;"
//        var statement: OpaquePointer?
//        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
//            throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
//        }
//        // Bind values to query
//        if sqlite3_bind_text(statement, 1, id, -1, nil) != SQLITE_OK {
//            throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
//        }
//        // Run query
//        if sqlite3_step(statement) != SQLITE_ROW {
//            throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
//        }
//        // Get values from query
//        let id = String(cString: sqlite3_column_text(statement, 0))
//        let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
//        let text = String(cString: sqlite3_column_text(statement, 2))
//        let recordDataBytes = sqlite3_column_blob(statement, 3)
//        let recordDataBytesLength = sqlite3_column_bytes(statement, 3)
//        let recordDataBytesPointer = UnsafeRawPointer(recordDataBytes)
//        let recordDataBytesBuffer = UnsafeBufferPointer<UInt8>(start: recordDataBytesPointer, count: Int(recordDataBytesLength))
//        let recordData = Data(recordDataBytesBuffer)
//        let record = try JSONDecoder().decode(RecordData.self, from: recordData)
//        // Finalize query
//        if sqlite3_finalize(statement) != SQLITE_OK {
//            throw VectorStoreError.sqliteError(message: String(cString: sqlite3_errmsg(db)))
//        }
//        return Record(id: id, date: date, text: text, data: record)
    }

    public func fullTextSearch(query: String, limit: Int = 10) async throws -> [Record] {
        // TODO
        return []
    }

    public func embeddingSearch(query: String) async throws -> [Record] {
        // TODO
        return []
    }
}
