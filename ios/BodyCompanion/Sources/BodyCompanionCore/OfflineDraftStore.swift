import CryptoKit
import Foundation

/// The only lifecycle values that may be stored by the offline prototype.
/// None of them represents a confirmed BodySignalEvent.
public enum DraftLifecycle: String, Codable, CaseIterable, Sendable {
    case editing
    case queued
    case syncing
    case conflict
    case remoteUnconfirmed = "remote_unconfirmed"
    case discarded
    case expired
}

public enum DraftSyncStatus: String, Codable, CaseIterable, Sendable {
    case notQueued = "not_queued"
    case queued
    case inFlight = "in_flight"
    case acceptedUnconfirmed = "accepted_unconfirmed"
    case conflict
    case failed
    case blocked
}

/// The P4 envelope intentionally omits full typed-fact provenance, but it
/// must retain the explicit user association between a sensation and the
/// selected body locations. Losing that link would make a multi-location
/// draft unsafe to restore or hand off.
public struct UnconfirmedDraftSensation: Codable, Equatable, Hashable, Sendable {
    public var code: String
    public var userLabel: String?
    public var locationMarkerIDs: [UUID]

    public init(code: String, userLabel: String? = nil, locationMarkerIDs: [UUID]) {
        self.code = code
        self.userLabel = userLabel
        self.locationMarkerIDs = locationMarkerIDs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code
        case userLabel = "user_label"
        case locationMarkerIDs = "location_marker_ids"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        userLabel = try container.decodeIfPresent(String.self, forKey: .userLabel)
        locationMarkerIDs = try container.decode([UUID].self, forKey: .locationMarkerIDs)
    }
}

public struct UnconfirmedDraftFacts: Codable, Equatable, Sendable {
    public var sensations: [UnconfirmedDraftSensation]
    public var intensity: Int?
    public var timePattern: String
    public var aggravatingFactors: [String]
    public var relievingFactors: [String]
    public var functionalImpacts: [String]
    public var backgroundFacts: [String]
    public var rawUserText: String?

    public init(
        sensations: [UnconfirmedDraftSensation] = [],
        intensity: Int? = nil,
        timePattern: String = "",
        aggravatingFactors: [String] = [],
        relievingFactors: [String] = [],
        functionalImpacts: [String] = [],
        backgroundFacts: [String] = [],
        rawUserText: String? = nil
    ) {
        self.sensations = sensations
        self.intensity = intensity
        self.timePattern = timePattern
        self.aggravatingFactors = aggravatingFactors
        self.relievingFactors = relievingFactors
        self.functionalImpacts = functionalImpacts
        self.backgroundFacts = backgroundFacts
        self.rawUserText = rawUserText
    }

    /// Compatibility read model for non-restoration UI such as a compact
    /// summary. New writes must use `sensations`, never a code-only array.
    public var sensationCodes: [String] {
        sensations.map(\.code)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sensations
        case intensity
        case timePattern = "time_pattern"
        case aggravatingFactors = "aggravating_factors"
        case relievingFactors = "relieving_factors"
        case functionalImpacts = "functional_impacts"
        case backgroundFacts = "background_facts"
        case rawUserText = "raw_user_text"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sensations = try container.decode([UnconfirmedDraftSensation].self, forKey: .sensations)
        intensity = try container.decodeIfPresent(Int.self, forKey: .intensity)
        timePattern = try container.decode(String.self, forKey: .timePattern)
        aggravatingFactors = try container.decode([String].self, forKey: .aggravatingFactors)
        relievingFactors = try container.decode([String].self, forKey: .relievingFactors)
        functionalImpacts = try container.decode([String].self, forKey: .functionalImpacts)
        backgroundFacts = try container.decode([String].self, forKey: .backgroundFacts)
        rawUserText = try container.decodeIfPresent(String.self, forKey: .rawUserText)
    }
}

public struct DraftSyncMetadata: Codable, Equatable, Sendable {
    public var state: DraftSyncStatus
    public var attemptCount: Int
    public var lastErrorCode: String?
    public var remoteRevision: Int?

    public init(
        state: DraftSyncStatus = .notQueued,
        attemptCount: Int = 0,
        lastErrorCode: String? = nil,
        remoteRevision: Int? = nil
    ) {
        self.state = state
        self.attemptCount = attemptCount
        self.lastErrorCode = lastErrorCode
        self.remoteRevision = remoteRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case state
        case attemptCount = "attempt_count"
        case lastErrorCode = "last_error_code"
        case remoteRevision = "remote_revision"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(DraftSyncStatus.self, forKey: .state)
        attemptCount = try container.decode(Int.self, forKey: .attemptCount)
        lastErrorCode = try container.decodeIfPresent(String.self, forKey: .lastErrorCode)
        remoteRevision = try container.decodeIfPresent(Int.self, forKey: .remoteRevision)
    }
}

