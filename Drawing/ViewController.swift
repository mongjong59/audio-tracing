//
//  ViewController.swift
//  Drawing
//
//  Created by Tristan Struthers on 7/13/17.
//  Copyright © 2017 Tristan Struthers. All rights reserved.
//

import ARKit
import Foundation
import UIKit
import SceneKit
import GLKit
import AudioKit

class ViewController: UIViewController, ARSCNViewDelegate {
    
    // MARK: - Class Properties
    var rootNode: SCNNode?
    var sessTool: Tool!
    var userIsDrawing = false
    var userIsMovingStructure = false
    
    var recorder: AKNodeRecorder!
    var player: AKPlayer!
    var micMixer: AKMixer!
    var micBooster: AKBooster!
    var mainMixer: AKMixer!
    var tape: AKAudioFile!
    
    var bufferNode: SCNNode?
    var newPointBuffer: [SCNNode]?
    
    var lineNodes: [Dictionary<String, Any>] = []
    var playerNodeIdx: Int = 0
    enum NodeType { case sphere, cylinder }
    
    var oldOrientation: SCNQuaternion?
    var worldUp: SCNVector4 {
        let wUp = rootNode!.worldUp
        let upVec = SCNVector4.init(wUp.x, wUp.y, wUp.z, 1.0)
        return upVec
    }
    
    let openHandIcon = UIImage.init(named: "open_hand_icon")
    let closedHandIcon = UIImage.init(named: "closed_hand_icon")
    
    let mic = AKMicrophone()

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        AKAudioFile.cleanTempDirectory()
        AKSettings.bufferLength = .medium
        
        do {
            try AKSettings.setSession(category: .playAndRecord, with: .allowBluetoothA2DP)
        } catch {
            AKLog("Could not set session category.")
        }
        
        AKSettings.defaultToSpeaker = true
        
        // Patching
        let monoToStereo = AKStereoFieldLimiter(mic, amount: 1)
        micMixer = AKMixer(monoToStereo)
        micBooster = AKBooster(micMixer)

        // Will set the level of microphone monitoring
        micBooster.gain = 0
        recorder = try? AKNodeRecorder(node: micMixer)
        if let file = recorder.audioFile {
            player = AKPlayer(audioFile: file)
        }
        
        mainMixer = AKMixer(player, micBooster)
        
