import Foundation

public enum WSTunnelMode: Int {
    case auto = 0
    case always = 1
    case disabled = 2
}

public enum WSTunnelConnectionStatus {
    case direct
    case tunnel(dcId: Int)
    case disconnected
}

public final class WebSocketTunnelManager {
    public static let shared = WebSocketTunnelManager()

    private let queue = DispatchQueue(label: "ws.tunnel.manager")

    public var tunnelMode: WSTunnelMode {
        get {
            let raw = UserDefaults.standard.integer(forKey: "ws_tunnel_mode")
            return WSTunnelMode(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "ws_tunnel_mode")
            if newValue == .disabled {
                queue.sync { _autoTunnelDCs.removeAll() }
            }
        }
    }

    private var _connectionStatus: WSTunnelConnectionStatus = .disconnected
    public var connectionStatus: WSTunnelConnectionStatus {
        get { return queue.sync { _connectionStatus } }
        set { queue.sync { _connectionStatus = newValue } }
    }

    // MARK: - WS availability cache

    // DC IDs where WS endpoint returned 302 or is unavailable
    private var _unavailableDCs: [Int: Date] = [:]
    private let unavailabilityCacheDuration: TimeInterval = 300 // 5 min

    public func markDCUnavailable(_ dcId: Int) {
        queue.sync {
            _unavailableDCs[dcId] = Date()
        }
    }

    public func isDCAvailable(_ dcId: Int) -> Bool {
        return queue.sync {
            guard let markedDate = _unavailableDCs[dcId] else { return true }
            if Date().timeIntervalSince(markedDate) > unavailabilityCacheDuration {
                _unavailableDCs.removeValue(forKey: dcId)
                return true
            }
            return false
        }
    }

    public func clearUnavailabilityCache() {
        queue.sync {
            _unavailableDCs.removeAll()
        }
    }

    // MARK: - Auto mode: TCP-first with WS fallback

    // Tracks connection attempts per DC for auto mode.
    // First attempt = TCP (return nil from factory). If TCP fails and
    // the factory is called again, the counter increments and WS is returned.
    private var _connectionAttempts: [Int: Int] = [:]

    // DCs that have been confirmed to need WS tunnel (TCP failed, WS succeeded)
    private var _autoTunnelDCs: Set<Int> = []

    /// Called by the factory for each connection attempt in auto mode.
    /// Returns true if WS should be used for this DC.
    public func shouldUseTunnelInAutoMode(forDC dcId: Int) -> Bool {
        return queue.sync {
            if _autoTunnelDCs.contains(dcId) {
                return true
            }
            let attempts = (_connectionAttempts[dcId] ?? 0) + 1
            _connectionAttempts[dcId] = attempts
            // First attempt: try TCP. Second+ attempt: try WS.
            return attempts > 1
        }
    }

    /// Called when WS tunnel connects successfully in auto mode.
    /// Marks this DC as needing WS tunnel for subsequent connections.
    public func confirmTunnelNeeded(forDC dcId: Int) {
        queue.sync {
            _autoTunnelDCs.insert(dcId)
            _connectionAttempts.removeValue(forKey: dcId)
        }
    }

    /// Called when TCP connects successfully.
    /// Resets the attempt counter so TCP is tried first next time.
    public func confirmTCPWorking(forDC dcId: Int) {
        queue.sync {
            _autoTunnelDCs.remove(dcId)
            _connectionAttempts.removeValue(forKey: dcId)
        }
    }

    // MARK: - Endpoints

    public static func wsEndpoint(forDC dcId: Int) -> URL? {
        guard dcId >= 1 && dcId <= 5 else { return nil }
        return URL(string: "wss://kws\(dcId).web.telegram.org/apiws")
    }

    private init() {}
}
