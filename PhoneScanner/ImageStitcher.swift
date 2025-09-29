import Foundation
import CoreImage
import simd
import Accelerate

struct StitchingResult {
    var stitchedPointCloud: [Point3D]
    var confidence: Float
    var transformations: [simd_float4x4]
}

class ImageStitcher {
    private let ciContext = CIContext()
    private var keyFrames: [KeyFrame] = []
    private let featureDetector = FeatureDetector()

    struct KeyFrame {
        let pointCloud: PointCloud
        let features: [FeaturePoint]
        let descriptors: [FeatureDescriptor]
    }

    func stitchImages(_ pointClouds: [PointCloud]) -> StitchingResult {
        keyFrames.removeAll()

        for pointCloud in pointClouds {
            let colorImage = createColorImage(from: pointCloud)
            let features = featureDetector.detectFeatures(in: colorImage)
            let descriptors = featureDetector.computeDescriptors(for: features, in: colorImage)

            let keyFrame = KeyFrame(
                pointCloud: pointCloud,
                features: features,
                descriptors: descriptors
            )
            keyFrames.append(keyFrame)
        }

        let transformations = computeGlobalTransformations()
        let stitchedCloud = mergePointCloudsWithTransformations(transformations)
        let confidence = computeStitchingConfidence(transformations)

        return StitchingResult(
            stitchedPointCloud: stitchedCloud,
            confidence: confidence,
            transformations: transformations
        )
    }

    private func createColorImage(from pointCloud: PointCloud) -> CIImage {
        let width = 640
        let height = 480
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        for point in pointCloud.points {
            let x = Int(point.position.x * 100) % width
            let y = Int(point.position.y * 100) % height

            if x >= 0 && x < width && y >= 0 && y < height {
                let index = (y * width + x) * 4
                if index + 3 < pixelData.count {
                    pixelData[index] = UInt8(point.color.x * 255)
                    pixelData[index + 1] = UInt8(point.color.y * 255)
                    pixelData[index + 2] = UInt8(point.color.z * 255)
                    pixelData[index + 3] = 255
                }
            }
        }

        let data = Data(pixelData)
        let ciImage = CIImage(
            bitmapData: data,
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        return ciImage
    }

    private func computeGlobalTransformations() -> [simd_float4x4] {
        var transformations = [simd_float4x4](repeating: matrix_identity_float4x4, count: keyFrames.count)

        if keyFrames.isEmpty {
            return transformations
        }

        transformations[0] = matrix_identity_float4x4

        for i in 1..<keyFrames.count {
            let matches = findFeatureMatches(
                frame1: keyFrames[i-1],
                frame2: keyFrames[i]
            )

            if matches.count >= 8 {
                let relativeTransform = estimateTransformation(from: matches)
                transformations[i] = transformations[i-1] * relativeTransform
            } else {
                transformations[i] = transformations[i-1]
            }
        }

        return optimizeTransformations(transformations)
    }

    private func findFeatureMatches(frame1: KeyFrame, frame2: KeyFrame) -> [FeatureMatch] {
        var matches: [FeatureMatch] = []
        let threshold: Float = 0.8

        for (i, desc1) in frame1.descriptors.enumerated() {
            var bestMatch: (index: Int, distance: Float) = (-1, Float.greatestFiniteMagnitude)
            var secondBestDistance: Float = Float.greatestFiniteMagnitude

            for (j, desc2) in frame2.descriptors.enumerated() {
                let distance = computeDescriptorDistance(desc1, desc2)

                if distance < bestMatch.distance {
                    secondBestDistance = bestMatch.distance
                    bestMatch = (j, distance)
                } else if distance < secondBestDistance {
                    secondBestDistance = distance
                }
            }

            if bestMatch.distance < threshold * secondBestDistance {
                let match = FeatureMatch(
                    point1: frame1.features[i],
                    point2: frame2.features[bestMatch.index],
                    distance: bestMatch.distance
                )
                matches.append(match)
            }
        }

        return matches
    }

    private func computeDescriptorDistance(_ desc1: FeatureDescriptor, _ desc2: FeatureDescriptor) -> Float {
        let diff = desc1.data - desc2.data
        return simd_length(diff)
    }

    private func estimateTransformation(from matches: [FeatureMatch]) -> simd_float4x4 {
        guard matches.count >= 8 else { return matrix_identity_float4x4 }

        let ransacIterations = 1000
        let inlierThreshold: Float = 0.01
        var bestTransform = matrix_identity_float4x4
        var maxInliers = 0

        for _ in 0..<ransacIterations {
            let sampleMatches = Array(matches.shuffled().prefix(8))

            let transform = solvePnP(matches: sampleMatches)

            let inliers = countInliers(matches: matches, transform: transform, threshold: inlierThreshold)

            if inliers > maxInliers {
                maxInliers = inliers
                bestTransform = transform
            }
        }

        return bestTransform
    }

    private func solvePnP(matches: [FeatureMatch]) -> simd_float4x4 {
        guard matches.count >= 8 else { return matrix_identity_float4x4 }

        var A = [Float]()
        var b = [Float]()

        for match in matches {
            let p1 = match.point1.position
            let p2 = match.point2.position

            A.append(contentsOf: [p1.x, p1.y, p1.z, 1, 0, 0, 0, 0, 0, 0, 0, 0])
            A.append(contentsOf: [0, 0, 0, 0, p1.x, p1.y, p1.z, 1, 0, 0, 0, 0])
            A.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, p1.x, p1.y, p1.z, 1])

            b.append(contentsOf: [p2.x, p2.y, p2.z])
        }

