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
