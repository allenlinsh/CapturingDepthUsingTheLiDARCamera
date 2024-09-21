/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An object that connects the camera controller and the views.
*/

import Foundation
import SwiftUI
import Combine
import simd
import AVFoundation
import SceneKit

class CameraManager: ObservableObject, CaptureDataReceiver {

    var capturedData: CameraCapturedData
    @Published var isFilteringDepth: Bool {
        didSet {
            controller.isFilteringEnabled = isFilteringDepth
        }
    }
    @Published var orientation = UIDevice.current.orientation
    @Published var waitingForCapture = false
    @Published var processingCapturedResult = false
    @Published var dataAvailable = false
    
    let controller: CameraController
    var cancellables = Set<AnyCancellable>()
    var session: AVCaptureSession { controller.captureSession }
    
    init() {
        // Create an object to store the captured data for the views to present.
        capturedData = CameraCapturedData()
        controller = CameraController()
        controller.isFilteringEnabled = true
        isFilteringDepth = controller.isFilteringEnabled
        
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification).sink { _ in
            self.orientation = UIDevice.current.orientation
        }.store(in: &cancellables)
        controller.delegate = self
        
        // Start the stream on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            self.controller.startStream()
        }
    }
    
    func startPhotoCapture() {
        controller.capturePhoto()
        waitingForCapture = true
    }
    
    func resumeStream() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.controller.startStream()
            DispatchQueue.main.async {
                self.processingCapturedResult = false
                self.waitingForCapture = false
            }
        }
    }
    
    func onNewPhotoData(capturedData: CameraCapturedData) {
        // Because the views hold a reference to `capturedData`, the app updates each texture separately.
        self.capturedData.depth = capturedData.depth
        self.capturedData.colorY = capturedData.colorY
        self.capturedData.colorCbCr = capturedData.colorCbCr
        self.capturedData.cameraIntrinsics = capturedData.cameraIntrinsics
        self.capturedData.cameraReferenceDimensions = capturedData.cameraReferenceDimensions
        waitingForCapture = false
        processingCapturedResult = true
    }
    
    func onNewData(capturedData: CameraCapturedData) {
        DispatchQueue.main.async {
            if !self.processingCapturedResult {
                if self.isRecording {
                    self.recordedFrames.append(capturedData)
                }
                // Because the views hold a reference to `capturedData`, the app updates each texture separately.
                self.capturedData.depth = capturedData.depth
                self.capturedData.colorY = capturedData.colorY
                self.capturedData.colorCbCr = capturedData.colorCbCr
                self.capturedData.cameraIntrinsics = capturedData.cameraIntrinsics
                self.capturedData.cameraReferenceDimensions = capturedData.cameraReferenceDimensions
                if self.dataAvailable == false {
                    self.dataAvailable = true
                }
            }
        }
    }
    
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    
    @Published var cameraError: String?

    func switchCamera() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.controller.switchCamera()
                DispatchQueue.main.async {
                    self.cameraError = nil
                }
            } catch CameraController.ConfigurationError.lidarDeviceUnavailable {
                print("Error switching camera: LiDAR or TrueDepth camera unavailable")
                DispatchQueue.main.async {
                    self.cameraError = "This device doesn't support depth capture on the selected camera."
                }
            } catch {
                print("Error switching camera: \(error)")
                DispatchQueue.main.async {
                    self.cameraError = "Unable to switch camera. An unexpected error occurred."
                }
            }
        }
    }

    func onCameraPositionChanged(position: AVCaptureDevice.Position) {
        DispatchQueue.main.async {
            self.currentCameraPosition = position
        }
    }
    
    @Published var isRecording = false
    @Published var hasRecordedFrames = false
    private var recordedFrames: [CameraCapturedData] = []

    func startRecording() {
        isRecording = true
        recordedFrames.removeAll()
        hasRecordedFrames = false
    }

    func stopRecording() {
        isRecording = false
        hasRecordedFrames = !recordedFrames.isEmpty
    }

    func exportFaceModel() {
        guard !recordedFrames.isEmpty else {
            print("No recorded frames to export")
            return
        }

        // Process recorded frames and generate face model
        let faceModel = generateFaceModel(from: recordedFrames)

        // Export as .obj and .mtl files
        exportOBJ(faceModel)
        exportMTL(faceModel)
    }

    private func generateFaceModel(from frames: [CameraCapturedData]) -> SCNNode {
        // Implement face model generation logic here
        // This is a placeholder and needs to be implemented based on your specific requirements
        let geometry = SCNGeometry()
        return SCNNode(geometry: geometry)
    }

    private func exportOBJ(_ model: SCNNode) {
        let objData = generateOBJData(from: model)
        saveToFile(data: objData, fileName: "face_model.obj")
        print("Exported OBJ file")
    }

    private func exportMTL(_ model: SCNNode) {
        let mtlData = generateMTLData(from: model)
        saveToFile(data: mtlData, fileName: "face_model.mtl")
        print("Exported MTL file")
    }

    private func generateOBJData(from model: SCNNode) -> Data {
        var objString = "# Exported OBJ file\n"
        
        // Vertex data
        var vertexOffset = 0
        model.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            guard let vertices = geometry.sources(for: .vertex).first?.data else { return }
            let vertexCount = vertices.count / 3
            
            for i in 0..<vertexCount {
                let x = vertices[i * 3]
                let y = vertices[i * 3 + 1]
                let z = vertices[i * 3 + 2]
                objString += "v \(x) \(y) \(z)\n"
            }
            
            // Face data
            if let elements = geometry.elements.first {
                let indexData = elements.data
                let indexCount = indexData.count / elements.bytesPerIndex
                
                for i in stride(from: 0, to: indexCount, by: 3) {
                    let i1 = Int(indexData[i]) + vertexOffset
                    let i2 = Int(indexData[i + 1]) + vertexOffset
                    let i3 = Int(indexData[i + 2]) + vertexOffset
                    objString += "f \(i1 + 1) \(i2 + 1) \(i3 + 1)\n"
                }
            }
            vertexOffset += vertexCount
        }
        
        return objString.data(using: .utf8) ?? Data()
    }

    private func generateMTLData(from model: SCNNode) -> Data {
        var mtlString = "# Exported MTL file\n"
        
        // Iterate through all nodes in the model
        model.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry, let material = geometry.firstMaterial else { return }
            
            // Generate a unique material name
            let materialName = "material_\(UUID().uuidString)"
            mtlString += "newmtl \(materialName)\n"
            
            // Export diffuse color
            if let diffuse = material.diffuse.contents as? UIColor {
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                diffuse.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                mtlString += String(format: "Kd %.6f %.6f %.6f\n", red, green, blue)
            }
            
            // Export ambient color
            if let ambient = material.ambient.contents as? UIColor {
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                ambient.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                mtlString += String(format: "Ka %.6f %.6f %.6f\n", red, green, blue)
            }
            
            // Export specular color
            if let specular = material.specular.contents as? UIColor {
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                specular.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                mtlString += String(format: "Ks %.6f %.6f %.6f\n", red, green, blue)
            }
            
            // Export shininess
            mtlString += String(format: "Ns %.1f\n", material.shininess)
            
            // Export transparency
            mtlString += String(format: "d %.6f\n", material.transparency)
            
            // Export illumination model (2 is the most common for colored materials with highlights)
            mtlString += "illum 2\n\n"
        }
        
        return mtlString.data(using: .utf8) ?? Data()
    }

    private func saveToFile(data: Data, fileName: String) {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Unable to access documents directory")
            return
        }
        
        let lidarCaptureFolder = documentsDirectory.appendingPathComponent("LiDARCapture")
        
        do {
            // Create the LiDARCapture folder if it doesn't exist
            if !FileManager.default.fileExists(atPath: lidarCaptureFolder.path) {
                try FileManager.default.createDirectory(at: lidarCaptureFolder, withIntermediateDirectories: true, attributes: nil)
            }
            
            let fileURL = lidarCaptureFolder.appendingPathComponent(fileName)
            
            try data.write(to: fileURL)
            print("File saved successfully at: \(fileURL.path)")
        } catch {
            print("Error saving file: \(error.localizedDescription)")
        }
    }
}

class CameraCapturedData {
    
    var depth: MTLTexture?
    var colorY: MTLTexture?
    var colorCbCr: MTLTexture?
    var cameraIntrinsics: matrix_float3x3
    var cameraReferenceDimensions: CGSize

    init(depth: MTLTexture? = nil,
         colorY: MTLTexture? = nil,
         colorCbCr: MTLTexture? = nil,
         cameraIntrinsics: matrix_float3x3 = matrix_float3x3(),
         cameraReferenceDimensions: CGSize = .zero) {
        
        self.depth = depth
        self.colorY = colorY
        self.colorCbCr = colorCbCr
        self.cameraIntrinsics = cameraIntrinsics
        self.cameraReferenceDimensions = cameraReferenceDimensions
    }
}
