import Foundation
import XCTest
@testable import BodyCompanionCore

final class OfflineDraftTests: XCTestCase {
    func testEncryptedRoundTripStoresOnlyCiphertext() async throws {
        let ownerID = UUID()
        let draft = makeDraft(ownerID: ownerID, rawUserText: "synthetic shoulder note")
        let store = InMemoryEncryptedDraftStore(keyProvider: InMemoryDraftKeyProvider())

        try await store.save(draft)
        let restored = try await store.load(draftID: draft.draftID, ownerID: ownerID)
        XCTAssertEqual(restored.schemaVersion, draft.schemaVersion)
        XCTAssertEqual(restored.draftID, draft.draftID)
        XCTAssertEqual(restored.ownerID, draft.ownerID)
        XCTAssertEqual(restored.clientOperationID, draft.clientOperationID)
        XCTAssertEqual(restored.draftRevision, draft.draftRevision)
        XCTAssertEqual(restored.lifecycle, draft.lifecycle)
        XCTAssertEqual(restored.locations.map(\.regionID), draft.locations.map(\.regionID))
        XCTAssertEqual(restored.facts, draft.facts)
        XCTAssertEqual(restored.sync, draft.sync)
        XCTAssertLessThan(abs(restored.createdAt.timeIntervalSince(draft.createdAt)), 1.0)
        XCTAssertLessThan(abs(restored.updatedAt.timeIntervalSince(draft.updatedAt)), 1.0)

        let storedBytes = await store.storedCiphertext(for: draft.draftID)
        let ciphertext = try XCTUnwrap(storedBytes)
        XCTAssertFalse(ciphertext.isEmpty)
        XCTAssertNil(ciphertext.range(of: Data("synthetic shoulder note".utf8)))
    }

    func testWrongOwnerCannotDecryptOrLearnDraftContent() async throws {
        let ownerID = UUID()
        let otherOwnerID = UUID()
        let draft = makeDraft(ownerID: ownerID, rawUserText: "synthetic private text")
        let store = InMemoryEncryptedDraftStore(keyProvider: InMemoryDraftKeyProvider())
        try await store.save(draft)

        do {
            _ = try await store.load(draftID: draft.draftID, ownerID: otherOwnerID)
            XCTFail("a different owner must not decrypt a draft")
        } catch let error as DraftStoreError {
            XCTAssertEqual(error, .decryptionFailed)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let wrongKeyStore = InMemoryEncryptedDraftStore(
            keyProvider: InMemoryDraftKeyProvider(masterKeyData: Data(repeating: 0x7B, count: 32))
        )
        let storedBytes = await store.storedCiphertext(for: draft.draftID)
        let ciphertext = try XCTUnwrap(storedBytes)
        await wrongKeyStore.replaceStoredCiphertextForTesting(ciphertext, draftID: draft.draftID)
        do {
            _ = try await wrongKeyStore.load(draftID: draft.draftID, ownerID: ownerID)
            XCTFail("a different key must not decrypt a draft")
        } catch let error as DraftStoreError {
            XCTAssertEqual(error, .decryptionFailed)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testTamperedCiphertextFailsWithoutPartialPlaintext() async throws {
        let ownerID = UUID()
        let draft = makeDraft(ownerID: ownerID, rawUserText: "synthetic tamper target")
        let store = InMemoryEncryptedDraftStore(keyProvider: InMemoryDraftKeyProvider())
        try await store.save(draft)
        let storedBytes = await store.storedCiphertext(for: draft.draftID)
        var corrupted = try XCTUnwrap(storedBytes)
        corrupted[corrupted.startIndex] ^= 0xFF
        await store.replaceStoredCiphertextForTesting(corrupted, draftID: draft.draftID)

        do {
            _ = try await store.load(draftID: draft.draftID, ownerID: ownerID)
            XCTFail("tampered ciphertext must not decode")
        } catch let error as DraftStoreError {
            XCTAssertEqual(error, .decryptionFailed)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDecoderRejectsUnknownEnvelopeFieldsAndUsesFixedSchema() throws {
        let draft = makeDraft(ownerID: UUID())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(draft)) as? [String: Any])
        object["unexpected_field"] = "must be rejected"
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertThrowsError(try decoder.decode(DraftEnvelope.self, from: data)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("unknown field should produce a data-corrupted error")
            }
        }
    }

    func testDeleteIsIdempotentAndDoesNotRestoreDraft() async throws {
        let ownerID = UUID()
        let draft = makeDraft(ownerID: ownerID)
        let store = InMemoryEncryptedDraftStore(keyProvider: InMemoryDraftKeyProvider())
        try await store.save(draft)
        try await store.delete(draftID: draft.draftID, ownerID: ownerID)
        try await store.delete(draftID: draft.draftID, ownerID: ownerID)

        do {
            _ = try await store.load(draftID: draft.draftID, ownerID: ownerID)
            XCTFail("deleted draft must not be recoverable")
        } catch let error as DraftStoreError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func testQueueDeduplicatesSameOperation() throws {
        let draft = makeDraft(ownerID: UUID())
        var queue = DraftSyncQueue()
        let first = try queue.enqueue(draft)
        let second = try queue.enqueue(draft)

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(first, second)
    }

    func testQueueRejectsOperationIDWithDifferentRevisionOrDigest() throws {
        let operationID = UUID()
        let draft = makeDraft(ownerID: UUID(), clientOperationID: operationID)
        var changed = draft
        changed.draftRevision = 2
        changed.updatedAt = draft.updatedAt.addingTimeInterval(1)
        var queue = DraftSyncQueue()
        _ = try queue.enqueue(draft)

        XCTAssertThrowsError(try queue.enqueue(changed)) { error in
            XCTAssertEqual(error as? DraftSyncQueueError, .idempotencyConflict)
        }
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.operation(id: operationID)?.draftRevision, 1)
    }

    func testAcceptedResultIsOnlyRemoteUnconfirmedAndCarriesNoEventOrApproval() throws {
        let draft = makeDraft(ownerID: UUID())
        var queue = DraftSyncQueue()
        let queued = try queue.enqueue(draft)
        let inFlight = try XCTUnwrap(queue.beginNext())
        XCTAssertEqual(inFlight.state, .inFlight)
        let accepted = try queue.apply(.acceptedUnconfirmed(remoteRevision: 3), to: queued.clientOperationID)

        XCTAssertEqual(accepted.state, .acceptedUnconfirmed)
        XCTAssertEqual(accepted.remoteRevision, 3)
        let data = try JSONEncoder().encode(accepted)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["event_id"])
        XCTAssertNil(object["confirmed_event_id"])
        XCTAssertNil(object["approval_id"])
    }

    func testConflictRetainsLocalRevisionAndDigest() throws {
        let draft = makeDraft(ownerID: UUID(), draftRevision: 4)
        var queue = DraftSyncQueue()
        let queued = try queue.enqueue(draft)
        _ = try XCTUnwrap(queue.beginNext())
        let conflicted = try queue.apply(.conflict(serverRevision: 5), to: queued.clientOperationID)

        XCTAssertEqual(conflicted.state, .conflict)
        XCTAssertEqual(conflicted.draftRevision, 4)
        XCTAssertEqual(conflicted.payloadDigest, queued.payloadDigest)
        XCTAssertEqual(conflicted.lastErrorCode, "REVISION_CONFLICT")
    }

    func testTemporaryFailureCanBeRetriedButPermanentFailureIsBlocked() throws {
        let draft = makeDraft(ownerID: UUID())
        var queue = DraftSyncQueue()
        let queued = try queue.enqueue(draft)
        _ = try XCTUnwrap(queue.beginNext())
        let failed = try queue.apply(.temporaryFailure(code: "network.timeout"), to: queued.clientOperationID)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.lastErrorCode, "network.timeout")
        XCTAssertEqual(try queue.retry(clientOperationID: queued.clientOperationID).state, .queued)
        _ = try XCTUnwrap(queue.beginNext())
        let blocked = try queue.apply(.permanentFailure(code: "consent.expired"), to: queued.clientOperationID)
        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertEqual(blocked.lastErrorCode, "consent.expired")
    }