        let solution = solveLeastSquares(A: A, b: b, rows: matches.count * 3, cols: 12)

        return simd_float4x4(
            simd_float4(solution[0], solution[1], solution[2], solution[3]),
            simd_float4(solution[4], solution[5], solution[6], solution[7]),
            simd_float4(solution[8], solution[9], solution[10], solution[11]),
            simd_float4(0, 0, 0, 1)
        )
    }

    private func solveLeastSquares(A: [Float], b: [Float], rows: Int, cols: Int) -> [Float] {
        var x = [Float](repeating: 0, count: cols)

        var mutableA = A
        var mutableB = b

        var info: __LAPACK_int = 0
        var m = __LAPACK_int(rows)
        var n = __LAPACK_int(cols)
        var nrhs = __LAPACK_int(1)
        var lda = m
        var ldb = max(m, n)

        sgels_(&("N".utf8.first!), &m, &n, &nrhs, &mutableA, &lda, &mutableB, &ldb, nil, nil, &info)

        if info == 0 && mutableB.count >= cols {
            x = Array(mutableB.prefix(cols))
        }

        return x
    }

    private func countInliers(matches: [FeatureMatch], transform: simd_float4x4, threshold: Float) -> Int {
        var inliers = 0

        for match in matches {
            let p1_4d = simd_float4(match.point1.position, 1.0)
            let transformed = transform * p1_4d
            let transformedPoint = simd_float3(transformed.x, transformed.y, transformed.z)

            let distance = simd_distance(transformedPoint, match.point2.position)
            if distance < threshold {
                inliers += 1
            }
        }

        return inliers
    }

    private func optimizeTransformations(_ transformations: [simd_float4x4]) -> [simd_float4x4] {
        var optimized = transformations

        for iteration in 0..<10 {
            var totalError: Float = 0

            for i in 1..<optimized.count {
                let matches = findFeatureMatches(frame1: keyFrames[i-1], frame2: keyFrames[i])

                if !matches.isEmpty {
                    let relativeTransform = estimateTransformation(from: matches)
                    let expectedTransform = optimized[i-1] * relativeTransform

                    let error = computeTransformationError(optimized[i], expectedTransform)
                    totalError += error

                    let alpha: Float = 0.1
                    optimized[i] = interpolateTransformations(optimized[i], expectedTransform, alpha: alpha)
                }
            }

            if totalError < 0.001 {
                break
            }
        }

        return optimized
    }

    private func computeTransformationError(_ t1: simd_float4x4, _ t2: simd_float4x4) -> Float {
        let diff = t1 - t2
        var sum: Float = 0
        for i in 0..<4 {
            for j in 0..<4 {
                sum += diff[i][j] * diff[i][j]
            }
        }
        return sqrt(sum)
    }

    private func interpolateTransformations(_ t1: simd_float4x4, _ t2: simd_float4x4, alpha: Float) -> simd_float4x4 {
        let beta = 1.0 - alpha
        return simd_float4x4(
            beta * t1.columns.0 + alpha * t2.columns.0,
            beta * t1.columns.1 + alpha * t2.columns.1,
            beta * t1.columns.2 + alpha * t2.columns.2,
            beta * t1.columns.3 + alpha * t2.columns.3
        )
    }

    private func mergePointCloudsWithTransformations(_ transformations: [simd_float4x4]) -> [Point3D] {
        var mergedPoints: [Point3D] = []

        for (i, keyFrame) in keyFrames.enumerated() {
            let transform = transformations[i]

            for point in keyFrame.pointCloud.points {
                let transformedPosition = transform * simd_float4(point.position, 1.0)
                let newPoint = Point3D(
                    position: simd_float3(transformedPosition.x, transformedPosition.y, transformedPosition.z),
                    color: point.color,
                    normal: point.normal,
                    timestamp: point.timestamp
                )
                mergedPoints.append(newPoint)
            }
        }

        return removeDuplicatePoints(mergedPoints)
    }

    private func removeDuplicatePoints(_ points: [Point3D]) -> [Point3D] {
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

    private func computeStitchingConfidence(_ transformations: [simd_float4x4]) -> Float {
        var totalConfidence: Float = 0
        var validTransforms = 0

        for i in 1..<transformations.count {
            let matches = findFeatureMatches(frame1: keyFrames[i-1], frame2: keyFrames[i])
            if matches.count >= 8 {
                let inliers = countInliers(
                    matches: matches,
                    transform: transformations[i],
                    threshold: 0.01
                )
                let confidence = Float(inliers) / Float(matches.count)
                totalConfidence += confidence
                validTransforms += 1
            }
        }

        return validTransforms > 0 ? totalConfidence / Float(validTransforms) : 0.0
    }
}

