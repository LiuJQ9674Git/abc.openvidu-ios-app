//
//  VideosViewController.swift
//  WebRTCapp
//
//  Created by Sergio Paniego Blanco on 31/05/2018.
//  Copyright © 2018 Sergio Paniego Blanco. All rights reserved.
//

import Foundation
import UIKit
import WebRTC
import Alamofire
//import Result

class VideosViewController: UIViewController {
    var tokenUrl:String="https://192.168.1.103:4443"
    var peersManager: PeersManager?
    var socket: WebSocketListener?
    var localAudioTrack: RTCAudioTrack?
    var localVideoTrack: RTCVideoTrack?
    var videoSource: RTCVideoSource?
    private var videoCapturer: RTCVideoCapturer?
    var url: String = "wss://192.168.1.101:4443"
    var sessionName: String = ""
    var participantName: String = ""
    @IBOutlet weak var localVideoView: UIView!
    @IBOutlet weak var remoteVideoView: UIView!
    @IBOutlet weak var remoteVideoView2: UIView!
    var remoteViews: [UIView]?
    @IBOutlet weak var remoteName1: UILabel!
    @IBOutlet weak var remoteName2: UILabel!
    var remoteNames: [UILabel]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        remoteViews = [UIView]()
        remoteViews?.append(remoteVideoView)
        remoteViews?.append(remoteVideoView2)
        remoteNames = [UILabel]()
        remoteNames?.append(remoteName1)
        remoteNames?.append(remoteName2)
    }
    
    @IBAction func backAction(_ sender: UIButton) {
        print("BUTTTON PRESSED")
        self.socket?.sendJson(method: "leaveRoom", params: [:])
        self.socket?.socket.disconnect()
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("View will Appear")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("Did Appear")
        self.peersManager = PeersManager(view: self.view)
        //start()
        startCheckTrusted()
        //startDefaultToken()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func startCheckTrusted(){
        let parameters:Parameters = [
            "customSessionId": self.sessionName,
        ]
        let headers: HTTPHeaders = [
            "Authorization": "Basic T1BFTlZJRFVBUFA6TVlfU0VDUkVU",
            "Content-Type": "application/json; charset=utf-8"
        ]
        let manager = SessionManager.default
        manager.delegate.sessionDidReceiveChallenge = {
            session,challenge in
            return    (URLSession.AuthChallengeDisposition.useCredential,URLCredential(trust:challenge.protectionSpace.serverTrust!))
        }
     //显示结果：{"id":"SessionA","createdAt":1597010548253} Alamofire 4.0
      manager.request(tokenUrl+"/api/sessions",
                              method: .post, parameters: parameters,
                              encoding:JSONEncoding.default, headers: headers).responseJSON { response in
            var sessionId = ""
            switch(response.result) {
            case .success(_):
                // 将数据转化为字典
                if let dic = try? JSONSerialization.jsonObject(with: response.data!, options:
                    JSONSerialization.ReadingOptions.allowFragments) as! [String: Any] {
                    if dic["id"] != nil {
                        sessionId = dic["id"] as! String
                        self.createToken(sessionId:sessionId)
                    }
            
                }
            break
            case .failure(_):
                print("请求网络失败:\(response.result)")
                self.startDefaultToken()
                break
            }
        }
    }
    func createToken(sessionId: String) {
        let parameters:Parameters = [
                   "session": sessionId,
               ]
        let headers: HTTPHeaders = [
            "Authorization": "Basic T1BFTlZJRFVBUFA6TVlfU0VDUkVU",
            "Content-Type": "application/json; charset=utf-8"
        ]
        let manager = SessionManager.default
        manager.delegate.sessionDidReceiveChallenge = {
            session,challenge in
            return    (URLSession.AuthChallengeDisposition.useCredential,URLCredential(trust:challenge.protectionSpace.serverTrust!))
        }
        manager.request(tokenUrl+"/api/tokens",
                              method: .post, parameters: parameters,
                              encoding:JSONEncoding.default, headers: headers).responseJSON { response in
            var token = ""
            switch(response.result) {
            case .success(_):
                // 将数据转化为字典
                if let dic = try? JSONSerialization.jsonObject(with: response.data!, options:
                    JSONSerialization.ReadingOptions.allowFragments) as! [String: Any] {
    
                    if dic["token"] != nil {
                       
                        token = dic["token"] as! String
                         print("获取Token值:\(token)")
                    } else {
                        token = self.url+"?sessionId=SessionA&token=6m6xfsbfvme5rhek"
                    }
                    //
                    self.createSocket(token: token)
                    
                    DispatchQueue.main.async {
                        self.createLocalVideoView()
                        let mandatoryConstraints = ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"]
                        let sdpConstraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
                        self.peersManager!.createLocalOffer(mediaConstraints: sdpConstraints);
                    }
                }
            break

            case .failure(_):
                print("请求网络失败:\(response.result)")
                self.startDefaultToken()
                break
            }
        }
    }
    
    func startDefaultToken() {
        let tokendefault = self.url+"?sessionId=SessionA&token=6m6xfsbfvme5rhek"
        self.createSocket(token: tokendefault)
        //主线队列中同步执行
        DispatchQueue.main.async {
            self.createLocalVideoView()
            let mandatoryConstraints = ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"]
            let sdpConstraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
            self.peersManager!.createLocalOffer(mediaConstraints: sdpConstraints);
        }
    }
    
    
    func createSocket(token: String) {
        //实例化Socket
        self.socket = WebSocketListener(url: self.url, sessionName: self.sessionName, participantName: self.participantName, peersManager: self.peersManager!,
            token: token, views: remoteViews!, names: remoteNames!)
        self.peersManager!.webSocketListener = self.socket
        self.peersManager!.start()
    }
    
    func createLocalVideoView() {
        let renderer = RTCEAGLVideoView(frame: self.localVideoView.frame)
        startCapureLocalVideo(renderer: renderer)
        
        self.embedView(renderer, into: self.localVideoView)
    }
    
    /**
     本类中调用 viewDidAppear->start->createLocalVideoView
     */
    func startCapureLocalVideo(renderer: RTCVideoRenderer) {
        //创建媒体流发送者
        createMediaSenders()
        
        guard let stream = self.peersManager!.localPeer!.localStreams.first ,
            let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
                return
        }

        guard
            let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == .front }),
            
            // choose highest res
            let format = (RTCCameraVideoCapturer.supportedFormats(for: frontCamera).sorted { (f1, f2) -> Bool in
                let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
                let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
                return width1 < width2
            }).last,
            
            // choose highest fps
            let fps = (format.videoSupportedFrameRateRanges.sorted { return $0.maxFrameRate < $1.maxFrameRate }.last) else {
                return
        }
        //媒体流捕获开始执行
        capturer.startCapture(with: frontCamera,
                                    format: format,
                                    fps: Int(fps.maxFrameRate))
        
        //
        stream.videoTracks.first?.add(renderer)
    }
    
    /**
    本类中调用 viewDidAppear->start->createLocalVideoView->createMediaSenders
    */
    private func createMediaSenders() {
        let streamId = "stream"
        let stream = self.peersManager!.peerConnectionFactory!.mediaStream(withStreamId: streamId)
        
        // Audio
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = self.peersManager!.peerConnectionFactory!.audioSource(with: audioConstrains)
        let audioTrack = self.peersManager!.peerConnectionFactory!.audioTrack(with: audioSource, trackId: "audio0")
        self.localAudioTrack = audioTrack
        self.peersManager!.localAudioTrack = audioTrack
        stream.addAudioTrack(audioTrack)
        
        // Video
        let videoSource = self.peersManager!.peerConnectionFactory!.videoSource()
        self.videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        let videoTrack = self.peersManager!.peerConnectionFactory!.videoTrack(with: videoSource, trackId: "video0")
        self.peersManager!.localVideoTrack = videoTrack
        self.localVideoTrack = videoTrack
        stream.addVideoTrack(videoTrack)
        
        self.peersManager!.localPeer!.add(stream)
        self.peersManager!.localPeer!.delegate = self.peersManager!
    }
    
    func embedView(_ view: UIView, into containerView: UIView) {
        containerView.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        let width = (UIScreen.main.bounds.width / 2)
        let height = (UIScreen.main.bounds.height / 2)
        containerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[view(" + width.description + ")]",
                                                                    options: NSLayoutFormatOptions(),
                                                                    metrics: nil,
                                                                    views: ["view":view]))
        
        containerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[view(" + height.description + ")]",
                                                                    options:NSLayoutFormatOptions(),
                                                                    metrics: nil,
                                                                    views: ["view":view]))
        containerView.layoutIfNeeded()
    }
}
