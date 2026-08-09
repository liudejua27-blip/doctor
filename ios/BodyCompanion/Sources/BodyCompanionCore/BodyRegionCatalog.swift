import Foundation

/// Stable, non-clinical regions used by the 2D map and by the prototype 3D
/// entity resolver. A region is a UI vocabulary item; it is not an anatomical
/// diagnosis or a statement about the source of a user's symptom.
public enum BodyRegionGeometry: Hashable, Sendable {
    case ellipse(center: Point2D, radius: Point2D)
    case rectangle(origin: Point2D, size: Point2D)

    public func contains(_ point: Point2D) -> Bool {
        switch self {
        case let .ellipse(center, radius):
            guard radius.x > 0, radius.y > 0 else { return false }
            let dx = (point.x - center.x) / radius.x
            let dy = (point.y - center.y) / radius.y
            return (dx * dx) + (dy * dy) <= 1
        case let .rectangle(origin, size):
            return point.x >= origin.x && point.x <= origin.x + size.x &&
                point.y >= origin.y && point.y <= origin.y + size.y
        }
    }
}

public struct BodyRegionOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let regionID: String
    public let laterality: Laterality
    public let surface: BodySurface
    public let depth: BodyDepth
    public let label: String
    public let englishLabel: String
    public let frontGeometry: BodyRegionGeometry?
    public let backGeometry: BodyRegionGeometry?
    public let priority: Int

    public init(
        regionID: String,
        laterality: Laterality,
        surface: BodySurface,
        depth: BodyDepth = .unspecified,
        label: String,
        englishLabel: String,
        frontGeometry: BodyRegionGeometry?,
        backGeometry: BodyRegionGeometry?,
        priority: Int = 0
    ) {
        self.id = "\(regionID)|\(laterality.rawValue)"
        self.regionID = regionID
        self.laterality = laterality
        self.surface = surface
        self.depth = depth
        self.label = label
        self.englishLabel = englishLabel
        self.frontGeometry = frontGeometry
        self.backGeometry = backGeometry
        self.priority = priority
    }

    public func geometry(for view: BodyMapView) -> BodyRegionGeometry? {
        switch view {
        case .front: return frontGeometry
        case .back: return backGeometry
        }
    }
}

public enum BodyRegionCatalog {
    public static let ontologyVersion = "body-ontology-prototype-v1"
    public static let assetID = "body-map-2d-v1"
    public static let assetVersion = "1.0.0"