        AudioKit.output = mainMixer
        do {
            try AudioKit.start()
        } catch {
            AKLog("AudioKit did not start!")
        }
    }
    
    // MARK: - Setup and Configuration
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupScene()
        setupTool()
        
        IconImage.isHidden = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    var configuration = ARWorldTrackingConfiguration()
    func setupScene() {
        // Configure and setup the scene view
        configuration.planeDetection = .horizontal
        sceneView.delegate = self
        
        sceneView.antialiasingMode = .multisampling4X
        sceneView.automaticallyUpdatesLighting = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.preferredFramesPerSecond = 60
        sceneView.contentScaleFactor = 1.3
        
        rootNode = sceneView.scene.rootNode

        DispatchQueue.main.async {
            self.IconImage.image = self.openHandIcon
            self.IconImage.isHidden = true
        }

        sceneView.session.run(configuration)
    }
    
    func setupTool() {
        sessTool = Tool()
        sessTool.rootNode = self.rootNode!
        sessTool.toolNode!.scale = SCNVector3Make(0.2, 0.2, 0.2)
        
        let placeHolderNode = SCNNode()
        positionNode(placeHolderNode, atDist: sessTool.distanceFromCamera)
        
        sessTool.toolNode!.position = placeHolderNode.position
        sessTool.toolNode!.rotation = placeHolderNode.rotation
        rootNode?.addChildNode(sessTool.toolNode!)
        
        self.oldOrientation = sessTool.toolNode!.orientation
    }
    
    // MARK: - Outlets
    
    @IBOutlet weak var sceneView: ARSCNView! {
        didSet {
            let holdRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(reactToLongPress(byReactingTo:)))
            holdRecognizer.minimumPressDuration = CFTimeInterval(0.1)
            sceneView.addGestureRecognizer(holdRecognizer)
            
            let leftSwipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(reactToSwipe(byReactingTo:)))
            leftSwipeRecognizer.direction = .left
            sceneView.addGestureRecognizer(leftSwipeRecognizer)
            
            let rightSwipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(reactToSwipe(byReactingTo:)))
            rightSwipeRecognizer.direction = .right
            sceneView.addGestureRecognizer(rightSwipeRecognizer)
            
            let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(reactToPinch(byReactingTo:)))
            sceneView.addGestureRecognizer(pinchRecognizer)
        }
    }
    
    @IBAction func deleteButton(_ sender: UIButton) {
            for selectedNode in self.sessTool.selection {
                // sessTool.updateSelection(withSelectedNode: selectedNode)
                selectedNode.removeFromParentNode()
            }
    }
    
    @IBOutlet weak var IconImage: UIImageView!
    
    // MARK: - Gesture Handlers
    
    @objc func reactToLongPress(byReactingTo holdRecognizer: UILongPressGestureRecognizer) {
        // Check tool type and react accordingly here
        switch sessTool.currentMode {
        case .Pen:
            switch holdRecognizer.state {
            case .began:
                userIsDrawing = true
                
                if AKSettings.headPhonesPlugged {
                    micBooster.gain = 1
                }
                do {
                    try recorder.record()
                } catch { AKLog("Errored recording.") }
            case .ended:
                userIsDrawing = false
                micBooster.gain = 0
                tape = recorder.audioFile!
                player.load(audioFile: tape)
                if let _ = player.audioFile?.duration {
                    recorder.stop()
                    tape.exportAsynchronously(
                        name: "TempTestFile.m4a",
                        baseDir: .documents,
                        exportFormat: .m4a
                    ) {
                        _, exportError in
                            if let error = exportError {
                                AKLog("Export Failed \(error)")
                            } else {
                                AKLog("Export succeeded")
                            }
                    }
                }
                print(lineNodes)
            default: break
            }
        /*
        case .Manipulator:
            switch holdRecognizer.state {
            case .began:
                userIsMovingStructure = true
            case .ended:
                userIsMovingStructure = false
            default: break
            }
        */
        default: break
        }
    }

    @objc func reactToSwipe(byReactingTo swipeRecognizer: UISwipeGestureRecognizer) {
        sessTool.swipe(swipeRecognizer)
        switch sessTool.currentMode {
        case .Pen:
            DispatchQueue.main.async {
                // self.IconImage.image = self.pencilIcon
                self.IconImage.isHidden = true
                self.sessTool.toolNode.isHidden = false
            }
        case .Player:
            DispatchQueue.main.async {
                self.sessTool.toolNode.isHidden = true
                self.IconImage.isHidden = false
                self.IconImage.image = self.openHandIcon
            }
        }
    }
    
    @objc func reactToPinch(byReactingTo pinchRecognizer: UIPinchGestureRecognizer) {
        sessTool.pinch(pinchRecognizer)
    }
    
    // MARK: - Public Class Methods
    
    func updateTool() {
        let placeHolderNode = SCNNode()
        positionNode(placeHolderNode, atDist: sessTool.distanceFromCamera)
        sessTool.toolNode!.position = placeHolderNode.position
        sessTool.toolNode!.orientation = getSlerpOrientation(from: oldOrientation!, to: placeHolderNode.orientation)
        
        oldOrientation = sessTool.toolNode!.orientation
    }

    private func getSlerpOrientation(from q1: SCNQuaternion, to q2: SCNQuaternion) -> SCNQuaternion {
        let gq1 = GLKQuaternion.init(q: (q1.x, q1.y, q1.z, q1.w))
        let gq2 = GLKQuaternion.init(q: (q2.x, q2.y, q2.z, q2.w))
        let slerpedQuat = GLKQuaternionSlerp(gq1, gq2, 0.1)
        return SCNQuaternion.init(slerpedQuat.x, slerpedQuat.y, slerpedQuat.z, slerpedQuat.w)
    }
    
    private func positionNode(_ node: SCNNode, atDist dist: Float) {
        node.transform = (sceneView.pointOfView?.transform)!
        var pointerVector = SCNVector3(
            -1 * node.transform.m31, -1 * node.transform.m32, -1 * node.transform.m33
        )
        pointerVector.scaleBy(dist)
        node.position += pointerVector
    }
    
    var lastPoint: SCNNode?
    
    func updateDraw(){
        if userIsDrawing {
            if bufferNode == nil {
                // user has started to draw a new line segment
                bufferNode = SCNNode()
                rootNode?.addChildNode(bufferNode!)
                newPointBuffer = []
            } else {
                let newNode = (SCNNode(geometry: SCNSphere(radius: sessTool.size)))
                positionNode(newNode, atDist: sessTool.distanceFromCamera)
                
                newPointBuffer!.append(newNode)
                rootNode!.addChildNode(newNode)
                
                var cylinderNode = SCNNode()
                
                if lastPoint == nil {
                    lastPoint = newNode
                } else {
                    cylinderNode = cylinderFrom(
                        vector: lastPoint!.position, toVector: newNode.position
                    )
                    cylinderNode.position = calculateGlobalAverage([lastPoint!, newNode])
                    cylinderNode.look(
                        at: newNode.position,
                        up: rootNode!.worldUp,
                        localFront: rootNode!.worldUp
                    )
                    rootNode!.addChildNode(cylinderNode)
                    newPointBuffer!.append(cylinderNode)
                    lastPoint = newNode
                }
                let nodeInfo = [
                    "node": newNode,
                    "cylinder": cylinderNode,
                    "recordingTime": recorder.recordedDuration,
                ] as [String : Any]
                lineNodes.append(nodeInfo)
            }
        } else {
            if bufferNode != nil {
                // user has finished drawing a new line
                let newParent = SCNNode()
                rootNode!.addChildNode(newParent)
                let bestCentroid = calculateGlobalCentroid(newPointBuffer!)
                newParent.position = bestCentroid
                
                rootNode!.addChildNode(newParent)
                
                DispatchQueue.main.async {
                    while self.newPointBuffer!.count > 0 {
                        let newNode = self.newPointBuffer!.removeFirst()
                        let origTrans = newNode.worldTransform
                        newNode.removeFromParentNode()
                        newParent.addChildNode(newNode)
                        newNode.setWorldTransform(origTrans)
                    }
                    self.bufferNode = nil
                    self.lastPoint = nil
                }
            }
        }
    }
    
    func updateListen() {
        if !userIsDrawing {
            var shouldPlay = false

            if lineNodes.count > 0 && playerNodeIdx < lineNodes.count {
                let nodeInfo = lineNodes[playerNodeIdx]
                let playerNode = nodeInfo["node"] as! SCNNode
                let playerNodePosition = playerNode.presentation.worldPosition
                let playerNodePositionGLK = SCNVector3ToGLKVector3(playerNodePosition)
                let toolPosition = sessTool.toolNode!.presentation.worldPosition
                let toolPositionGLK = SCNVector3ToGLKVector3(toolPosition)
                let distance = GLKVector3Distance(playerNodePositionGLK, toolPositionGLK)
                let recordingTime = nodeInfo["recordingTime"] as! Double
                print(recordingTime)
                let nextPlayerTime = recordingTime + 0.1
                if distance < 0.1 && player.currentTime <= nextPlayerTime {
                    shouldPlay = true
                    print(player.currentTime)
                    playerNode.geometry?.firstMaterial?.diffuse.contents = UIColor.darkGray
                    let playerCylinderNode = nodeInfo["cylinder"] as! SCNNode
                    playerCylinderNode.geometry?.firstMaterial?.diffuse.contents = UIColor.darkGray
                    if player.currentTime - nextPlayerTime < 0.01  {
                        playerNodeIdx += 1
                    }
                }
            }
            
            if playerNodeIdx == lineNodes.count {
                player.stop()
                
            }
            
            if shouldPlay {
                if !player.isPlaying {
                    player.isPaused ? player.resume() : player.play()
                }
            } else {
                if player.isPlaying { player.pause() }
            }
        }
    }
    
    // MARK: - Private Class Methods
    
    private func calculateGlobalAverage(_ nodeList: [SCNNode]) -> SCNVector3 {
        // returns the average position of all nodes in nodeList
        var averagePos = SCNVector3()
        for aNode in nodeList {
            let translVec = aNode.position
            averagePos = averagePos + translVec
        }
        averagePos.scaleBy(1.0/Float(nodeList.count))
        return averagePos
    }
    
    private func calculateGlobalCentroid(_ nodeList: [SCNNode]) -> SCNVector3 {
        // returns the position where each component is the midpoint of the extreme points in the respective axis
        var xExtrema: (xMin: Float, xMax: Float) = (Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var yExtrema: (yMin: Float, yMax: Float) = (Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var zExtrema: (zMin: Float, zMax: Float) = (Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        
        for aNode in nodeList {
            let pos = aNode.position
            xExtrema.xMin = min(xExtrema.xMin, pos.x)
            xExtrema.xMax = max(xExtrema.xMax, pos.x)
            
            yExtrema.yMin = min(yExtrema.yMin, pos.y)
            yExtrema.yMax = max(yExtrema.yMax, pos.y)
            
            zExtrema.zMin = min(zExtrema.zMin, pos.z)
            zExtrema.zMax = max(zExtrema.zMax, pos.z)
        }
        
        let xMid = (xExtrema.xMin + xExtrema.xMax) / 2.0
        let yMid = (yExtrema.yMin + yExtrema.yMax) / 2.0
        let zMid = (zExtrema.zMin + zExtrema.zMax) / 2.0
        
        return SCNVector3.init(xMid, yMid, zMid)
    }
    
    private func cylinderFrom(vector vector1: SCNVector3, toVector vector2: SCNVector3) -> SCNNode {
        
        let distBetweenVecs = SCNVector3.SCNVector3Distance(vectorStart: vector1, vectorEnd: vector2)
        
        let retNode = SCNNode()
        retNode.geometry = SCNCylinder(radius: sessTool.size, height: CGFloat(distBetweenVecs))
        
        return retNode
    }
    
    // MARK: - Delegate Methods
    
    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        updateDraw()
        updateListen()
        updateTool()
    }
}
