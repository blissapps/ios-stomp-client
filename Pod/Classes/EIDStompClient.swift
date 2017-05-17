//
//  EIDStompClient.swift
//
//  Created by Alexander Köhn
//

import UIKit
import SocketRocket

struct StompCommands {
    static let commandConnect = "CONNECT"
    static let commandSend = "SEND"
    static let commandSubscribe = "SUBSCRIBE"
    static let commandUnsubscribe = "UNSUBSCRIBE"
    static let commandBegin = "BEGIN"
    static let commandCommit = "COMMIT"
    static let commandAbort = "ABORT"
    static let commandAck = "ACK"
    static let commandDisconnect = "DISCONNECT"
    static let commandPing = "\n"
    
    static let controlChar = String(format: "%C", arguments: [0x00])
    
    static let ackClient = "client"
    static let ackAuto = "auto"
    
    static let commandHeaderReceipt = "receipt"
    static let commandHeaderDestination = "destination"
    static let commandHeaderDestinationId = "id"
    static let commandHeaderContentLength = "content-length"
    static let commandHeaderContentType = "content-type"
    static let commandHeaderAck = "ack"
    static let commandHeaderTransaction = "transaction"
    static let commandHeaderMessageId = "message-id"
    static let commandHeaderSubscription = "subscription"
    static let commandHeaderDisconnected = "disconnected"
    static let commandHeaderHeartBeat = "heart-beat"
    static let commandHeaderAcceptVersion = "accept-version"

    static let responseHeaderSession = "session"
    static let responseHeaderReceiptId = "receipt-id"
    static let responseHeaderErrorMessage = "message"
    
    static let responseFrameConnected = "CONNECTED"
    static let responseFrameMessage = "MESSAGE"
    static let responseFrameReceipt = "RECEIPT"
    static let responseFrameError = "ERROR"
}

public enum EIDStompAckMode {
    case autoMode
    case clientMode
}

public protocol EIDStompClientDelegate {
    
    func stompClient(_ client: EIDStompClient!, didReceiveMessageWithJSONBody jsonBody: AnyObject?, withHeader header:[String:String]?, withDestination destination: String)
    
    func stompClientDidDisconnect(_ client: EIDStompClient!)
    func stompClientWillDisconnect(_ client: EIDStompClient!, withError error: NSError)
    func stompClientDidConnect(_ client: EIDStompClient!)
    func serverDidSendReceipt(_ client: EIDStompClient!, withReceiptId receiptId: String)
    func serverDidSendError(_ client: EIDStompClient!, withErrorMessage description: String, detailedErrorMessage message: String?)
    func serverDidSendPing()
}

open class EIDStompClient: NSObject, SRWebSocketDelegate {


    public var socket: SRWebSocket?
    var sessionId: String?
    var delegate: EIDStompClientDelegate?
    var connectionHeaders: [String: String]?
    open var certificateCheckEnabled = true
    var maxWebSocketFrameSize = 12000
    
    fileprivate var urlRequest: URLRequest?
    
    open func sendJSONForDict(_ dict: AnyObject, toDestination destination: String) {
        do {
            let theJSONData = try JSONSerialization.data(withJSONObject: dict, options: JSONSerialization.WritingOptions())
            let theJSONText = String(data: theJSONData, encoding: String.Encoding.utf8)
            //print(theJSONText!)
            let header = [StompCommands.commandHeaderContentType:"application/json;charset=UTF-8"]
            sendMessage(theJSONText!, toDestination: destination, withHeaders: header, withReceipt: nil)
        } catch {
            print("error serializing JSON: \(error)")
        }
    }
    
    open func openSocketWithURLRequest(_ request: URLRequest, delegate: EIDStompClientDelegate) {
        self.delegate = delegate
        self.urlRequest = request
        
        openSocket()
    }
    
    open func openSocketWithURLRequest(_ request: URLRequest, delegate: EIDStompClientDelegate, connectionHeaders: [String: String]?) {
        self.connectionHeaders = connectionHeaders
        openSocketWithURLRequest(request, delegate: delegate)
    }
    
    fileprivate func openSocket() {
        if socket == nil || socket?.readyState == .CLOSED {
            if certificateCheckEnabled == true {
                self.socket = SRWebSocket(urlRequest: urlRequest)
            } else {
                self.socket = SRWebSocket(urlRequest: urlRequest, protocols: [], allowsUntrustedSSLCertificates: true)
            }

            socket!.delegate = self
            socket!.open()
        }
    }
    