    /// The coordinates are normalized to the map canvas. They intentionally
    /// describe broad, user-selectable areas rather than anatomical landmarks.
    public static let all: [BodyRegionOption] = [
        option("body.head.general", .midline, .circumferential, "头部", "Head", ellipse(0.50, 0.10, 0.075, 0.075), ellipse(0.50, 0.10, 0.075, 0.075), 10),
        option("body.neck.general", .midline, .circumferential, "颈部", "Neck", rect(0.455, 0.165, 0.09, 0.055), rect(0.455, 0.165, 0.09, 0.055), 20),
        option("body.shoulder.general", .left, .lateral, "左肩", "Left shoulder", ellipse(0.405, 0.235, 0.08, 0.045), ellipse(0.405, 0.235, 0.08, 0.045), 25),
        option("body.shoulder.general", .right, .lateral, "右肩", "Right shoulder", ellipse(0.595, 0.235, 0.08, 0.045), ellipse(0.595, 0.235, 0.08, 0.045), 25),
        option("body.chest.general", .left, .anterior, "左胸前", "Left chest", ellipse(0.445, 0.285, 0.075, 0.065), nil, 30),
        option("body.chest.general", .right, .anterior, "右胸前", "Right chest", ellipse(0.555, 0.285, 0.075, 0.065), nil, 30),
        option("body.upper_back.general", .left, .posterior, "左上背", "Left upper back", nil, ellipse(0.445, 0.285, 0.075, 0.065), 30),
        option("body.upper_back.general", .right, .posterior, "右上背", "Right upper back", nil, ellipse(0.555, 0.285, 0.075, 0.065), 30),
        option("body.torso.general", .midline, .circumferential, "躯干", "Torso", ellipse(0.50, 0.355, 0.14, 0.17), ellipse(0.50, 0.355, 0.14, 0.17), 5),
        option("body.abdomen.general", .midline, .anterior, "腹部", "Abdomen", ellipse(0.50, 0.405, 0.095, 0.10), nil, 20),
        option("body.lower_back.general", .midline, .posterior, "下背部", "Lower back", nil, ellipse(0.50, 0.405, 0.095, 0.10), 20),
        option("body.upper_arm.general", .left, .lateral, "左上臂", "Left upper arm", ellipse(0.335, 0.335, 0.045, 0.12), ellipse(0.335, 0.335, 0.045, 0.12), 20),
        option("body.upper_arm.general", .right, .lateral, "右上臂", "Right upper arm", ellipse(0.665, 0.335, 0.045, 0.12), ellipse(0.665, 0.335, 0.045, 0.12), 20),
        option("body.elbow.general", .left, .lateral, "左肘", "Left elbow", ellipse(0.315, 0.465, 0.045, 0.045), ellipse(0.315, 0.465, 0.045, 0.045), 40),
        option("body.elbow.general", .right, .lateral, "右肘", "Right elbow", ellipse(0.685, 0.465, 0.045, 0.045), ellipse(0.685, 0.465, 0.045, 0.045), 40),
        option("body.forearm.general", .left, .lateral, "左前臂", "Left forearm", ellipse(0.30, 0.535, 0.04, 0.09), ellipse(0.30, 0.535, 0.04, 0.09), 15),
        option("body.forearm.general", .right, .lateral, "右前臂", "Right forearm", ellipse(0.70, 0.535, 0.04, 0.09), ellipse(0.70, 0.535, 0.04, 0.09), 15),
        option("body.hand.general", .left, .lateral, "左手腕/手", "Left wrist/hand", ellipse(0.275, 0.635, 0.055, 0.07), ellipse(0.275, 0.635, 0.055, 0.07), 20),
        option("body.hand.general", .right, .lateral, "右手腕/手", "Right wrist/hand", ellipse(0.725, 0.635, 0.055, 0.07), ellipse(0.725, 0.635, 0.055, 0.07), 20),
        option("body.hip.general", .left, .lateral, "左髋", "Left hip", ellipse(0.445, 0.535, 0.07, 0.065), ellipse(0.445, 0.535, 0.07, 0.065), 30),
        option("body.hip.general", .right, .lateral, "右髋", "Right hip", ellipse(0.555, 0.535, 0.07, 0.065), ellipse(0.555, 0.535, 0.07, 0.065), 30),
        option("body.pelvis.general", .midline, .circumferential, "骨盆区域", "Pelvis area", ellipse(0.50, 0.535, 0.12, 0.08), ellipse(0.50, 0.535, 0.12, 0.08), 5),
        option("body.thigh.general", .left, .lateral, "左大腿", "Left thigh", ellipse(0.445, 0.655, 0.06, 0.105), ellipse(0.445, 0.655, 0.06, 0.105), 15),
        option("body.thigh.general", .right, .lateral, "右大腿", "Right thigh", ellipse(0.555, 0.655, 0.06, 0.105), ellipse(0.555, 0.655, 0.06, 0.105), 15),
        option("body.knee.general", .left, .lateral, "左膝附近", "Left knee area", ellipse(0.445, 0.775, 0.055, 0.055), ellipse(0.445, 0.775, 0.055, 0.055), 45),
        option("body.knee.general", .right, .lateral, "右膝附近", "Right knee area", ellipse(0.555, 0.775, 0.055, 0.055), ellipse(0.555, 0.775, 0.055, 0.055), 45),
        option("body.calf.general", .left, .lateral, "左小腿", "Left calf", ellipse(0.445, 0.875, 0.05, 0.09), ellipse(0.445, 0.875, 0.05, 0.09), 15),
        option("body.calf.general", .right, .lateral, "右小腿", "Right calf", ellipse(0.555, 0.875, 0.05, 0.09), ellipse(0.555, 0.875, 0.05, 0.09), 15),
        option("body.ankle_foot.general", .left, .lateral, "左脚踝/足部", "Left ankle/foot", ellipse(0.435, 0.965, 0.07, 0.035), ellipse(0.435, 0.965, 0.07, 0.035), 25),
        option("body.ankle_foot.general", .right, .lateral, "右脚踝/足部", "Right ankle/foot", ellipse(0.565, 0.965, 0.07, 0.035), ellipse(0.565, 0.965, 0.07, 0.035), 25),
    ]

