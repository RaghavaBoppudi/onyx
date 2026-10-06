import CryptoKit
import Foundation
import Security

nonisolated extension Sequence where Element == UInt8 {
    var onyxHex: String {
        reduce(into: "") { $0 += String(format: "%02x", $1) }
    }
}

private nonisolated enum SigningKey {
    case hardware(SecureEnclave.P256.Signing.PrivateKey)
    case software(P256.Signing.PrivateKey)

    var publicKey: P256.Signing.PublicKey {
        switch self {
        case .hardware(let key): key.publicKey
        case .software(let key): key.publicKey
        }
    }

    var storage: String {
        switch self {
        case .hardware: "secure-enclave"
        case .software: "software"
        }
    }

    var id: String {
        SHA256.hash(data: publicKey.x963Representation).prefix(8).onyxHex
    }

    func sign(_ data: Data) throws -> Data {
        switch self {
        case .hardware(let key): try key.signature(for: data).rawRepresentation
        case .software(let key): try key.signature(for: data).rawRepresentation
        }
    }
}

actor CaptureLedger {

    private struct Tail {
        let sequence: Int
        let hash: String
        let signer: String
    }

    private enum TailReading {
        case empty
        case tail(Tail)
        case unreadable
    }

    private static let service = "com.onyx.provenance"
    private static let hardwareAccount = "signing-key.secure-enclave"
    private static let softwareAccount = "signing-key.software"

    private let directory: URL
    private let fileURL: URL
    private var cachedKey: SigningKey?
    private var tail: Tail?

    init() {
        directory = URL.documentsDirectory.appending(path: "Provenance", directoryHint: .isDirectory)
        fileURL = directory.appending(path: "ledger.jsonl", directoryHint: .notDirectory)
    }

    func append(dng: Data, context: CaptureContext) throws -> LedgerReceipt {
        let key = try signingKey()
        let head = try chainHead(for: key)

        let digest = SHA256.hash(data: dng).onyxHex
        let capture = LedgerPayload.Capture(
            id: context.id.uuidString,
            dngSHA256: digest,
            dngBytes: dng.count,
            lens: context.lens,
            flashRequested: context.flashRequested,
            exposureBias: context.exposureBias,
            location: context.location,
            depth: LedgerPayload.Depth(
                status: "unavailable",
                reason: "rear lenses are physical devices without depth output"
            )
        )
        let payload = LedgerPayload(
            schema: 1,
            sequence: head.sequence + 1,
            previousHash: head.hash,
            capturedAtMillis: Self.nowMillis(),
            signer: key.id,
            genesis: nil,
            capture: capture
        )

        let entry = try seal(payload, with: key)
        try write(entry)
        tail = Tail(sequence: payload.sequence, hash: entry.hash, signer: key.id)

        return LedgerReceipt(sequence: payload.sequence, dngSHA256: digest, entryHash: entry.hash)
    }

    private func chainHead(for key: SigningKey) throws -> Tail {
        if let tail, tail.signer == key.id { return tail }

        switch readTail() {
        case .tail(let existing) where existing.signer == key.id:
            tail = existing
            return existing
        case .tail(let existing):
            return try startChain(key: key, after: existing, reason: "key-changed")
        case .empty:
            return try startChain(key: key, after: nil, reason: "first-run")
        case .unreadable:
            quarantineFile()
            return try startChain(key: key, after: nil, reason: "chain-unreadable")
        }
    }

    private func startChain(key: SigningKey, after previous: Tail?, reason: String) throws -> Tail {
        let genesis = LedgerPayload.Genesis(
            publicKey: key.publicKey.x963Representation.base64EncodedString(),
            keyStorage: key.storage,
            device: Self.hardwareIdentifier(),
            app: Self.appVersion(),
            reason: reason
        )
        let payload = LedgerPayload(
            schema: 1,
            sequence: (previous?.sequence ?? -1) + 1,
            previousHash: previous?.hash ?? String(repeating: "0", count: 64),
            capturedAtMillis: Self.nowMillis(),
            signer: key.id,
            genesis: genesis,
            capture: nil
        )

        let entry = try seal(payload, with: key)
        try write(entry)

        let head = Tail(sequence: payload.sequence, hash: entry.hash, signer: key.id)
        tail = head
        return head
    }

    private func seal(_ payload: LedgerPayload, with key: SigningKey) throws -> LedgerEntry {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let bytes = try encoder.encode(payload)
        guard let text = String(data: bytes, encoding: .utf8) else { throw LedgerError.encoding }

        let message = Data(text.utf8)
        return LedgerEntry(
            payload: text,
            hash: SHA256.hash(data: message).onyxHex,
            signature: try key.sign(message).base64EncodedString()
        )
    }

    private func write(_ entry: LedgerEntry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(entry)
        line.append(0x0A)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    private func readTail() -> TailReading {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return .unreadable }

        guard let last = text.split(separator: "\n", omittingEmptySubsequences: true).last else {
            return .empty
        }

        let decoder = JSONDecoder()
        guard let entry = try? decoder.decode(LedgerEntry.self, from: Data(last.utf8)),
              let payload = try? decoder.decode(LedgerPayload.self, from: Data(entry.payload.utf8))
        else { return .unreadable }

        return .tail(Tail(sequence: payload.sequence, hash: entry.hash, signer: payload.signer))
    }

    private func quarantineFile() {
        let destination = directory.appending(
            path: "ledger-\(Self.nowMillis()).unreadable.jsonl",
            directoryHint: .notDirectory
        )
        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }

    private func signingKey() throws -> SigningKey {
        if let cachedKey { return cachedKey }
        let key = try Self.loadOrCreateKey()
        cachedKey = key
        return key
    }

    private static func loadOrCreateKey() throws -> SigningKey {
        if let data = try readKeychain(account: hardwareAccount) {
            return .hardware(try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data))
        }
        if let data = try readKeychain(account: softwareAccount) {
            return .software(try P256.Signing.PrivateKey(rawRepresentation: data))
        }

        if SecureEnclave.isAvailable {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                .privateKeyUsage,
                &error
            ) else { throw LedgerError.accessControl }

            let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
            try writeKeychain(key.dataRepresentation, account: hardwareAccount)
            return .hardware(key)
        }

        let key = P256.Signing.PrivateKey()
        try writeKeychain(key.rawRepresentation, account: softwareAccount)
        return .software(key)
    }

    private static func readKeychain(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw LedgerError.keychain(status)
        }
    }

    private static func writeKeychain(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw LedgerError.keychain(status) }
    }

    private static func nowMillis() -> Int64 {
        Int64(Date.now.timeIntervalSince1970 * 1000)
    }

    private static func appVersion() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func hardwareIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let bytes = machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
