import Foundation
import ARKit
import AVFoundation
import CoreImage

protocol DepthDataCaptureDelegate: AnyObject {
    func didCaptureDepthData(_ depthData: [Float], colorData: UIImage)
    func didEncounterError(_ error: Error)
}

class DepthDataCapture: NSObject {
    weak var delegate: DepthDataCaptureDelegate?

    private var captureSession: AVCaptureSession?
    private var depthDataOutput: AVCaptureDepthDataOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "session queue")
    private let dataOutputQueue = DispatchQueue(label: "data output queue", qos: .userInteractive)

    private var isCapturing = false
    private var capturedFrames: [(depthData: [Float], colorData: UIImage)] = []

    override init() {
        super.init()
        setupCaptureSession()
    }

    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .vga640x480

        guard let captureSession = captureSession else { return }

        do {
            guard let frontCamera = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else {
                throw CaptureError.noTrueDepthCamera
            }

            let deviceInput = try AVCaptureDeviceInput(device: frontCamera)

            if captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
            }

            depthDataOutput = AVCaptureDepthDataOutput()
            depthDataOutput?.isFilteringEnabled = true
            depthDataOutput?.setDelegate(self, callbackQueue: dataOutputQueue)

            if captureSession.canAddOutput(depthDataOutput!) {
                captureSession.addOutput(depthDataOutput!)

                let depthConnection = depthDataOutput?.connection(with: .depthData)
                depthConnection?.isEnabled = true
            }

            videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput?.setSampleBufferDelegate(self, queue: dataOutputQueue)

            if captureSession.canAddOutput(videoDataOutput!) {
                captureSession.addOutput(videoDataOutput!)
            }

        } catch {
            delegate?.didEncounterError(error)
        }
    }

    func startCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.isCapturing = true
            self.capturedFrames.removeAll()
            self.captureSession?.startRunning()
        }
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.isCapturing = false
            self.captureSession?.stopRunning()
        }
    }

    func processFrame(faceAnchor: ARFaceAnchor) {
        guard isCapturing else { return }

        let geometry = faceAnchor.geometry
        let vertices = geometry.vertices
        let textureCoordinates = geometry.textureCoordinates

        var depthPoints: [Float] = []

        for i in 0..<vertices.count {
            let vertex = vertices[i]
            depthPoints.append(vertex.x)
            depthPoints.append(vertex.y)
            depthPoints.append(vertex.z)
        }

        if let colorImage = createColorImage(from: textureCoordinates) {
            delegate?.didCaptureDepthData(depthPoints, colorData: colorImage)
        }
    }

    private func createColorImage(from textureCoordinates: [vector_float2]) -> UIImage? {
        let width = 640
        let height = 480
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(data: nil, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }

        context.setFillColor(UIColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for coord in textureCoordinates {
            let x = CGFloat(coord.x) * CGFloat(width)
            let y = CGFloat(coord.y) * CGFloat(height)
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: x-1, y: y-1, width: 2, height: 2))
        }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

extension DepthDataCapture: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        guard isCapturing else { return }

        let depthPixelBuffer = depthData.depthDataMap
        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)

        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer) else { return }
        let depthPointer = baseAddress.assumingMemoryBound(to: Float32.self)

        var depthArray: [Float] = []
        for y in 0..<height {
            for x in 0..<width {
                let depth = depthPointer[y * width + x]
                if depth > 0 && depth < 10.0 {
                    depthArray.append(Float(x))
                    depthArray.append(Float(y))
                    depthArray.append(depth)
                }
            }
        }

        if let colorImage = createColorImageFromDepth(width: width, height: height, depthData: depthPointer) {
            delegate?.didCaptureDepthData(depthArray, colorData: colorImage)
        }
    }

    private func createColorImageFromDepth(width: Int, height: Int, depthData: UnsafePointer<Float32>) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(data: nil, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }

        guard let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt32.self)

        for y in 0..<height {
            for x in 0..<width {
                let depth = depthData[y * width + x]
                let normalizedDepth = min(max(depth / 3.0, 0.0), 1.0)
                let grayValue = UInt8((1.0 - normalizedDepth) * 255)

                let pixel = (UInt32(255) << 24) | (UInt32(grayValue) << 16) | (UInt32(grayValue) << 8) | UInt32(grayValue)
                pixels[y * width + x] = pixel
            }
        }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

extension DepthDataCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isCapturing else { return }
    }
}

enum CaptureError: Error {
    case noTrueDepthCamera
    case sessionConfigurationFailed

    var localizedDescription: String {
        switch self {
        case .noTrueDepthCamera:
            return "设备不支持TrueDepth摄像头"
        case .sessionConfigurationFailed:
            return "摄像头配置失败"
        }
    }
}