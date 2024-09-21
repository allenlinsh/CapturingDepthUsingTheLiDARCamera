/*
See LICENSE folder for this sample's licensing information.

Abstract:
An object that connects the camera controller and the views.
*/

import Foundation
import SwiftUI
import Combine
import simd
import AVFoundation
import SceneKit
import UniformTypeIdentifiers

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

    @Published var isExporting = false
    @Published var exportError: String?

    func exportFaceModel() {
        guard !recordedFrames.isEmpty else {
            print("No recorded frames to export")
            return
        }

        // Process recorded frames and generate face model
        let faceModel = generateFaceModel(from: recordedFrames)

        // Generate OBJ and MTL data
        let objData = generateOBJData(from: faceModel)
        let mtlData = generateMTLData(from: faceModel)

        // Start the export process
        isExporting = true
        presentSavePicker(objData: objData, mtlData: mtlData)
    }

    private func presentSavePicker(objData: Data, mtlData: Data) {
        DispatchQueue.main.async {
            let exportViewController = ExportViewController(objData: objData, mtlData: mtlData) { result in
                switch result {
                case .success:
                    print("Files exported successfully")
                case .failure(let error):
                    print("Error exporting files: \(error.localizedDescription)")
                    self.exportError = "Failed to export files. Please try again."
                }
                self.isExporting = false
            }
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(exportViewController, animated: true, completion: nil)
            }
        }
    }

    private func generateFaceModel(from frames: [CameraCapturedData]) -> SCNNode {
        // Implement face model generation logic here
        // This is a placeholder and needs to be implemented based on your specific requirements
        let geometry = SCNGeometry()
        return SCNNode(geometry: geometry)
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

struct OBJDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.objFile] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct MTLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mtlFile] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

class ExportViewController: UIViewController {
    private var objData: Data
    private var mtlData: Data
    private var completion: (Result<Void, Error>) -> Void

    init(objData: Data, mtlData: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        self.objData = objData
        self.mtlData = mtlData
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        exportOBJ()
    }

    private func exportOBJ() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("model.obj")
        do {
            try objData.write(to: tempURL)
            let picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
            picker.delegate = self
            picker.allowsMultipleSelection = false
            picker.shouldShowFileExtensions = true
            present(picker, animated: true, completion: nil)
        } catch {
            completion(.failure(error))
            dismiss(animated: true, completion: nil)
        }
    }

    private func exportMTL() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("model.mtl")
        do {
            try mtlData.write(to: tempURL)
            let picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
            picker.delegate = self
            picker.allowsMultipleSelection = false
            picker.shouldShowFileExtensions = true
            present(picker, animated: true, completion: nil)
        } catch {
            completion(.failure(error))
            dismiss(animated: true, completion: nil)
        }
    }
}

extension ExportViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            completion(.failure(NSError(domain: "ExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No file selected"])))
            return
        }

        if url.lastPathComponent.hasSuffix(".obj") {
            exportMTL()
        } else if url.lastPathComponent.hasSuffix(".mtl") {
            completion(.success(()))
            dismiss(animated: true, completion: nil)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(.failure(NSError(domain: "ExportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Export was cancelled"])))
        dismiss(animated: true, completion: nil)
    }
}

extension UTType {
    static var objFile: UTType {
        UTType(filenameExtension: "obj")!
    }
    
    static var mtlFile: UTType {
        UTType(filenameExtension: "mtl")!
    }
}