    public static func options(for view: BodyMapView) -> [BodyRegionOption] {
        all.filter { $0.geometry(for: view) != nil }
    }

    /// Searches only the display vocabulary of the versioned local catalog.
    /// The query is intentionally not expanded through history, Agent output,
    /// remote synonyms, or anatomy inference. Filtering happens after the
    /// front/back catalog filter, so the returned ordering stays stable.
    public static func options(matching query: String, for view: BodyMapView) -> [BodyRegionOption] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let viewOptions = options(for: view)
        guard !normalizedQuery.isEmpty else { return viewOptions }
        return viewOptions.filter { option in
            option.label.localizedCaseInsensitiveContains(normalizedQuery) ||
                option.englishLabel.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    public static func hitTest(point: Point2D, view: BodyMapView) -> BodyRegionOption? {
        options(for: view)
            .filter { $0.geometry(for: view)?.contains(point) == true }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.id < rhs.id
            }
            .first
    }

    public static func option(regionID: String, laterality: Laterality) -> BodyRegionOption? {
        all.first { $0.regionID == regionID && $0.laterality == laterality }
    }

    /// Resolves only the stable names emitted by the project's own procedural
    /// candidate model. It deliberately does not infer anatomy from arbitrary
    /// mesh names or from an upstream rendering heuristic.
    public static func option(forEntityID entityID: String) -> BodyRegionOption? {
        let normalized = entityID.lowercased()
        let laterality: Laterality = normalized.contains("left") ? .left : (normalized.contains("right") ? .right : .midline)
        let regionID: String?
        if normalized.contains("head") { regionID = "body.head.general" }
        else if normalized.contains("neck") { regionID = "body.neck.general" }
        else if normalized.contains("shoulder") { regionID = "body.shoulder.general" }
        else if normalized.contains("chest") { regionID = "body.chest.general" }
        else if normalized.contains("upper_back") { regionID = "body.upper_back.general" }
        else if normalized.contains("torso") { regionID = "body.torso.general" }
        else if normalized.contains("abdomen") { regionID = "body.abdomen.general" }
        else if normalized.contains("lower_back") { regionID = "body.lower_back.general" }
        else if normalized.contains("upper_arm") { regionID = "body.upper_arm.general" }
        else if normalized.contains("elbow") { regionID = "body.elbow.general" }
        else if normalized.contains("forearm") { regionID = "body.forearm.general" }
        else if normalized.contains("hand") { regionID = "body.hand.general" }
        else if normalized.contains("hip") { regionID = "body.hip.general" }
        else if normalized.contains("pelvis") { regionID = "body.pelvis.general" }
        else if normalized.contains("thigh") { regionID = "body.thigh.general" }
        else if normalized.contains("knee") { regionID = "body.knee.general" }
        else if normalized.contains("calf") { regionID = "body.calf.general" }
        else if normalized.contains("ankle") || normalized.contains("foot") { regionID = "body.ankle_foot.general" }
        else { regionID = nil }

        guard let regionID else { return nil }
        if laterality == .midline {
            return all.first { $0.regionID == regionID && $0.laterality == .midline }
        }
        return option(regionID: regionID, laterality: laterality)
    }

    private static func option(
        _ regionID: String,
        _ laterality: Laterality,
        _ surface: BodySurface,
        _ label: String,
        _ englishLabel: String,
        _ frontGeometry: BodyRegionGeometry?,
        _ backGeometry: BodyRegionGeometry?,
        _ priority: Int
    ) -> BodyRegionOption {
        BodyRegionOption(
            regionID: regionID,
            laterality: laterality,
            surface: surface,
            label: label,
            englishLabel: englishLabel,
            frontGeometry: frontGeometry,
            backGeometry: backGeometry,
            priority: priority
        )
    }

    private static func ellipse(_ x: Double, _ y: Double, _ radiusX: Double, _ radiusY: Double) -> BodyRegionGeometry {
        .ellipse(center: Point2D(x: x, y: y), radius: Point2D(x: radiusX, y: radiusY))
    }

    private static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> BodyRegionGeometry {
        .rectangle(origin: Point2D(x: x, y: y), size: Point2D(x: width, y: height))
    }
}
