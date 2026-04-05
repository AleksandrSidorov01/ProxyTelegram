import Foundation
import MtProtoKit

@available(iOS 13.0, *)
final class WebSocketTunnelConnectionInterface: NSObject, MTTcpConnectionInterface, URLSessionWebSocketDelegate {
    private struct ReadRequest {
        let length: Int
        let tag: Int
    }

    private let queue: DispatchQueue
    private weak var delegate: MTTcpConnectionInterfaceDelegate?
    private let delegateQueue: DispatchQueue
    private let datacenterId: Int

    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveBuffer = Data()
    private var readRequests: [ReadRequest] = []
    private var isConnected = false
    private var reportedDisconnection = false

    private var pingTimer: DispatchSourceTimer?
    private let pingInterval: TimeInterval = 30.0

    init(delegate: MTTcpConnectionInterfaceDelegate, delegateQueue: DispatchQueue, datacenterId: Int) {
        self.delegate = delegate
        self.delegateQueue = delegateQueue
        self.datacenterId = datacenterId
        self.queue = DispatchQueue(label: "ws.tunnel.connection.\(datacenterId)")
        super.init()
    }

    deinit {
        pingTimer?.cancel()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()
    }

    // MARK: - MTTcpConnectionInterface

    func setGetLogPrefix(_ getLogPrefix: (() -> String)?) {
    }

    func setUsageCalculationInfo(_ usageCalculationInfo: MTNetworkUsageCalculationInfo?) {
    }

    func connect(toHost inHost: String, onPort port: UInt16, viaInterface inInterface: String?, withTimeout timeout: TimeInterval, error errPtr: NSErrorPointer) -> Bool {
        queue.async { [weak self] in
            self?.performConnect(originalHost: inHost, originalPort: port, timeout: timeout)
        }
        return true
    }

    func write(_ data: Data) {
        queue.async { [weak self] in
            self?.performWrite(data: data)
        }
    }