    fileprivate func connect() {
        if socket?.readyState == .OPEN {
            // at the moment only anonymous logins
            self.sendFrame(StompCommands.commandConnect, header: connectionHeaders, body: nil)
        } else {
            self.openSocket()
        }
    }
    
    
    open func webSocket(_ webSocket: SRWebSocket!, didReceiveMessage message: Any!) {
//        print("didReceiveMessage")
        
        func processString(_ string: String) {
            var contents = string.components(separatedBy: "\n")
            if contents.first == "" {
                contents.removeFirst()
            }
            
            if let command = contents.first {
                var headers = [String: String]()
                var body = ""
                var hasHeaders  = false
                
                contents.removeFirst()
                for line in contents {
                    if hasHeaders == true {
                        body += line
                    } else {
                        if line == "" {
                            hasHeaders = true
                        } else {
                            let parts = line.components(separatedBy: ":")
                            if let key = parts.first {
                                headers[key] = parts.last
                            }
                        }
                    }
                }
                
                //remove garbage from body
                if body.hasSuffix("\0") {
                    body = body.replacingOccurrences(of: "\0", with: "")
                }
                
                receiveFrame(command, headers: headers, body: body)
            }
        }
        
        if let strData = message as? Data {
            if let msg = String(data: strData, encoding: String.Encoding.utf8) {
                processString(msg)
            }
        } else if let str = message as? String {
            processString(str)
        }
    }
    
    open func webSocketDidOpen(_ webSocket: SRWebSocket!) {
        print("webSocketDidOpen")
        connect()
    }
    
    open func webSocket(_ webSocket: SRWebSocket!, didFailWithError error: Error!) {
        print("didFailWithError: \(error)")
        
        if let delegate = delegate {
            DispatchQueue.main.async(execute: {
                delegate.serverDidSendError(self, withErrorMessage: "Fail Error.", detailedErrorMessage: error.localizedDescription)
            })
        }
    }
    
    open func webSocket(_ webSocket: SRWebSocket!, didCloseWithCode code: Int, reason: String!, wasClean: Bool) {
        print("didCloseWithCode \(code), reason: \(reason)")
        if let delegate = delegate {
            DispatchQueue.main.async(execute: {
                delegate.stompClientDidDisconnect(self)
            })
        }
    }
    
    open func webSocket(_ webSocket: SRWebSocket!, didReceivePong pongPayload: Data!) {
        print("didReceivePong")
    }
    
    fileprivate func sendFrame(_ command: String?, header: [String: String]?, body: AnyObject?) {
        if socket?.readyState == .OPEN {
            var frameString = ""
            if command != nil {
                frameString = command! + "\n"
            }
            
            if let header = header {
                for (key, value) in header {
                    frameString += key
                    frameString += ":"
                    frameString += value
                    frameString += "\n"
                }
            }
            
            if let body = body as? String {
                frameString += "\n"
                frameString += body
            } else if let _ = body as? Data {
                //EID, 20151015: do we need to implemenet this?
            }
            
            if body == nil {
                frameString += "\n"
            }
            
            frameString += StompCommands.controlChar
            
            if socket?.readyState == .OPEN {
            
                    //                socket?.send(frameString)
                    
                    //                var frameNSString = NSString(string: frameString)
                    while true {
                        
                        if frameString.characters.count > self.maxWebSocketFrameSize {
                            //                        socket!.send(frameNSString.substringToIndex(self.maxWebSocketFrameSize))
                            //                        frameNSString = frameNSString.substringFromIndex(self.maxWebSocketFrameSize)
                            
                            let index = frameString.index(frameString.startIndex, offsetBy: self.maxWebSocketFrameSize)
//                            let index: String.Index = frameString.startIndex.advanced(by: self.maxWebSocketFrameSize)
                            socket!.send(frameString.substring(to: index))
                            frameString = frameString.substring(from: index)
                            
                            
                        } else {
                            socket!.send(frameString)
                            break
                        }
                        
                    }
            } else {
                print("no socket connection")
                if let delegate = delegate {
                    DispatchQueue.main.async(execute: {
                        delegate.stompClientDidDisconnect(self)
                    })
                }
            }
        }
    }
    
    fileprivate func destinationFromHeader(_ header: [String: String]) -> String {
        for (key, _) in header {
            if key == "destination" {
                let destination = header[key]!
                return destination
            }
        }
        return ""
    }
    
    fileprivate func dictForJSONString(_ jsonStr: String?) -> AnyObject? {
        if let jsonStr = jsonStr {
            do {
                if let data = jsonStr.data(using: String.Encoding.utf8) {
                    let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                    return json as AnyObject?
                }
            } catch {
                print("error serializing JSON: \(error)")
            }
        }
        return nil
    }
    
