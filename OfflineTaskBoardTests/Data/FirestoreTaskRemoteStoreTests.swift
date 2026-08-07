//
//  FirestoreTaskRemoteStoreTests.swift
//  OfflineTaskBoardTests
//
//  Created by Vaishnav on 07/08/26.
//

#if canImport(FirebaseFirestore)
import XCTest
import FirebaseFirestore
@testable import OfflineTaskBoard

/// Tests the pure Firestore <-> TaskItem mapping — no network, no emulator. `Timestamp` and
/// `[String: Any]` dictionaries are plain values the SDK lets you construct standalone, so the
/// decode path is exercised via `init(firestoreDocumentID:fields:)` rather than a real
/// `QueryDocumentSnapshot`, which can only come from an actual Firestore call.
///
/// Compiled only when the Firebase package is linked. It's linked into the app target directly;
/// the test target intentionally does *not* re-link the Firestore/abseil/gRPC/leveldb/nanopb
/// binary products itself — Xcode's separately-linked test-bundle variant of those hits a real
/// upstream linker bug on this Xcode 26 toolchain (github.com/firebase/firebase-ios-sdk#15642)
/// even though the app target links the exact same products fine. Since XCTest unit test bundles
/// run in-process inside the host app, these tests still execute against the app's already-linked
/// Firestore symbols without needing their own separate link.
final class FirestoreTaskRemoteStoreTests: XCTestCase {
    func testDecodingAWellFormedDocumentProducesASyncedTask() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let updatedAt = Date(timeIntervalSince1970: 1_060)
        let fields: [String: Any] = [
            "title": "From the cloud",
            "notes": "some notes",
            "status": TaskStatus.inProgress.rawValue,
            "sortOrder": 2.0,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
        ]

        let task = try TaskItem(firestoreDocumentID: id.uuidString, fields: fields)

        XCTAssertEqual(task.id, id)
        XCTAssertEqual(task.title, "From the cloud")
        XCTAssertEqual(task.notes, "some notes")
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.sortOrder, 2.0)
        XCTAssertEqual(task.createdAt, createdAt)
        XCTAssertEqual(task.updatedAt, updatedAt)
        XCTAssertEqual(task.syncStatus, .synced, "anything fetched from the server is, by definition, synced")
        XCTAssertEqual(task.lastSyncedUpdatedAt, updatedAt)
    }

    func testDecodingDefaultsMissingNotesToEmptyString() throws {
        let fields: [String: Any] = [
            "title": "No notes field",
            "status": TaskStatus.todo.rawValue,
            "sortOrder": 0.0,
            "createdAt": Timestamp(date: .now),
            "updatedAt": Timestamp(date: .now),
        ]

        let task = try TaskItem(firestoreDocumentID: UUID().uuidString, fields: fields)
        XCTAssertEqual(task.notes, "")
    }

    func testDecodingThrowsOnNonUUIDDocumentID() {
        let fields: [String: Any] = [
            "title": "x", "status": TaskStatus.todo.rawValue, "sortOrder": 0.0,
            "createdAt": Timestamp(date: .now), "updatedAt": Timestamp(date: .now),
        ]
        XCTAssertThrowsError(try TaskItem(firestoreDocumentID: "not-a-uuid", fields: fields)) { error in
            guard case RemoteDataSourceError.decodingFailed = error else {
                return XCTFail("expected decodingFailed, got \(error)")
            }
        }
    }

    func testDecodingThrowsOnMissingTitle() {
        let fields: [String: Any] = [
            "status": TaskStatus.todo.rawValue, "sortOrder": 0.0,
            "createdAt": Timestamp(date: .now), "updatedAt": Timestamp(date: .now),
        ]
        XCTAssertThrowsError(try TaskItem(firestoreDocumentID: UUID().uuidString, fields: fields))
    }

    func testDecodingThrowsOnInvalidStatus() {
        let fields: [String: Any] = [
            "title": "x", "status": "not-a-real-status", "sortOrder": 0.0,
            "createdAt": Timestamp(date: .now), "updatedAt": Timestamp(date: .now),
        ]
        XCTAssertThrowsError(try TaskItem(firestoreDocumentID: UUID().uuidString, fields: fields))
    }

    func testEncodedFieldsRoundTripThroughDecoding() throws {
        let original = TaskItem(
            title: "Round trip", notes: "notes here", status: .done, sortOrder: 5,
            createdAt: Date(timeIntervalSince1970: 500), updatedAt: Date(timeIntervalSince1970: 600)
        )

        let decoded = try TaskItem(firestoreDocumentID: original.id.uuidString, fields: original.firestoreFields)

        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.notes, original.notes)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.sortOrder, original.sortOrder)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
        XCTAssertEqual(decoded.updatedAt, original.updatedAt)
    }
}
#endif