    func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.readRequests.append(ReadRequest(length: Int(length), tag: tag))
            self.processReadRequests()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.performDisconnect(error: nil)
        }
    }

    func resetDelegate() {
        self.delegate = nil
    }

    // MARK: - Connection

    private func performConnect(originalHost: String, originalPort: UInt16, timeout: TimeInterval) {
        guard let wsURL = WebSocketTunnelManager.wsEndpoint(forDC: datacenterId) else {
            NSLog("[WSTunnel] No WS endpoint for DC \(datacenterId), falling back")
            performDisconnect(error: NSError(domain: "WSTunnel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No WS endpoint for DC \(datacenterId)"]))
            return
        }

        if !WebSocketTunnelManager.shared.isDCAvailable(datacenterId) {
            NSLog("[WSTunnel] DC \(datacenterId) marked as WS-unavailable, falling back")
            performDisconnect(error: NSError(domain: "WSTunnel", code: -2, userInfo: [NSLocalizedDescriptionKey: "DC \(datacenterId) WS unavailable"]))
            return
        }

        NSLog("[WSTunnel] Connecting to DC \(datacenterId) via \(wsURL.absoluteString)")

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = timeout > 0 ? timeout : 10.0

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false

        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 2 * 1024 * 1024
        self.webSocketTask = task
        task.resume()

        // Timeout handling
        queue.asyncAfter(deadline: .now() + (timeout > 0 ? timeout : 10.0)) { [weak self] in
            guard let self = self, !self.isConnected else { return }
            NSLog("[WSTunnel] Connection to DC \(self.datacenterId) timed out")
            self.performDisconnect(error: NSError(domain: "WSTunnel", code: -3, userInfo: [NSLocalizedDescriptionKey: "Connection timeout"]))
        }
    }

    private func performWrite(data: Data) {
        guard let task = webSocketTask, isConnected else { return }
        let message = URLSessionWebSocketTask.Message.data(data)
        task.send(message) { [weak self] error in
            if let error = error {
                self?.queue.async {
                    NSLog("[WSTunnel] Write error DC \(self?.datacenterId ?? 0): \(error.localizedDescription)")
                    self?.performDisconnect(error: error)
                }
            }
        }
    }

    private func performDisconnect(error: Error?) {
        pingTimer?.cancel()
        pingTimer = nil

        isConnected = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        if !reportedDisconnection {
            reportedDisconnection = true
            let delegate = self.delegate
            delegateQueue.async {
                delegate?.connectionInterfaceDidDisconnectWithError(error)
            }
        }
    }

    // MARK: - WebSocket receive loop

    private func startReceiveLoop() {
        guard let task = webSocketTask else { return }
        task.receive { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                switch result {
                case .success(let message):
                    switch message {
                    case .data(let data):
                        self.receiveBuffer.append(data)
                        self.processReadRequests()
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            self.receiveBuffer.append(data)
                            self.processReadRequests()
                        }
                    @unknown default:
                        break
                    }
                    self.startReceiveLoop()
                case .failure(let error):
                    NSLog("[WSTunnel] Receive error DC \(self.datacenterId): \(error.localizedDescription)")
                    self.performDisconnect(error: error)
                }
            }
        }
    }

    // MARK: - Read request processing

    private func processReadRequests() {
        while !readRequests.isEmpty {
            let request = readRequests[0]
            if receiveBuffer.count >= request.length {
                let data = receiveBuffer.prefix(request.length)
                receiveBuffer = Data(receiveBuffer.dropFirst(request.length))
                readRequests.removeFirst()

                let readData = Data(data)
                let tag = request.tag
                let delegate = self.delegate
                delegateQueue.async {
                    delegate?.connectionInterfaceDidRead(readData, withTag: tag, networkType: 0)
                }
            } else {
                // Partial data notification
                if receiveBuffer.count > 0 {
                    let partialLength = UInt(receiveBuffer.count)
                    let tag = request.tag
                    let delegate = self.delegate
                    delegateQueue.async {
                        delegate?.connectionInterfaceDidReadPartialData(ofLength: partialLength, tag: tag)
                    }
                }
                break
            }
        }
    }

    // MARK: - Ping keepalive

    private func startPingTimer() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in
            self?.sendPing()
        }
        timer.resume()
        pingTimer = timer
    }

    private func sendPing() {
        guard let task = webSocketTask, isConnected else { return }
        task.sendPing { [weak self] error in
            if let error = error {
                self?.queue.async {
                    NSLog("[WSTunnel] Ping failed DC \(self?.datacenterId ?? 0): \(error.localizedDescription)")
                    self?.performDisconnect(error: error)
                }
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            NSLog("[WSTunnel] Connected to DC \(self.datacenterId) via WS tunnel")
            self.isConnected = true
            WebSocketTunnelManager.shared.connectionStatus = .tunnel(dcId: self.datacenterId)
            WebSocketTunnelManager.shared.confirmTunnelNeeded(forDC: self.datacenterId)

            self.startReceiveLoop()
            self.startPingTimer()

            let delegate = self.delegate
            self.delegateQueue.async {
                delegate?.connectionInterfaceDidConnect()
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            NSLog("[WSTunnel] WS closed DC \(self.datacenterId), code: \(closeCode.rawValue)")
            self.performDisconnect(error: nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let error = error {
                NSLog("[WSTunnel] Task error DC \(self.datacenterId): \(error.localizedDescription)")

                // Check for HTTP redirect (302) - mark DC as WS-unavailable
                if let urlError = error as? URLError, urlError.code == .httpTooManyRedirects || urlError.code == .redirectToNonExistentLocation {
                    WebSocketTunnelManager.shared.markDCUnavailable(self.datacenterId)
                }
            }
            self.performDisconnect(error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // 302 redirect means WS endpoint is not available for this DC
        if response.statusCode == 302 {
            NSLog("[WSTunnel] DC \(datacenterId) returned 302 redirect, marking WS unavailable")
            WebSocketTunnelManager.shared.markDCUnavailable(datacenterId)
        }
        // Do not follow redirect - cancel the connection
        completionHandler(nil)
    }
}