/// A user-owned, not-yet-confirmed signal. The type is intentionally an
/// envelope rather than a BodySignalEvent: a draft cannot carry an approval,
/// event, report, or diagnostic conclusion.
public struct DraftEnvelope: Codable, Equatable, Sendable, Identifiable {
    public static let currentSchemaVersion = "1.1"

    public let schemaVersion: String
    public let draftID: UUID
    public let ownerID: UUID
    public let clientOperationID: UUID
    public var draftRevision: Int
    public var lifecycle: DraftLifecycle
    public var locations: [BodyLocation]
    public var facts: UnconfirmedDraftFacts
    public var sync: DraftSyncMetadata
    public let createdAt: Date
    public var updatedAt: Date

    public var id: UUID { draftID }

    public init(
        draftID: UUID = UUID(),
        ownerID: UUID,
        clientOperationID: UUID = UUID(),
        draftRevision: Int = 1,
        lifecycle: DraftLifecycle = .editing,
        locations: [BodyLocation] = [],
        facts: UnconfirmedDraftFacts = .init(),
        sync: DraftSyncMetadata = .init(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        precondition(draftRevision >= 1, "draft revision must be positive")
        precondition(sync.attemptCount >= 0, "sync attempt count cannot be negative")
        self.schemaVersion = Self.currentSchemaVersion
        self.draftID = draftID
        self.ownerID = ownerID
        self.clientOperationID = clientOperationID
        self.draftRevision = draftRevision
        self.lifecycle = lifecycle
        self.locations = locations
        self.facts = facts
        self.sync = sync
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case draftID = "draft_id"
        case ownerID = "owner_id"
        case clientOperationID = "client_operation_id"
        case draftRevision = "draft_revision"
        case lifecycle
        case locations
        case facts
        case sync
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DraftStoreError.schemaMismatch
        }
        draftID = try container.decode(UUID.self, forKey: .draftID)
        ownerID = try container.decode(UUID.self, forKey: .ownerID)
        clientOperationID = try container.decode(UUID.self, forKey: .clientOperationID)
        draftRevision = try container.decode(Int.self, forKey: .draftRevision)
        guard draftRevision >= 1 else { throw DraftStoreError.invalidEnvelope }
        lifecycle = try container.decode(DraftLifecycle.self, forKey: .lifecycle)
        locations = try container.decode([BodyLocation].self, forKey: .locations)
        facts = try container.decode(UnconfirmedDraftFacts.self, forKey: .facts)
        sync = try container.decode(DraftSyncMetadata.self, forKey: .sync)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              draftRevision >= 1,
              locations.count <= 20,
              Set(locations.map(\.id)).count == locations.count,
              facts.sensations.count <= 20,
              facts.aggravatingFactors.count <= 30,
              facts.relievingFactors.count <= 30,
              facts.functionalImpacts.count <= 30,
              facts.backgroundFacts.count <= 50,
              facts.timePattern.count <= 128,
              facts.rawUserText.map({ $0.count <= 4000 }) ?? true,
              sync.attemptCount >= 0,
              sync.remoteRevision.map({ $0 >= 1 }) ?? true else {
            throw DraftStoreError.invalidEnvelope
        }
        if let intensity = facts.intensity, !(0...10).contains(intensity) {
            throw DraftStoreError.invalidEnvelope
        }
        let locationIDs = Set(locations.map(\.id))
        if facts.sensations.contains(where: {
            $0.code.isEmpty || $0.code.count > 64 ||
                ($0.userLabel?.count ?? 0) > 200 ||
                $0.locationMarkerIDs.isEmpty ||
                Set($0.locationMarkerIDs).count != $0.locationMarkerIDs.count ||
                !Set($0.locationMarkerIDs).isSubset(of: locationIDs)
        }) ||
            facts.aggravatingFactors.contains(where: { $0.isEmpty || $0.count > 128 }) ||
            facts.relievingFactors.contains(where: { $0.isEmpty || $0.count > 128 }) ||
            facts.functionalImpacts.contains(where: { $0.isEmpty || $0.count > 128 }) ||
            facts.backgroundFacts.contains(where: { $0.isEmpty || $0.count > 256 }) {
            throw DraftStoreError.invalidEnvelope
        }
    }
}

/// A compatibility name used in feature documents. It intentionally resolves
/// to the envelope above so callers cannot accidentally create a second,
/// weaker draft representation.
public typealias UnconfirmedSignalDraft = DraftEnvelope

public enum DraftStoreError: Error, Equatable, Sendable {
    case notFound
    case ownerMismatch
    case keyUnavailable
    case encryptionFailed
    case decryptionFailed
    case schemaMismatch
    case invalidEnvelope
    case cannotRestoreDiscardedDraft
}

