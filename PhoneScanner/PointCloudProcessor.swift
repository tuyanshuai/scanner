import Foundation
import simd
import Accelerate

struct Point3D {
    var position: simd_float3
    var color: simd_float3
    var normal: simd_float3
    var timestamp: TimeInterval
}

struct PointCloud {
    var points: [Point3D]
    var transform: simd_float4x4
    var timestamp: TimeInterval
}

class PointCloudProcessor {
    private var capturedClouds: [PointCloud] = []
    private var mergedCloud: [Point3D] = []
    private let processingQueue = DispatchQueue(label: "pointcloud.processing", qos: .userInitiated)

    func addDepthData(_ depthData: [Float], colorData: UIImage) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            let pointCloud = self.createPointCloud(from: depthData, colorData: colorData)
            self.capturedClouds.append(pointCloud)

            if self.capturedClouds.count > 30 {
                self.capturedClouds.removeFirst()
            }
        }
    }

    private func createPointCloud(from depthData: [Float], colorData: UIImage) -> PointCloud {
        var points: [Point3D] = []
        let currentTime = Date().timeIntervalSince1970

        let colorPixels = extractColorPixels(from: colorData)

        for i in stride(from: 0, to: depthData.count - 2, by: 3) {
            let x = depthData[i]
            let y = depthData[i + 1]
            let z = depthData[i + 2]

            let position = simd_float3(x / 1000.0, y / 1000.0, z)

            let colorIndex = min(Int(y) * Int(colorData.size.width) + Int(x), colorPixels.count - 1)
            let color = colorIndex >= 0 ? colorPixels[colorIndex] : simd_float3(0.5, 0.5, 0.5)

            let normal = calculateNormal(for: position, in: depthData, index: i)

            let point = Point3D(
                position: position,
                color: color,
                normal: normal,
                timestamp: currentTime
            )
            points.append(point)
        }

        return PointCloud(
            points: points,
            transform: matrix_identity_float4x4,
            timestamp: currentTime
        )
    }

    private func extractColorPixels(from image: UIImage) -> [simd_float3] {
        guard let cgImage = image.cgImage else { return [] }

        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var colors: [simd_float3] = []
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let r = Float(pixelData[i]) / 255.0
            let g = Float(pixelData[i + 1]) / 255.0
            let b = Float(pixelData[i + 2]) / 255.0
            colors.append(simd_float3(r, g, b))
        }

        return colors
    }

    private func calculateNormal(for position: simd_float3, in depthData: [Float], index: Int) -> simd_float3 {
        let width = 640
        let height = 480

        let x = Int(position.x)
        let y = Int(position.y)

        guard x > 0 && x < width - 1 && y > 0 && y < height - 1 else {
            return simd_float3(0, 0, 1)
        }

        let centerIndex = y * width + x
        let rightIndex = y * width + (x + 1)
        let bottomIndex = (y + 1) * width + x

        guard centerIndex * 3 + 2 < depthData.count,
              rightIndex * 3 + 2 < depthData.count,
              bottomIndex * 3 + 2 < depthData.count else {
            return simd_float3(0, 0, 1)
        }

        let center = simd_float3(
            depthData[centerIndex * 3],
            depthData[centerIndex * 3 + 1],
            depthData[centerIndex * 3 + 2]
        )

        let right = simd_float3(
            depthData[rightIndex * 3],
            depthData[rightIndex * 3 + 1],
            depthData[rightIndex * 3 + 2]
        )

        let bottom = simd_float3(
            depthData[bottomIndex * 3],
            depthData[bottomIndex * 3 + 1],
            depthData[bottomIndex * 3 + 2]
        )

        let v1 = right - center
        let v2 = bottom - center
        let normal = normalize(cross(v1, v2))

        return normal
    }

    func processData() -> [PointCloud] {
        return processingQueue.sync {
            performICP()
            return capturedClouds
        }
    }

    private func performICP() {
        guard capturedClouds.count > 1 else { return }

        let referenceCloud = capturedClouds[0]

        for i in 1..<capturedClouds.count {
            let transform = calculateTransform(
                source: capturedClouds[i],
                target: referenceCloud
            )
            capturedClouds[i].transform = transform
        }

        mergePointClouds()
    }

    private func calculateTransform(source: PointCloud, target: PointCloud) -> simd_float4x4 {
        let maxIterations = 20
        let convergenceThreshold: Float = 0.001
        var currentTransform = matrix_identity_float4x4

        for _ in 0..<maxIterations {
            let correspondences = findCorrespondences(
                source: source,
                target: target,
                transform: currentTransform
            )

            guard correspondences.count >= 3 else { break }

            let deltaTransform = computeTransformation(correspondences: correspondences)
            currentTransform = deltaTransform * currentTransform

            let error = computeError(correspondences: correspondences, transform: currentTransform)
            if error < convergenceThreshold {
                break
            }
        }

        return currentTransform
    }

    private func findCorrespondences(
        source: PointCloud,
        target: PointCloud,
        transform: simd_float4x4
    ) -> [(sourcePoint: Point3D, targetPoint: Point3D)] {
        var correspondences: [(sourcePoint: Point3D, targetPoint: Point3D)] = []
        let maxDistance: Float = 0.05

        for sourcePoint in source.points {
            let transformedPosition = transform * simd_float4(sourcePoint.position, 1.0)
            let transformedPoint3D = simd_float3(transformedPosition.x, transformedPosition.y, transformedPosition.z)

            var closestPoint: Point3D?
            var minDistance: Float = Float.greatestFiniteMagnitude

            for targetPoint in target.points {
                let distance = simd_distance(transformedPoint3D, targetPoint.position)
                if distance < minDistance && distance < maxDistance {
                    minDistance = distance
                    closestPoint = targetPoint
                }
            }

            if let closest = closestPoint {
                correspondences.append((sourcePoint: sourcePoint, targetPoint: closest))
            }
        }

        return correspondences
    }

    private func computeTransformation(correspondences: [(sourcePoint: Point3D, targetPoint: Point3D)]) -> simd_float4x4 {
        guard correspondences.count >= 3 else { return matrix_identity_float4x4 }

        var sourcePoints: [simd_float3] = []
        var targetPoints: [simd_float3] = []

        for correspondence in correspondences {
            sourcePoints.append(correspondence.sourcePoint.position)
            targetPoints.append(correspondence.targetPoint.position)
        }

        let sourceCentroid = computeCentroid(points: sourcePoints)
        let targetCentroid = computeCentroid(points: targetPoints)

        var H = matrix_float3x3(0)

        for i in 0..<sourcePoints.count {
            let sourcePointCentered = sourcePoints[i] - sourceCentroid
            let targetPointCentered = targetPoints[i] - targetCentroid

            H += simd_float3x3(
                sourcePointCentered * targetPointCentered.x,
                sourcePointCentered * targetPointCentered.y,
                sourcePointCentered * targetPointCentered.z
            )
        }

        let svd = computeSVD(matrix: H)
        let rotation = svd.V * transpose(svd.U)

        if determinant(rotation) < 0 {
            var V = svd.V
            V.columns.2 = -V.columns.2
            let correctedRotation = V * transpose(svd.U)
            let translation = targetCentroid - correctedRotation * sourceCentroid
            return createTransformMatrix(rotation: correctedRotation, translation: translation)
        } else {
            let translation = targetCentroid - rotation * sourceCentroid
            return createTransformMatrix(rotation: rotation, translation: translation)
        }
    }

    private func computeCentroid(points: [simd_float3]) -> simd_float3 {
        var sum = simd_float3(0, 0, 0)
        for point in points {
            sum += point
        }
        return sum / Float(points.count)
    }

    private func computeSVD(matrix: simd_float3x3) -> (U: simd_float3x3, S: simd_float3, V: simd_float3x3) {
        var A = matrix
        var U = matrix_identity_float3x3
        var V = matrix_identity_float3x3
        var S = simd_float3(1, 1, 1)

        return (U: U, S: S, V: V)
    }

    private func createTransformMatrix(rotation: simd_float3x3, translation: simd_float3) -> simd_float4x4 {
        return simd_float4x4(
            simd_float4(rotation.columns.0, 0),
            simd_float4(rotation.columns.1, 0),
            simd_float4(rotation.columns.2, 0),
            simd_float4(translation, 1)
        )
    }

    private func computeError(correspondences: [(sourcePoint: Point3D, targetPoint: Point3D)], transform: simd_float4x4) -> Float {
        var totalError: Float = 0

        for correspondence in correspondences {
            let transformedPosition = transform * simd_float4(correspondence.sourcePoint.position, 1.0)
            let transformedPoint3D = simd_float3(transformedPosition.x, transformedPosition.y, transformedPosition.z)
            let distance = simd_distance(transformedPoint3D, correspondence.targetPoint.position)
            totalError += distance * distance
        }

        return sqrt(totalError / Float(correspondences.count))
    }

    private func mergePointClouds() {
        mergedCloud.removeAll()

        for pointCloud in capturedClouds {
            for point in pointCloud.points {
                let transformedPosition = pointCloud.transform * simd_float4(point.position, 1.0)
                let transformedPoint = Point3D(
                    position: simd_float3(transformedPosition.x, transformedPosition.y, transformedPosition.z),
                    color: point.color,
                    normal: point.normal,
                    timestamp: point.timestamp
                )
                mergedCloud.append(transformedPoint)
            }
        }

        mergedCloud = removeDuplicatePoints(points: mergedCloud)
    }

    private func removeDuplicatePoints(points: [Point3D]) -> [Point3D] {
        var uniquePoints: [Point3D] = []
        let threshold: Float = 0.001

        for point in points {
            var isDuplicate = false
            for existingPoint in uniquePoints {
                if simd_distance(point.position, existingPoint.position) < threshold {
                    isDuplicate = true
                    break
                }
            }
            if !isDuplicate {
                uniquePoints.append(point)
            }
        }

        return uniquePoints
    }

    func getMergedPointCloud() -> [Point3D] {
        return mergedCloud
    }

    func savePointCloud(to url: URL) {
        let pointCloudData = mergedCloud.map { point in
            "\(point.position.x) \(point.position.y) \(point.position.z) \(point.color.x) \(point.color.y) \(point.color.z)"
        }.joined(separator: "\n")

        do {
            try pointCloudData.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("保存点云数据失败: \(error)")
        }
    }
}