    fileprivate func receiveFrame(_ command: String, headers: [String: String], body: String?) {
        if command == StompCommands.responseFrameConnected {
            // Connected
            if let sessId = headers[StompCommands.responseHeaderSession] {
                sessionId = sessId
            }
            
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.stompClientDidConnect(self)
                })
            }
        } else if command == StompCommands.responseFrameMessage {
            // Resonse

            if headers["content-type"]?.lowercased().range(of: "application/json") != nil {
                if let delegate = delegate {
                    DispatchQueue.main.async(execute: {
                        delegate.stompClient(self, didReceiveMessageWithJSONBody: self.dictForJSONString(body), withHeader: headers, withDestination: self.destinationFromHeader(headers))
                    })
                }
            } else {
                // TODO: send binary data back
            }
        } else if command == StompCommands.responseFrameReceipt {
            // Receipt
            if let delegate = delegate {
                if let receiptId = headers[StompCommands.responseHeaderReceiptId] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendReceipt(self, withReceiptId: receiptId)
                    })
                }
            }
        } else if command.characters.count == 0 {
            // Pong from the server
            socket?.send(StompCommands.commandPing)
            
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.serverDidSendPing()
                })
            }
        } else if command == StompCommands.responseFrameError {
            // Error
            if let delegate = delegate {
                if let msg = headers[StompCommands.responseHeaderErrorMessage] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendError(self, withErrorMessage: msg, detailedErrorMessage: body)
                    })
                }
            }
        }
    }
    
    open func sendMessage(_ message: String, toDestination destination: String, withHeaders headers: [String: String]?, withReceipt receipt: String?) {
        var headersToSend = [String: String]()
        if let headers = headers {
            headersToSend = headers
        }
        
        // Setting up the receipt.
        if let receipt = receipt {
            headersToSend[StompCommands.commandHeaderReceipt] = receipt
        }
        
        headersToSend[StompCommands.commandHeaderDestination] = destination
        
        // Setting up the content length.
        let contentLength = message.utf8.count
        headersToSend[StompCommands.commandHeaderContentLength] = "\(contentLength)"
        
        // Setting up content type as plain text.
        if headersToSend[StompCommands.commandHeaderContentType] == nil {
            headersToSend[StompCommands.commandHeaderContentType] = "text/plain"
        }
        
        sendFrame(StompCommands.commandSend, header: headersToSend, body: message as AnyObject?)
    }
    
    open func subscribeToDestination(_ destination: String) {
        subscribeToDestination(destination, withAck: .autoMode)
    }
    
    open func subscribeToDestination(_ destination: String, withAck ackMode: EIDStompAckMode) {
        var ack = ""
        switch ackMode {
        case EIDStompAckMode.clientMode:
            ack = StompCommands.ackClient
            break
        default:
            ack = StompCommands.ackAuto
            break
        }
        
        let headers = [StompCommands.commandHeaderDestination: destination, StompCommands.commandHeaderAck: ack, StompCommands.commandHeaderDestinationId: ""]
        
        self.sendFrame(StompCommands.commandSubscribe, header: headers, body: nil)
    }
    
    open func subscribeToDestination(_ destination: String, withHeader header: [String: String]) {
        var headerToSend = header
        headerToSend[StompCommands.commandHeaderDestination] = destination
        sendFrame(StompCommands.commandSubscribe, header: headerToSend, body: nil)
    }
    
    open func unsubscribeFromDestination(_ destination: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderDestinationId] = destination
        sendFrame(StompCommands.commandUnsubscribe, header: headerToSend, body: nil)
    }

    open func begin(_ transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(StompCommands.commandBegin, header: headerToSend, body: nil)
    }

    open func commit(_ transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(StompCommands.commandCommit, header: headerToSend, body: nil)
    }
    
    open func abort(_ transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(StompCommands.commandAbort, header: headerToSend, body: nil)
    }
    
    open func ack(_ messageId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        sendFrame(StompCommands.commandAck, header: headerToSend, body: nil)
    }

    open func ack(_ messageId: String, withSubscription subscription: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        headerToSend[StompCommands.commandHeaderSubscription] = subscription
        sendFrame(StompCommands.commandAck, header: headerToSend, body: nil)
    }
    
    open func disconnect() {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandDisconnect] = String(Int(Date().timeIntervalSince1970))
        sendFrame(StompCommands.commandDisconnect, header: headerToSend, body: nil)
    }
}
