//
//  FirestoreTaskRemoteStore.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation

#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
import FirebaseCore
import FirebaseFirestore

/// Configures Firebase exactly once, and only if a `GoogleService-Info.plist` is actually
/// present — so the app doesn't crash on launch for anyone who's cloned the repo without setting
/// up their own Firebase project. See README for setup steps.
enum FirebaseBootstrap {
    static func configureIfAvailable() {
        guard FirebaseApp.app() == nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
    }

    static var isConfigured: Bool { FirebaseApp.app() != nil }
}

/// Firestore used purely as a remote CRUD endpoint — deliberately not Firestore's own offline
/// cache. SwiftData plus TaskSyncUseCase's outbox is what makes this app offline-first; Firestore
/// here is just "the server," interchangeable with anything else behind `TaskRemoteDataSource`.
struct FirestoreTaskRemoteStore: TaskRemoteDataSource {
    private let collection: CollectionReference

    init(database: Firestore = .firestore()) {
        collection = database.collection("tasks")
    }

    func fetchAll() async throws -> [TaskItem] {
        let snapshot = try await collection.getDocuments()
        return try snapshot.documents.map(TaskItem.init(firestoreDocument:))
    }

    func save(_ task: TaskItem) async throws {
        try await collection.document(task.id.uuidString).setData(task.firestoreFields, merge: false)
    }

    func delete(id: UUID) async throws {
        try await collection.document(id.uuidString).delete()
    }
}

extension TaskItem {
    /// A task fetched from Firestore is, by definition, the confirmed remote state — always
    /// `.synced` with its own `updatedAt` as the baseline.
    init(firestoreDocument document: QueryDocumentSnapshot) throws {
        try self.init(firestoreDocumentID: document.documentID, fields: document.data())
    }

    /// Split out from `init(firestoreDocument:)` so the decoding logic is testable with a plain
    /// dictionary — `QueryDocumentSnapshot` can't be constructed without a live Firestore call,
    /// but `Timestamp` and `[String: Any]` need nothing but the SDK's types.
    init(firestoreDocumentID documentID: String, fields data: [String: Any]) throws {
        guard let id = UUID(uuidString: documentID) else {
            throw RemoteDataSourceError.decodingFailed("document id \(documentID) is not a UUID")
        }
        guard let title = data["title"] as? String else {
            throw RemoteDataSourceError.decodingFailed("missing title")
        }
        guard let statusRaw = data["status"] as? String, let status = TaskStatus(rawValue: statusRaw) else {
            throw RemoteDataSourceError.decodingFailed("missing or invalid status")
        }
        guard let sortOrder = data["sortOrder"] as? Double else {
            throw RemoteDataSourceError.decodingFailed("missing sortOrder")
        }
        guard let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            throw RemoteDataSourceError.decodingFailed("missing createdAt")
        }
        guard let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else {
            throw RemoteDataSourceError.decodingFailed("missing updatedAt")
        }
        let notes = data["notes"] as? String ?? ""

        self.init(
            id: id, title: title, notes: notes, status: status, sortOrder: sortOrder,
            createdAt: createdAt, updatedAt: updatedAt, syncStatus: .synced,
            isDeleted: false, lastSyncedUpdatedAt: updatedAt
        )
    }

    var firestoreFields: [String: Any] {
        [
            "title": title,
            "notes": notes,
            "status": status.rawValue,
            "sortOrder": sortOrder,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
        ]
    }
}
#else
enum FirebaseBootstrap {
    static func configureIfAvailable() {}
    static var isConfigured: Bool { false }
}
#endif