class FeatureDetector {
    func detectFeatures(in image: CIImage) -> [FeaturePoint] {
        var features: [FeaturePoint] = []

        let detector = CIDetector(ofType: CIDetectorTypeText, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])

        let harrisFilter = CIFilter(name: "CIColorControls")!
        harrisFilter.setValue(image, forKey: kCIInputImageKey)

        guard let processedImage = harrisFilter.outputImage else { return features }

        let width = Int(processedImage.extent.width)
        let height = Int(processedImage.extent.height)

        for y in stride(from: 0, to: height, by: 20) {
            for x in stride(from: 0, to: width, by: 20) {
                let position = simd_float3(Float(x), Float(y), 0)
                let feature = FeaturePoint(position: position, strength: 1.0)
                features.append(feature)
            }
        }

        return features
    }

    func computeDescriptors(for features: [FeaturePoint], in image: CIImage) -> [FeatureDescriptor] {
        return features.map { feature in
            let descriptor = simd_float16(
                feature.position.x / 100.0,
                feature.position.y / 100.0,
                feature.strength,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            )
            return FeatureDescriptor(data: descriptor)
        }
    }
}

struct FeaturePoint {
    let position: simd_float3
    let strength: Float
}

struct FeatureDescriptor {
    let data: simd_float16
}

struct FeatureMatch {
    let point1: FeaturePoint
    let point2: FeaturePoint
    let distance: Float
}