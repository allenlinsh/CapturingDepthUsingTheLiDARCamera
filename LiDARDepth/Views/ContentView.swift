/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The app's main user interface.
*/

import SwiftUI
import MetalKit
import Metal

struct ContentView: View {
    
    @StateObject private var manager = CameraManager()
    
    @State private var maxDepth = Float(5.0)
    @State private var minDepth = Float(0.0)
    @State private var scaleMovement = Float(1.0)
    
    let maxRangeDepth = Float(15)
    let minRangeDepth = Float(0)
    
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Button {
                        manager.processingCapturedResult ? manager.resumeStream() : manager.startPhotoCapture()
                    } label: {
                        Image(systemName: manager.processingCapturedResult ? "play.circle" : "camera.circle")
                            .font(.largeTitle)
                    }
                    
                    Button {
                        manager.switchCamera()
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.largeTitle)
                    }
                    
                    Text(manager.currentCameraPosition == .back ? "LiDAR" : "TrueDepth")
                        .font(.caption)
                        .padding(.horizontal)
                    
                    Text("Depth Filtering")
                    Toggle("Depth Filtering", isOn: $manager.isFilteringDepth).labelsHidden()
                    Spacer()
                }
                Button {
                    if manager.isRecording {
                        manager.stopRecording()
                    } else {
                        manager.startRecording()
                    }
                } label: {
                    Image(systemName: manager.isRecording ? "stop.circle" : "record.circle")
                        .font(.largeTitle)
                }

                Button {
                    manager.exportFaceModel()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.largeTitle)
                }
                .disabled(!manager.hasRecordedFrames)
                
                SliderDepthBoundaryView(val: $maxDepth, label: "Max Depth", minVal: minRangeDepth, maxVal: maxRangeDepth)
                SliderDepthBoundaryView(val: $minDepth, label: "Min Depth", minVal: minRangeDepth, maxVal: maxRangeDepth)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(maximum: 600)), GridItem(.flexible(maximum: 600))]) {
                        
                        if manager.dataAvailable {
                            ZoomOnTap {
                                MetalTextureColorThresholdDepthView(
                                    rotationAngle: rotationAngle,
                                    maxDepth: $maxDepth,
                                    minDepth: $minDepth,
                                    capturedData: manager.capturedData
                                )
                                .aspectRatio(calcAspect(orientation: viewOrientation, texture: manager.capturedData.depth), contentMode: .fit)
                            }
                            ZoomOnTap {
                                MetalTextureColorZapView(
                                    rotationAngle: rotationAngle,
                                    maxDepth: $maxDepth,
                                    minDepth: $minDepth,
                                    capturedData: manager.capturedData
                                )
                                .aspectRatio(calcAspect(orientation: viewOrientation, texture: manager.capturedData.depth), contentMode: .fit)
                            }
                            ZoomOnTap {
                                MetalPointCloudView(
                                    rotationAngle: rotationAngle,
                                    maxDepth: $maxDepth,
                                    minDepth: $minDepth,
                                    scaleMovement: $scaleMovement,
                                    capturedData: manager.capturedData
                                )
                                .aspectRatio(calcAspect(orientation: viewOrientation, texture: manager.capturedData.depth), contentMode: .fit)
                            }
                            ZoomOnTap {
                                DepthOverlay(manager: manager,
                                             maxDepth: $maxDepth,
                                             minDepth: $minDepth
                                )
                                    .aspectRatio(calcAspect(orientation: viewOrientation, texture: manager.capturedData.depth), contentMode: .fit)
                            }
                        }
                    }
                }
                if let error = manager.cameraError {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            if manager.showingSavePrompt {
                savePromptOverlay
            }
        }
        .alert(isPresented: $manager.showingSavePrompt) {
            Alert(
                title: Text("File Saved"),
                message: Text("The 3D model has been saved to:\n\(manager.savedFilePath ?? "Unknown location")"),
                dismissButton: .default(Text("OK")) {
                    manager.showingSavePrompt = false
                }
            )
        }
    }
    
    private var savePromptOverlay: some View {
        VStack {
            Text("Saving 3D Model...")
            ProgressView()
        }
        .padding()
        .background(Color.secondary.colorInvert())
        .cornerRadius(10)
        .shadow(radius: 10)
    }
}

struct SliderDepthBoundaryView: View {
    @Binding var val: Float
    var label: String
    var minVal: Float
    var maxVal: Float
    let stepsCount = Float(200.0)
    var body: some View {
        HStack {
            Text(String(format: " %@: %.2f", label, val))
            Slider(
                value: $val,
                in: minVal...maxVal,
                step: (maxVal - minVal) / stepsCount
            ) {
            } minimumValueLabel: {
                Text(String(minVal))
            } maximumValueLabel: {
                Text(String(maxVal))
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPhone 12 Pro Max")
    }
}
