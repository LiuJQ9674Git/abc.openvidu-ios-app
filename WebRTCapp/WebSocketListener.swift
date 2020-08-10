//
//  WebSocketListener.swift
//  WebRTCapp
//
//  WebSocket监听
//  Copyright © 2018 Sergio Paniego Blanco. All rights reserved.
//

import Foundation
import Starscream
import WebRTC

class WebSocketListener: WebSocketDelegate {
    let JSON_RPCVERSION = "2.0"
    let useSSL = true
    var socket: WebSocket
    var helloWorldTimer: Timer?
    var id = 0
    var url: String
    var sessionName: String
    var participantName: String
    var localOfferParams: [String: String]?
    var iceCandidatesParams: [[String:String]]?
    var userId: String?
    var remoteParticipantId: String?
    var participants: [String: RemoteParticipant]
    var localPeer: RTCPeerConnection?
    var peersManager: PeersManager
    var token: String
    var views: [UIView]!
    var names: [UILabel]!
	
    init(url: String, sessionName: String, participantName: String,
         peersManager: PeersManager, token: String, views: [UIView], names: [UILabel]) {
        self.url = url
        self.sessionName = sessionName
        self.participantName = participantName
        self.peersManager = peersManager
        self.localPeer = self.peersManager.localPeer
        self.iceCandidatesParams = []
        self.token = token
        self.participants = [String: RemoteParticipant]()
        self.views = views
        self.names = names
        socket = WebSocket(url: URL(string: url)!)
        socket.disableSSLCertValidation = useSSL
        socket.delegate = self
        //初始化时建立连接
        socket.connect()
    }
    
    func websocketDidConnect(socket: WebSocketClient) {
        print("Connected")
        pingMessageHandler()
        var joinRoomParams: [String: String] = [:]
        joinRoomParams["recorder"] = "false"
        joinRoomParams["platform"] = "iOS"
        joinRoomParams[JSONConstants.Metadata] = "{\"clientData\": \"" + "iOSUserP_1" + "\"}"
        joinRoomParams["secret"] = "MY_SECRET"
        joinRoomParams["session"] = sessionName
        joinRoomParams["token"] = token
        sendJson(method: "joinRoom", params: joinRoomParams)
        if localOfferParams != nil {
            sendJson(method: "publishVideo",params: localOfferParams!)
        }
    }
    