public protocol DraftKeyProvider: Sendable {
    func key(for ownerID: UUID) throws -> SymmetricKey
}

/// A deterministic, process-memory-only key provider for the prototype.
/// Production must replace this with Keychain/Data Protection and must not use
/// the test master key or the derivation scheme as a storage contract.
public struct InMemoryDraftKeyProvider: DraftKeyProvider, Sendable {
    private let masterKeyData: Data

    public init(masterKeyData: Data = Data(repeating: 0x2A, count: 32)) {
        precondition(masterKeyData.count == 32, "prototype master key must be 256 bits")
        self.masterKeyData = masterKeyData
    }

    public func key(for ownerID: UUID) throws -> SymmetricKey {
        let master = SymmetricKey(data: masterKeyData)
        let ownerData = Data(ownerID.uuidString.lowercased().utf8)
        let derived = HMAC<SHA256>.authenticationCode(for: ownerData, using: master)
        return SymmetricKey(data: Data(derived))
    }
}

/// An in-memory encrypted store. It deliberately has no file or Keychain
/// access; its purpose is to prove the encryption and ownership contract
/// before a production persistence choice is approved.
public actor InMemoryEncryptedDraftStore {
    private let keyProvider: any DraftKeyProvider
    private var ciphertextByDraftID: [UUID: Data] = [:]

    public init(keyProvider: any DraftKeyProvider) {
        self.keyProvider = keyProvider
    }

    public func save(_ envelope: DraftEnvelope) throws {
        try envelope.validate()
        guard envelope.lifecycle != .discarded, envelope.lifecycle != .expired else {
            throw DraftStoreError.cannotRestoreDiscardedDraft
        }
        let plaintext = try Self.encode(envelope)
        let key = try keyProvider.key(for: envelope.ownerID)
        let aad = Self.additionalAuthenticatedData(draftID: envelope.draftID, ownerID: envelope.ownerID)
        do {
            guard let combined = try AES.GCM.seal(plaintext, using: key, authenticating: aad).combined else {
                throw DraftStoreError.encryptionFailed
            }
            ciphertextByDraftID[envelope.draftID] = combined
        } catch let error as DraftStoreError {
            throw error
        } catch {
            throw DraftStoreError.encryptionFailed
        }
    }

    public func load(draftID: UUID, ownerID: UUID) throws -> DraftEnvelope {
        guard let ciphertext = ciphertextByDraftID[draftID] else {
            throw DraftStoreError.notFound
        }
        let key = try keyProvider.key(for: ownerID)
        let aad = Self.additionalAuthenticatedData(draftID: draftID, ownerID: ownerID)
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
            let envelope = try Self.decode(plaintext)
            guard envelope.draftID == draftID else { throw DraftStoreError.invalidEnvelope }
            guard envelope.ownerID == ownerID else { throw DraftStoreError.ownerMismatch }
            return envelope
        } catch let error as DraftStoreError {
            throw error
        } catch {
            throw DraftStoreError.decryptionFailed
        }
    }

    /// Idempotent deletion after ownership/decryption verification. A missing
    /// record is treated as already deleted; no health content is returned.
    public func delete(draftID: UUID, ownerID: UUID) throws {
        guard ciphertextByDraftID[draftID] != nil else { return }
        _ = try load(draftID: draftID, ownerID: ownerID)
        ciphertextByDraftID.removeValue(forKey: draftID)
    }

    /// Test-only evidence hook. It exposes bytes only to `@testable` tests and
    /// must not be surfaced by a production repository API.
    func storedCiphertext(for draftID: UUID) -> Data? {
        ciphertextByDraftID[draftID]
    }

    /// Test-only fault injection for authentication-failure coverage.
    func replaceStoredCiphertextForTesting(_ ciphertext: Data, draftID: UUID) {
        ciphertextByDraftID[draftID] = ciphertext
    }

    private static func encode(_ envelope: DraftEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    private static func decode(_ data: Data) throws -> DraftEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DraftEnvelope.self, from: data)
    }

    private static func additionalAuthenticatedData(draftID: UUID, ownerID: UUID) -> Data {
        Data("body-companion:draft:\(draftID.uuidString.lowercased()):owner:\(ownerID.uuidString.lowercased())".utf8)
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func rejectUnknownKeys<K: CodingKey>(
    _ decoder: Decoder,
    allowed: [K]
) throws {
    let allowedNames = Set(allowed.map(\.stringValue))
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    if let unknown = container.allKeys.first(where: { !allowedNames.contains($0.stringValue) }) {
        throw DecodingError.dataCorruptedError(
            forKey: unknown,
            in: container,
            debugDescription: "unknown field is not allowed: \(unknown.stringValue)"
        )
    }
}
