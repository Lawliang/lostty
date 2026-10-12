import Foundation
import Network

public enum PairingError: Error, Equatable {
    case invalidLink
    case macNotFound
    case localNetworkDenied
    case connectionFailed
    case badMessage

    public var message: String {
        switch self {
        case .invalidLink:
            "That isn't a Lostty pairing code. On your Mac, open Lostty → Phone Access → Pair a Phone."
        case .macNotFound:
            "Couldn't find your Mac nearby. Keep the pairing code open on the Mac, and keep this phone close to it."
        case .localNetworkDenied:
            "Lostty needs Local Network access to find your Mac. Turn it on in Settings → Privacy & Security → Local Network, then try again."
        case .connectionFailed:
            "The connection to your Mac dropped. Show a new code on the Mac and scan it again."
        case .badMessage:
            "Your Mac answered in a way this Lostty doesn't understand. Update Lostty on both devices."
        }
    }
}

/// Runs a closure at most once, from any thread.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

/// Length-prefixed JSON messages (4-byte big-endian length, at most 4 KiB).
enum PairingWire {
    static let maxMessage = 4096

    static func frame(_ body: Data) -> Data {
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }

    /// The body length a header announces; nil for 0, over `maxMessage`, or
    /// a short header.
    static func bodyLength(header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        return (1...maxMessage).contains(length) ? length : nil
    }

    /// Starts `connection` and waits for the TLS handshake. Any failure,
    /// including a wrong pre-shared key, is `.connectionFailed`.
    static func start(_ connection: NWConnection, queue: DispatchQueue) async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { done.resume() }
                case .failed, .waiting, .cancelled: once.run { done.resume(throwing: PairingError.connectionFailed) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    static func send(_ body: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            connection.send(content: frame(body), completion: .contentProcessed { error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            })
        }
    }

    static func receive(on connection: NWConnection) async throws -> Data {
        guard let length = bodyLength(header: try await read(4, on: connection)) else {
            throw PairingError.badMessage
        }
        return try await read(length, on: connection)
    }

    /// Exactly `count` bytes; cancelling the connection ends a pending read.
    private static func read(_ count: Int, on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let data, data.count == count {
                    done.resume(returning: data)
                } else {
                    done.resume(throwing: error ?? PairingError.connectionFailed)
                }
            }
        }
    }
}

/// The Mac's side of pairing. A device without the QR code fails the TLS
/// handshake and never gets a request in, so it can't use up the code. The
/// first valid request is answered (after `decide`), then the server stops.
public final class PairingServer: @unchecked Sendable {
    public typealias Decide = @Sendable (PairingRequest) async -> Bool

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.lawliang.lostty.pairing.server")
    private let decide: Decide
    private let onFinish: @Sendable (Bool) -> Void
    private let lock = NSLock()
    private var claimed = false
    private var connections: [NWConnection] = []

    /// `advertise`: publish the Bonjour service (tests connect by port instead).
    public init(
        secret: Data,
        advertise: Bool = true,
        decide: @escaping Decide,
        onFinish: @escaping @Sendable (Bool) -> Void = { _ in }
    ) throws {
        listener = try NWListener(using: PairingCrypto.parameters(secret: secret))
        if advertise {
            listener.service = NWListener.Service(
                name: PairingCrypto.serviceName(secret: secret), type: PairingCrypto.serviceType)
        }
        self.decide = decide
        self.onFinish = onFinish
    }

    /// Starts listening; the port once ready.
    public func start() async throws -> NWEndpoint.Port {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let once = Once()
        let listener = listener
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<NWEndpoint.Port, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { done.resume(returning: listener.port ?? .any) }
                case .failed, .cancelled: once.run { done.resume(throwing: PairingError.connectionFailed) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Stops listening and drops every open connection.
    public func stop() {
        listener.cancel()
        lock.lock()
        let open = connections
        connections = []
        lock.unlock()
        open.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        let done = claimed
        if !done { connections.append(connection) }
        lock.unlock()
        guard !done else {
            connection.cancel()
            return
        }
        Task { await self.serve(connection) }
    }

    /// The first valid request claims the code.
    private func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }

    private func serve(_ connection: NWConnection) async {
        do {
            try await PairingWire.start(connection, queue: queue)
            let request = try JSONDecoder().decode(PairingRequest.self, from: try await PairingWire.receive(on: connection))
            guard request.v == 1 else { throw PairingError.badMessage }
            guard claim() else {
                connection.cancel()
                return
            }
            let allowed = request.acceptedKey == nil ? false : await decide(request)
            let response = try JSONEncoder().encode(PairingResponse(result: allowed ? .allowed : .denied))
            try? await PairingWire.send(response, on: connection)
            stop()
            onFinish(allowed)
        } catch {
            connection.cancel()
        }
    }
}

/// The phone's side of pairing.
public enum PairingClient {
    /// Finds the Mac showing this code nearby (same Wi-Fi, or peer-to-peer).
    public static func find(secret: Data, timeout: TimeInterval = 20) async throws -> NWEndpoint {
        let wanted = PairingCrypto.serviceName(secret: secret)
        let browser = NWBrowser(
            for: .bonjour(type: PairingCrypto.serviceType, domain: nil),
            using: PairingCrypto.parameters(secret: secret))
        let queue = DispatchQueue(label: "com.lawliang.lostty.pairing.browse")
        let once = Once()
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<NWEndpoint, Error>) in
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint, name == wanted {
                        once.run {
                            browser.cancel()
                            done.resume(returning: result.endpoint)
                        }
                        return
                    }
                }
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error) where isPolicyDenied(error), .failed(let error) where isPolicyDenied(error):
                    once.run {
                        browser.cancel()
                        done.resume(throwing: PairingError.localNetworkDenied)
                    }
                case .failed:
                    once.run {
                        browser.cancel()
                        done.resume(throwing: PairingError.macNotFound)
                    }
                default:
                    break
                }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                once.run {
                    browser.cancel()
                    done.resume(throwing: PairingError.macNotFound)
                }
            }
        }
    }

    /// Sends `request` to the Mac and waits for its answer while the Allow
    /// prompt is up, at most `timeout` (then the connection is cancelled,
    /// which ends the pending read).
    public static func send(
        _ request: PairingRequest,
        to endpoint: NWEndpoint,
        secret: Data,
        timeout: TimeInterval = 150
    ) async throws -> PairingResponse {
        let queue = DispatchQueue(label: "com.lawliang.lostty.pairing.client")
        let connection = NWConnection(to: endpoint, using: PairingCrypto.parameters(secret: secret))
        let deadline = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            connection.cancel()
        }
        try await PairingWire.start(connection, queue: queue)
        try await PairingWire.send(try JSONEncoder().encode(request), on: connection)
        let response = try JSONDecoder().decode(PairingResponse.self, from: try await PairingWire.receive(on: connection))
        guard response.v == 1 else { throw PairingError.badMessage }
        return response
    }

    /// iOS reports a denied Local Network permission as DNS-SD's
    /// kDNSServiceErr_PolicyDenied (-65570).
    static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == -65570 }
        return false
    }
}