    func pingMessageHandler() {
        helloWorldTimer = Timer.scheduledTimer(timeInterval: 5, target: self,
                    selector: #selector(WebSocketListener.doPing), userInfo: nil, repeats: true)
        doPing()
    }
    
    @objc func doPing() {
        var pingParams: [String: String] = [:]
        pingParams["interval"] = "5000"
        sendJson(method: "ping", params: pingParams)
        socket.write(ping: Data())
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("Disconnect: " + error.debugDescription)
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        print("Recieved message: " + text)
        let data = text.data(using: .utf8)!
        do {
            let json: [String: Any] = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as! [String : Any]
            
            if json[JSONConstants.Result] != nil {
                handleResult(json: json)
            } else {
                handleMethod(json: json)
            }
            
        } catch let error as NSError {
            print("ERROR parsing JSON: ", error)
        }
    }
    
    func handleResult(json: [String: Any]) {
        let result: [String: Any] = json[JSONConstants.Result] as! [String: Any]
        if result[JSONConstants.SdpAnswer] != nil {
            saveAnswer(json: result)
        } else if result[JSONConstants.SessionId] != nil {
            if result[JSONConstants.Value] != nil {
                let value = result[JSONConstants.Value]  as! [[String:Any]]
                if !value.isEmpty {
                    addParticipantsAlreadyInRoom(result: result)
                }
                self.userId = result[JSONConstants.Id] as? String
                for var iceCandidate in iceCandidatesParams! {
                    iceCandidate["endpointName"] = self.userId
                    sendJson(method: "onIceCandidate", params:  iceCandidate)
                }
            }
        } else if result[JSONConstants.Value] != nil {
            print("pong")
        } else {
            print("Unrecognized")
        }
    }
    
    func addParticipantsAlreadyInRoom(result: [String: Any]) {
        let values = result[JSONConstants.Value] as! [[String: Any]]
        for participant in values {
            print(participant[JSONConstants.Id]!)
            self.remoteParticipantId = participant[JSONConstants.Id]! as? String
            let remoteParticipant = RemoteParticipant()
            remoteParticipant.id = participant[JSONConstants.Id] as? String
            let metadataString = participant[JSONConstants.Metadata] as! String
            let data = metadataString.data(using: .utf8)!
            do {
                if let metadata = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as? Dictionary<String,Any>
                {
                    remoteParticipant.participantName = metadata["clientData"] as? String
                }
            } catch let error as NSError {
                print(error)
            }
            self.participants[remoteParticipant.id!] = remoteParticipant
            self.peersManager.createRemotePeerConnection(remoteParticipant: remoteParticipant)
            let mandatoryConstraints = ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"]
            let sdpConstraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
            remoteParticipant.peerConnection!.offer(for: sdpConstraints, completionHandler: {(sessionDescription, error) in
                print("Remote Offer: " + error.debugDescription)
                self.participants[remoteParticipant.id!]!.peerConnection!.setLocalDescription(sessionDescription!, completionHandler: {(error) in
                    print("Remote Peer Local Description set " + error.debugDescription)
                })
                var remoteOfferParams: [String:String] = [:]
                remoteOfferParams["sdpOffer"] = sessionDescription!.sdp
                remoteOfferParams["sender"] = self.remoteParticipantId! + "_CAMERA"
                self.sendJson(method: "receiveVideoFrom", params: remoteOfferParams)
            })
            self.peersManager.remotePeer!.delegate = self.peersManager
        }
    }

    func saveAnswer(json: [String:Any]) {
        let sessionDescription = RTCSessionDescription(type: RTCSdpType.answer, sdp: json["sdpAnswer"] as! String)
        if localPeer == nil {
            self.localPeer = self.peersManager.localPeer
        }
        if (localPeer!.remoteDescription != nil) { //远程远端描述为空
            participants[remoteParticipantId!]!.peerConnection!.setRemoteDescription(sessionDescription, completionHandler: {(error) in
                print("Remote Peer Remote Description set: " + error.debugDescription)
                if self.peersManager.remoteStreams.count >= self.participants.count {
                    DispatchQueue.main.async {
                        print("参与者共计Count: " + self.participants.count.description)
                        let renderer = RTCEAGLVideoView(frame:  self.views[self.participants.count-1].frame)
                        let videoTrack = self.peersManager.remoteStreams[self.participants.count-1].videoTracks[0]
                        videoTrack.add(renderer)
                        // Add the view and name to the first free space available
                        var index = 0
                        while (index < 2 && !(self.names[index].text?.isEmpty)!) {
                            index += 1
                        }
                        if index < 2 {
                            self.names[index].text = self.participants[self.remoteParticipantId!]?.participantName
                            self.names[index].backgroundColor = UIColor.black
                            self.names[index].textColor = UIColor.white
                            self.embedView(renderer, into: self.views[index])
                            self.participants[self.remoteParticipantId!]?.index = index
                            self.views[index].bringSubview(toFront: self.names[index])
                        }
                    }
                }
            })
        } else {
            localPeer!.setRemoteDescription(sessionDescription, completionHandler: {(error) in
                print("Local Peer Remote Description set: " + error.debugDescription)
            })
        }
    }
    
    func handleMethod(json: Dictionary<String,Any>) {
        if json[JSONConstants.Params] != nil {
            let method = json[JSONConstants.Method] as! String
            let params = json[JSONConstants.Params] as! Dictionary<String, Any>
            switch method {
                case JSONConstants.IceCandidate:
                    iceCandidateMethod(params: params)
                case JSONConstants.ParticipantJoined:
                    participantJoinedMethod(params: params)
                case JSONConstants.ParticipantPublished: //参与者加入
                    participantPublished(params: params)
                case JSONConstants.ParticipantLeft: //参与者离开动作
                    participantLeft(params: params)
            default:
                print("Error handleMethod, " + "method '" + method + "' is not implemented")
            }
        }
    }
    func iceCandidateMethod(params: Dictionary<String, Any>) {
        if (params["endpointName"] as? String == userId) {
            saveIceCandidate(json: params, endPointName: nil)
        } else {
            saveIceCandidate(json: params, endPointName: params["endpointName"] as? String)
        }
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print("Received data: " + data.description)
    }
    
    func participantJoinedMethod(params: Dictionary<String, Any>) {
        let remoteParticipant = RemoteParticipant()
        remoteParticipant.id = params[JSONConstants.Id] as? String
        self.participants[params[JSONConstants.Id] as! String] = remoteParticipant
        let metadataString = params[JSONConstants.Metadata] as! String
        let data = metadataString.data(using: .utf8)!
        do {
            if let metadata = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as? Dictionary<String,Any>
            {
                remoteParticipant.participantName = metadata["clientData"] as? String
                self.peersManager.createRemotePeerConnection(remoteParticipant: remoteParticipant)
            } else {
                print("bad json")
            }
        } catch let error as NSError {
            print(error)
        }
    }
    
    func participantPublished(params: Dictionary<String, Any>) {
        self.remoteParticipantId = params[JSONConstants.Id] as? String
        print("ID: " + remoteParticipantId!)
        let remoteParticipantPublished = participants[remoteParticipantId!]!
        let mandatoryConstraints = ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"]
        remoteParticipantPublished.peerConnection!.offer(for: RTCMediaConstraints.init(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil), completionHandler: { (sessionDescription, error) in
            remoteParticipantPublished.peerConnection!.setLocalDescription(sessionDescription!, completionHandler: {(error) in
                print("Remote Peer Local Description set")
            })
            var remoteOfferParams:  [String: String] = [:]
            remoteOfferParams["sdpOffer"] = sessionDescription!.description
            remoteOfferParams["sender"] = remoteParticipantPublished.id! + "_webcam"
            self.sendJson(method: "receiveVideoFrom", params: remoteOfferParams)
        })
        self.peersManager.remotePeer!.delegate = self.peersManager
    }
    
    func participantLeft(params: Dictionary<String, Any>) {
        print("participants", participants)
        print("params", params)
        let participantId = params["connectionId"] as! String
        participants[participantId]!.peerConnection!.close()
        //存在Bug LiuJQ
        //REMOVE VIEW
//        let renderer = RTCEAGLVideoView(frame:  self.views[self.participants.count-1].frame)
        
//        let videoTrack = self.peersManager.remoteStreams[0].videoTracks[0]
//        videoTrack.remove(renderer)
//		if let index = self.participants.keys.index(of: participantId) {
//			let i = participants.distance(from: participants.startIndex, to: index)
//			self.views[i].willRemoveSubview(renderer)
//			self.names[i].text = ""
//			self.names[i].backgroundColor = UIColor.clear
//		}
//        participants.removeValue(forKey: participantId)
    }
    
    func saveIceCandidate(json: Dictionary<String, Any>, endPointName: String?) {
        let iceCandidate = RTCIceCandidate(sdp: json["candidate"] as! String, sdpMLineIndex: json["sdpMLineIndex"] as! Int32, sdpMid: json["sdpMid"] as? String)
        if (endPointName == nil || participants[endPointName!] == nil) {
            self.localPeer = self.peersManager.localPeer
            self.localPeer!.add(iceCandidate)
        } else {
            participants[endPointName!]!.peerConnection!.add(iceCandidate)
        }
    }
    
    func sendJson(method: String, params: [String: String]) {
        let json: NSMutableDictionary = NSMutableDictionary()
        json.setValue(method, forKey: JSONConstants.Method)
        json.setValue(id, forKey: JSONConstants.Id)
        id += 1
        json.setValue(params, forKey: JSONConstants.Params)
        json.setValue(JSON_RPCVERSION, forKey: JSONConstants.JsonRPC)
        let jsonData: NSData
        do {
            jsonData = try JSONSerialization.data(withJSONObject: json, options: JSONSerialization.WritingOptions()) as NSData
            let jsonString = NSString(data: jsonData as Data, encoding: String.Encoding.utf8.rawValue)! as String
            print("Sending = \(jsonString)")
            socket.write(string: jsonString)
        } catch _ {
            print ("JSON Failure")
        }
    }
    
    func addIceCandidate(iceCandidateParams: [String: String]) {
        iceCandidatesParams!.append(iceCandidateParams)
    }
    
    func embedView(_ view: UIView, into containerView: UIView) {
        containerView.addSubview(view)
        containerView.backgroundColor = UIColor.white.withAlphaComponent(0.8)
		

        view.centerXAnchor.constraint(equalTo: containerView.centerXAnchor).isActive = true
        view.centerYAnchor.constraint(equalTo: containerView.centerYAnchor).isActive = true
    }
    
}
