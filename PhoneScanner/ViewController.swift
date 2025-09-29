import UIKit
import ARKit
import MetalKit
import SceneKit

class ViewController: UIViewController {

    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var previewView: MetalKitView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var resetButton: UIButton!
    @IBOutlet weak var saveButton: UIButton!
    @IBOutlet weak var exportButton: UIButton!

    private var depthCapture: DepthDataCapture!
    private var pointCloudProcessor: PointCloudProcessor!
    private var imageStitcher: ImageStitcher!
    private var renderer3D: Renderer3D!
    private var isCapturing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCapture()
        setupARSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let configuration = ARFaceTrackingConfiguration()
        sceneView.session.run(configuration)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    private func setupUI() {
        captureButton.setTitle("开始扫描", for: .normal)
        captureButton.backgroundColor = .systemBlue
        captureButton.layer.cornerRadius = 25
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)

        resetButton.addTarget(self, action: #selector(resetButtonTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveButtonTapped), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(exportButtonTapped), for: .touchUpInside)

        statusLabel.text = "准备就绪"
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusLabel.textColor = .white
        statusLabel.layer.cornerRadius = 8

        setupGestureRecognizers()
    }

    private func setupCapture() {
        depthCapture = DepthDataCapture()
        pointCloudProcessor = PointCloudProcessor()
        imageStitcher = ImageStitcher()
        renderer3D = Renderer3D()

        depthCapture.delegate = self
        previewView.device = MTLCreateSystemDefaultDevice()
        previewView.delegate = renderer3D
    }

    private func setupARSession() {
        sceneView.delegate = self
        sceneView.showsStatistics = true
    }

    @objc private func captureButtonTapped() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }

    private func startCapture() {
        isCapturing = true
        captureButton.setTitle("停止扫描", for: .normal)
        captureButton.backgroundColor = .systemRed
        statusLabel.text = "正在扫描..."

        depthCapture.startCapture()
    }

    private func stopCapture() {
        isCapturing = false
        captureButton.setTitle("开始扫描", for: .normal)
        captureButton.backgroundColor = .systemBlue
        statusLabel.text = "处理数据中..."

        depthCapture.stopCapture()
        processAndStitchData()
    }

    private func processAndStitchData() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let processedData = self.pointCloudProcessor.processData()
            let stitchedResult = self.imageStitcher.stitchImages(processedData)

            DispatchQueue.main.async {
                self.statusLabel.text = "扫描完成"
                self.renderer3D.displayResult(stitchedResult)
            }
        }
    }

    private func setupGestureRecognizers() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        previewView.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        previewView.addGestureRecognizer(pinchGesture)
    }

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        renderer3D.handlePanGesture(gesture, in: previewView)
    }

    @objc private func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        renderer3D.handlePinchGesture(gesture)
    }

    @objc private func resetButtonTapped() {
        renderer3D.resetCamera()
        pointCloudProcessor = PointCloudProcessor()
        statusLabel.text = "已重置"
    }

    @objc private func saveButtonTapped() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "scan_\(Date().timeIntervalSince1970).txt"
        let fileURL = documentsPath.appendingPathComponent(fileName)

        pointCloudProcessor.savePointCloud(to: fileURL)
        statusLabel.text = "已保存到 \(fileName)"
    }

    @objc private func exportButtonTapped() {
        let plyContent = renderer3D.exportPointCloud()

        let activityVC = UIActivityViewController(activityItems: [plyContent], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = exportButton
        present(activityVC, animated: true)
    }
}

extension ViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }

        if isCapturing {
            depthCapture.processFrame(faceAnchor: faceAnchor)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }

        if isCapturing {
            depthCapture.processFrame(faceAnchor: faceAnchor)
        }
    }
}

extension ViewController: DepthDataCaptureDelegate {
    func didCaptureDepthData(_ depthData: [Float], colorData: UIImage) {
        pointCloudProcessor.addDepthData(depthData, colorData: colorData)
    }

    func didEncounterError(_ error: Error) {
        DispatchQueue.main.async {
            self.statusLabel.text = "错误: \(error.localizedDescription)"
        }
    }
}