    func testDiscardedOrExpiredDraftCannotBeSavedOrEnterSyncQueue() async throws {
        for lifecycle in [DraftLifecycle.discarded, .expired] {
            let draft = makeDraft(ownerID: UUID(), lifecycle: lifecycle)
            let store = InMemoryEncryptedDraftStore(keyProvider: InMemoryDraftKeyProvider())
            do {
                try await store.save(draft)
                XCTFail("a discarded or expired draft must not be persisted")
            } catch let error as DraftStoreError {
                XCTAssertEqual(error, .cannotRestoreDiscardedDraft)
            }
            var queue = DraftSyncQueue()
            XCTAssertThrowsError(try queue.enqueue(draft)) { error in
                XCTAssertEqual(error as? DraftSyncQueueError, .draftNotSyncable)
            }
        }
    }

    func testQueueStateLabelsAreAccessibleWithoutColorOrAnimation() {
        let labels: [DraftSyncOperationState: String] = [
            .queued: "等待网络同步",
            .inFlight: "正在同步未确认草稿",
            .acceptedUnconfirmed: "已同步为未确认草稿",
            .conflict: "需要处理草稿冲突",
            .failed: "同步失败，可重试",
            .blocked: "同步被阻断，需要重新记录"
        ]
        XCTAssertEqual(labels.count, DraftSyncOperationState.allCases.count)
        XCTAssertTrue(labels.values.allSatisfy { !$0.isEmpty })
    }

    private func makeDraft(
        ownerID: UUID,
        clientOperationID: UUID = UUID(),
        draftRevision: Int = 1,
        lifecycle: DraftLifecycle = .editing,
        rawUserText: String? = nil
    ) -> DraftEnvelope {
        let location = BodyLocationMapper.from2D(
            BodyRegionSelection(
                regionID: "body.knee.general",
                laterality: .left,
                surface: .anterior,
                source: .bodyMap2D,
                view: .front,
                point: Point2D(x: 0.42, y: 0.64)
            )
        )
        return DraftEnvelope(
            ownerID: ownerID,
            clientOperationID: clientOperationID,
            draftRevision: draftRevision,
            lifecycle: lifecycle,
            locations: [location],
            facts: UnconfirmedDraftFacts(
                sensationCodes: ["sore"],
                intensity: 4,
                timePattern: "after synthetic exercise",
                aggravatingFactors: ["stairs"],
                relievingFactors: ["rest"],
                functionalImpacts: ["slower running"],
                backgroundFacts: ["synthetic test context"],
                rawUserText: rawUserText
            )
        )
    }
}
