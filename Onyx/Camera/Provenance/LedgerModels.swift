import CoreLocation
import Foundation

nonisolated struct LocationEvidence: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var altitude: Double
    var timestampMillis: Int64
    var simulatedBySoftware: Bool?
    var producedByAccessory: Bool?
}

extension LocationEvidence {
    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            timestampMillis: Int64(location.timestamp.timeIntervalSince1970 * 1000),
            simulatedBySoftware: location.sourceInformation?.isSimulatedBySoftware,
            producedByAccessory: location.sourceInformation?.isProducedByAccessory
        )
    }
}

nonisolated struct CaptureContext: Sendable {
    let id: UUID
    let capturedAtMillis: Int64
    let lens: String
    let flashRequested: String
    let flashEnabled: Bool?
    let exposureBiasRequested: Float
    let exposureBiasActual: Float?
    let locationStatus: String
    let location: LocationEvidence?
}

nonisolated struct LedgerPayload: Codable, Sendable {

    nonisolated struct Genesis: Codable, Sendable {
        var publicKey: String
        var keyStorage: String
        var device: String
        var app: String
        var reason: String
    }

    nonisolated struct Depth: Codable, Sendable {
        var status: String
        var reason: String
    }

    nonisolated struct Capture: Codable, Sendable {
        var id: String
        var dngSHA256: String
        var dngBytes: Int
        var lens: String
        var flashRequested: String
        var flashEnabled: Bool?
        var exposureBiasRequested: Float
        var exposureBiasActual: Float?
        var locationStatus: String
        var location: LocationEvidence?
        var depth: Depth
    }

    nonisolated struct Status: Codable, Sendable {
        var captureID: String
        var event: String
        var detail: String
    }

    var schema: Int
    var sequence: Int
    var previousHash: String
    var capturedAtMillis: Int64
    var signer: String
    var genesis: Genesis?
    var status: Status?
    var capture: Capture?
}

nonisolated struct LedgerEntry: Codable, Sendable {
    let payload: String
    let hash: String
    let signature: String
}

nonisolated struct LedgerReceipt: Sendable {
    let sequence: Int
    let dngSHA256: String?
}

nonisolated enum LedgerError: Error, Sendable {
    case keychain(OSStatus)
    case accessControl
    case encoding
}
