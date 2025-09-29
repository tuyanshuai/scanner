import Foundation
import Metal
import MetalKit
import simd

class Renderer3D: NSObject, MTKViewDelegate {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var renderPipelineState: MTLRenderPipelineState!
    private var depthStencilState: MTLDepthStencilState!

    private var vertexBuffer: MTLBuffer?
    private var colorBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    private var pointCloud: [Point3D] = []
    private var camera = Camera()
    private var projectionMatrix = matrix_identity_float4x4

    private struct Uniforms {
        var modelViewProjectionMatrix: simd_float4x4
        var normalMatrix: simd_float3x3
        var pointSize: Float
    }

    override init() {
        super.init()
        setupMetal()
    }

    private func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()

        setupRenderPipeline()
        setupDepthStencil()
        setupBuffers()
    }

    private func setupRenderPipeline() {
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }

    private func setupDepthStencil() {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }

    private func setupBuffers() {
        let maxPoints = 100000
        let vertexSize = MemoryLayout<simd_float3>.size * maxPoints
        let colorSize = MemoryLayout<simd_float3>.size * maxPoints
        let uniformSize = MemoryLayout<Uniforms>.size

        vertexBuffer = device.makeBuffer(length: vertexSize, options: .storageModeShared)
        colorBuffer = device.makeBuffer(length: colorSize, options: .storageModeShared)
        uniformBuffer = device.makeBuffer(length: uniformSize, options: .storageModeShared)
    }

    func displayResult(_ result: StitchingResult) {
        pointCloud = result.stitchedPointCloud
        updateBuffers()
    }

    private func updateBuffers() {
        guard !pointCloud.isEmpty else { return }

        let vertices = pointCloud.map { $0.position }
        let colors = pointCloud.map { $0.color }

        if let vertexPointer = vertexBuffer?.contents().bindMemory(to: simd_float3.self, capacity: vertices.count) {
            for (index, vertex) in vertices.enumerated() {
                vertexPointer[index] = vertex
            }
        }

        if let colorPointer = colorBuffer?.contents().bindMemory(to: simd_float3.self, capacity: colors.count) {
            for (index, color) in colors.enumerated() {
                colorPointer[index] = color
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width / size.height)
        projectionMatrix = createPerspectiveMatrix(fovy: .pi / 3, aspect: aspect, near: 0.1, far: 100.0)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        camera.updateMatrices()
        let modelViewProjectionMatrix = projectionMatrix * camera.viewMatrix

        let uniforms = Uniforms(
            modelViewProjectionMatrix: modelViewProjectionMatrix,
            normalMatrix: simd_float3x3(camera.viewMatrix),
            pointSize: 2.0
        )

        if let uniformPointer = uniformBuffer?.contents().bindMemory(to: Uniforms.self, capacity: 1) {
            uniformPointer[0] = uniforms
        }

        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)

        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 2)

        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCloud.count)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func createPerspectiveMatrix(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1.0 / tan(fovy * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wzScale = -2.0 * far * near / zRange

        let P = simd_float4x4(
            simd_float4(xScale, 0, 0, 0),
            simd_float4(0, yScale, 0, 0),
            simd_float4(0, 0, zScale, -1),
            simd_float4(0, 0, wzScale, 0)
        )
        return P
    }

    func handlePanGesture(_ gesture: UIPanGestureRecognizer, in view: UIView) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        let sensitivity: Float = 0.01
        let deltaX = Float(translation.x) * sensitivity
        let deltaY = Float(translation.y) * sensitivity

        camera.rotate(deltaX: deltaX, deltaY: deltaY)
        gesture.setTranslation(.zero, in: view)
    }

    func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        let scale = Float(gesture.scale)
        camera.zoom(scale: scale)
        gesture.scale = 1.0
    }

    func resetCamera() {
        camera.reset()
    }

    func exportPointCloud() -> String {
        var plyContent = """
        ply
        format ascii 1.0
        element vertex \(pointCloud.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """

        for point in pointCloud {
            let r = UInt8(point.color.x * 255)
            let g = UInt8(point.color.y * 255)
            let b = UInt8(point.color.z * 255)

            plyContent += "\(point.position.x) \(point.position.y) \(point.position.z) \(r) \(g) \(b)\n"
        }

        return plyContent
    }
}

class Camera {
    var position = simd_float3(0, 0, 3)
    var target = simd_float3(0, 0, 0)
    var up = simd_float3(0, 1, 0)

    private var rotationX: Float = 0
    private var rotationY: Float = 0
    private var distance: Float = 3.0

    var viewMatrix: simd_float4x4 = matrix_identity_float4x4

    func updateMatrices() {
        let eye = simd_float3(
            distance * cos(rotationY) * cos(rotationX),
            distance * sin(rotationY),
            distance * cos(rotationY) * sin(rotationX)
        )

        position = target + eye
        viewMatrix = createLookAtMatrix(eye: position, center: target, up: up)
    }

    func rotate(deltaX: Float, deltaY: Float) {
        rotationX += deltaX
        rotationY = max(-Float.pi/2 + 0.1, min(Float.pi/2 - 0.1, rotationY + deltaY))
    }

    func zoom(scale: Float) {
        distance *= 1.0 / scale
        distance = max(0.5, min(10.0, distance))
    }

    func reset() {
        rotationX = 0
        rotationY = 0
        distance = 3.0
        position = simd_float3(0, 0, 3)
        target = simd_float3(0, 0, 0)
        up = simd_float3(0, 1, 0)
    }

    private func createLookAtMatrix(eye: simd_float3, center: simd_float3, up: simd_float3) -> simd_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        return simd_float4x4(
            simd_float4(x.x, y.x, z.x, 0),
            simd_float4(x.y, y.y, z.y, 0),
            simd_float4(x.z, y.z, z.z, 0),
            simd_float4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        )
    }
}

extension Renderer3D {
    func createMetalShaders() -> String {
        return """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float3 position [[attribute(0)]];
            float3 color [[attribute(1)]];
        };

        struct VertexOut {
            float4 position [[position]];
            float3 color;
            float pointSize [[point_size]];
        };

        struct Uniforms {
            float4x4 modelViewProjectionMatrix;
            float3x3 normalMatrix;
            float pointSize;
        };

        vertex VertexOut vertex_main(VertexIn vertexIn [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(2)]]) {
            VertexOut vertexOut;
            vertexOut.position = uniforms.modelViewProjectionMatrix * float4(vertexIn.position, 1.0);
            vertexOut.color = vertexIn.color;
            vertexOut.pointSize = uniforms.pointSize;
            return vertexOut;
        }

        fragment float4 fragment_main(VertexOut fragmentIn [[stage_in]],
                                    float2 pointCoord [[point_coord]]) {
            float distance = length(pointCoord - 0.5);
            if (distance > 0.5) {
                discard_fragment();
            }

            float alpha = 1.0 - smoothstep(0.3, 0.5, distance);
            return float4(fragmentIn.color, alpha);
        }
        """
    }
}