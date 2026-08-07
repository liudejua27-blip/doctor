import CryptoKit
import Foundation

public enum DraftSyncQueueError: Error, Equatable, Sendable {
    case idempotencyConflict
    case operationNotFound
    case invalidState
    case draftNotSyncable
}

public enum DraftSyncOperationState: String, Codable, CaseIterable, Sendable {
    case queued
    case inFlight = "in_flight"
    case acceptedUnconfirmed = "accepted_unconfirmed"
    case conflict
    case failed
    case blocked
}

public struct DraftSyncOperation: Codable, Equatable, Sendable, Identifiable {
    public let clientOperationID: UUID
    public let draftID: UUID
    public let ownerID: UUID
    public let draftRevision: Int
    public let payloadDigest: String
    public var state: DraftSyncOperationState
    public var attemptCount: Int
    public var lastErrorCode: String?
    public var remoteRevision: Int?
    public let createdAt: Date

    public var id: UUID { clientOperationID }

    public init(
        clientOperationID: UUID,
        draftID: UUID,
        ownerID: UUID,
        draftRevision: Int,
        payloadDigest: String,
        state: DraftSyncOperationState = .queued,
        attemptCount: Int = 0,
        lastErrorCode: String? = nil,
        remoteRevision: Int? = nil,
        createdAt: Date = .now
    ) {
        self.clientOperationID = clientOperationID
        self.draftID = draftID
        self.ownerID = ownerID
        self.draftRevision = draftRevision
        self.payloadDigest = payloadDigest
        self.state = state
        self.attemptCount = attemptCount
        self.lastErrorCode = lastErrorCode
        self.remoteRevision = remoteRevision
        self.createdAt = createdAt
    }
}

public enum DraftSyncResult: Equatable, Sendable {
    case acceptedUnconfirmed(remoteRevision: Int)
    case alreadyAcceptedUnconfirmed(remoteRevision: Int)
    case conflict(serverRevision: Int)
    case temporaryFailure(code: String)
    case permanentFailure(code: String)
}

/// An in-memory state machine for a future HTTPS draft transport. It carries
/// only a digest and IDs; it has no confirmed Event or Approval result field.
public struct DraftSyncQueue: Sendable {
    private var operationsByID: [UUID: DraftSyncOperation] = [:]

    public init() {}

    public var count: Int { operationsByID.count }

    public func operation(id: UUID) -> DraftSyncOperation? {
        operationsByID[id]
    }

    public func allOperations() -> [DraftSyncOperation] {
        operationsByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.clientOperationID.uuidString < rhs.clientOperationID.uuidString }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public mutating func enqueue(_ draft: DraftEnvelope) throws -> DraftSyncOperation {
        do {
            try draft.validate()
        } catch {
            throw DraftSyncQueueError.draftNotSyncable
        }
        guard draft.lifecycle != .discarded, draft.lifecycle != .expired else {
            throw DraftSyncQueueError.draftNotSyncable
        }
        let digest = try DraftDigest.sha256(draft)
        if let existing = operationsByID[draft.clientOperationID] {
            guard existing.draftID == draft.draftID,
                  existing.ownerID == draft.ownerID,
                  existing.draftRevision == draft.draftRevision,
                  existing.payloadDigest == digest else {
                throw DraftSyncQueueError.idempotencyConflict
            }
            return existing
        }
        let operation = DraftSyncOperation(
            clientOperationID: draft.clientOperationID,
            draftID: draft.draftID,
            ownerID: draft.ownerID,
            draftRevision: draft.draftRevision,
            payloadDigest: digest
        )
        operationsByID[operation.clientOperationID] = operation
        return operation
    }

    public mutating func beginNext() throws -> DraftSyncOperation? {
        guard let next = allOperations().first(where: { $0.state == .queued }) else { return nil }
        guard var updated = operationsByID[next.clientOperationID] else {
            throw DraftSyncQueueError.operationNotFound
        }
        updated.state = .inFlight
        updated.attemptCount += 1
        updated.lastErrorCode = nil
        operationsByID[updated.clientOperationID] = updated
        return updated
    }

    public mutating func apply(
        _ result: DraftSyncResult,
        to clientOperationID: UUID
    ) throws -> DraftSyncOperation {
        guard var operation = operationsByID[clientOperationID] else {
            throw DraftSyncQueueError.operationNotFound
        }
        guard operation.state == .inFlight else {
            throw DraftSyncQueueError.invalidState
        }
        switch result {
        case let .acceptedUnconfirmed(remoteRevision), let .alreadyAcceptedUnconfirmed(remoteRevision):
            guard remoteRevision >= 1 else { throw DraftSyncQueueError.invalidState }
            operation.state = .acceptedUnconfirmed
            operation.remoteRevision = remoteRevision
            operation.lastErrorCode = nil
        case let .conflict(serverRevision):
            guard serverRevision >= 1 else { throw DraftSyncQueueError.invalidState }
            operation.state = .conflict
            operation.remoteRevision = serverRevision
            operation.lastErrorCode = "REVISION_CONFLICT"
        case let .temporaryFailure(code):
            operation.state = .failed
            operation.lastErrorCode = Self.normalizedErrorCode(code)
        case let .permanentFailure(code):
            operation.state = .blocked
            operation.lastErrorCode = Self.normalizedErrorCode(code)
        }
        operationsByID[clientOperationID] = operation
        return operation
    }

    public mutating func retry(clientOperationID: UUID) throws -> DraftSyncOperation {
        guard var operation = operationsByID[clientOperationID] else {
            throw DraftSyncQueueError.operationNotFound
        }
        guard operation.state == .failed else { throw DraftSyncQueueError.invalidState }
        operation.state = .queued
        operation.lastErrorCode = nil
        operationsByID[clientOperationID] = operation
        return operation
    }

    public mutating func discard(clientOperationID: UUID) throws -> DraftSyncOperation {
        guard var operation = operationsByID[clientOperationID] else {
            throw DraftSyncQueueError.operationNotFound
        }
        guard operation.state != .inFlight else { throw DraftSyncQueueError.invalidState }
        operation.state = .blocked
        operation.lastErrorCode = "DRAFT_DISCARDED"
        operationsByID[clientOperationID] = operation
        return operation
    }

    private static func normalizedErrorCode(_ code: String) -> String {
        let allowed = code.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
        return String(allowed.prefix(80)).isEmpty ? "UNKNOWN_SYNC_ERROR" : String(allowed.prefix(80))
    }
}

public enum DraftDigest {
    public static func sha256(_ draft: DraftEnvelope) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(draft)
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
