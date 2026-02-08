import Foundation
import Vision
import CoreML
import CoreMedia
import VisionCamera
import UIKit
import ImageIO

@objc(BallDetectorPlugin)
public class BallDetectorPlugin: FrameProcessorPlugin {

  private static let confMin: Float = 0.05
  private static let maxMatchDistance: CGFloat = 0.20
  private static let maxGapFrames: Int = 30
  private static let minBoundingBoxArea: CGFloat = 0.001
  private static let maxBoundingBoxArea: CGFloat = 0.3
  private static let minBoundingBoxDimension: CGFloat = 0.01
  private static let iouThreshold: Float = 0.45

  private static let modelInputSize: CGFloat = 960.0

  private var lastBallPosition: CGPoint? = nil
  private var framesSinceLastDetection: Int = 0
  private var detectionHistory: [(center: CGPoint, conf: Float, timestamp: TimeInterval)] = []
  private let maxHistorySize = 5

  private static var vnModel: VNCoreMLModel = {
    do {
      let config = MLModelConfiguration()
      config.computeUnits = .all

      let coreMLModel = try BasketballDetectorV2(configuration: config).model

      return try VNCoreMLModel(for: coreMLModel)
    } catch {
      fatalError("Failed to load Core ML model: \(error)")
    }
  }()

  private func getImageOrientation(from frame: Frame) -> CGImagePropertyOrientation {
    switch frame.orientation {
    case .up:            return .up
    case .upMirrored:    return .upMirrored
    case .down:          return .down
    case .downMirrored:  return .downMirrored
    case .left:          return .left
    case .leftMirrored:  return .leftMirrored
    case .right:         return .right
    case .rightMirrored: return .rightMirrored
    @unknown default:    return .up
    }
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
  }

  private func isValidBoundingBox(_ bb: CGRect) -> Bool {
    let area = bb.width * bb.height
    let minDim = min(bb.width, bb.height)

    guard area >= Self.minBoundingBoxArea else { return false }
    guard area <= Self.maxBoundingBoxArea else { return false }
    guard minDim >= Self.minBoundingBoxDimension else { return false }

    let aspectRatio = bb.width / bb.height
    guard aspectRatio >= 0.5 && aspectRatio <= 2.0 else { return false }

    return true
  }

  private func getSmoothedPosition(_ detections: [(center: CGPoint, conf: Float, bb: CGRect)]) -> (center: CGPoint, conf: Float, bb: CGRect)? {
    guard !detections.isEmpty else { return nil }

    if !detectionHistory.isEmpty {
      let recentCenters = detectionHistory.map { $0.center }
      let avgX = recentCenters.map { $0.x }.reduce(0, +) / CGFloat(recentCenters.count)
      let avgY = recentCenters.map { $0.y }.reduce(0, +) / CGFloat(recentCenters.count)
      let avgPoint = CGPoint(x: avgX, y: avgY)

      let weighted = detections.map { det -> (center: CGPoint, conf: Float, bb: CGRect, weight: Float) in
        let distToAvg = distance(det.center, avgPoint)
        let proximityWeight = Float(1.0 / (1.0 + distToAvg * 5.0))
        let weight = det.conf * 0.7 + proximityWeight * 0.3
        return (det.center, det.conf, det.bb, weight)
      }

      let best = weighted.max(by: { $0.weight < $1.weight })!
      return (best.center, best.conf, best.bb)
    }

    return detections.max(by: { $0.conf < $1.conf })
  }

  private struct RawBox {
    var x: Float
    var y: Float
    var w: Float
    var h: Float
    var conf: Float
  }

  private func decodeYOLO(_ arr: MLMultiArray, confThreshold: Float, iouThreshold: Float) -> [RawBox] {
    let shape = arr.shape.map { $0.intValue }
    guard shape.count == 3, shape[0] == 1, shape[1] == 5 else { return [] }

    let n = shape[2]

    func v(_ c: Int, _ i: Int) -> Float {
      let idx: [NSNumber] = [0, NSNumber(value: c), NSNumber(value: i)]
      return arr[idx].floatValue
    }

    var boxes: [RawBox] = []
    boxes.reserveCapacity(64)

    for i in 0..<n {
      let conf = v(4, i)
      if conf < confThreshold { continue }

      let x = v(0, i)
      let y = v(1, i)
      let w = v(2, i)
      let h = v(3, i)

      if w <= 0 || h <= 0 { continue }

      boxes.append(RawBox(x: x, y: y, w: w, h: h, conf: conf))
    }

    boxes.sort { $0.conf > $1.conf }
    var keep: [RawBox] = []

    for b in boxes {
      var ok = true
      for k in keep {
        if iou(b, k) > iouThreshold {
          ok = false
          break
        }
      }
      if ok { keep.append(b) }
    }

    return keep
  }

  private func iou(_ a: RawBox, _ b: RawBox) -> Float {
    let ax1 = a.x - a.w/2, ay1 = a.y - a.h/2
    let ax2 = a.x + a.w/2, ay2 = a.y + a.h/2
    let bx1 = b.x - b.w/2, by1 = b.y - b.h/2
    let bx2 = b.x + b.w/2, by2 = b.y + b.h/2

    let ix1 = max(ax1, bx1), iy1 = max(ay1, by1)
    let ix2 = min(ax2, bx2), iy2 = min(ay2, by2)

    let iw = max(0, ix2 - ix1)
    let ih = max(0, iy2 - iy1)

    let inter = iw * ih
    let union = (a.w * a.h) + (b.w * b.h) - inter
    return union > 0 ? inter / union : 0
  }

  private func toNormalizedRect(_ b: RawBox) -> CGRect? {
    let isPixelSpace = (abs(b.x) > 2 || abs(b.y) > 2 || abs(b.w) > 2 || abs(b.h) > 2)

    if isPixelSpace {
      let x = CGFloat(b.x)
      let y = CGFloat(b.y)
      let w = CGFloat(b.w)
      let h = CGFloat(b.h)

      let x1 = (x - w / 2) / Self.modelInputSize
      let y1 = (y - h / 2) / Self.modelInputSize
      let wn = w / Self.modelInputSize
      let hn = h / Self.modelInputSize

      let rect = CGRect(x: x1, y: y1, width: wn, height: hn)
      return rect.standardized
    } else {
      let x1 = CGFloat(b.x - b.w / 2)
      let y1 = CGFloat(b.y - b.h / 2)
      let rect = CGRect(x: x1, y: y1, width: CGFloat(b.w), height: CGFloat(b.h))
      return rect.standardized
    }
  }

  public override func callback(_ frame: Frame, withArguments arguments: [AnyHashable: Any]?) -> Any? {
    let sampleBuffer: CMSampleBuffer = frame.buffer

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return [
        "width": frame.width,
        "height": frame.height,
        "timestamp": frame.timestamp,
        "detections": [],
        "tracked": false,
        "message": "Could not get CVPixelBuffer from CMSampleBuffer",
      ]
    }

    var ballDetections: [(center: CGPoint, conf: Float, bb: CGRect)] = []

    let request = VNCoreMLRequest(model: Self.vnModel) { req, err in

      guard let results = req.results else {return}


      guard let featureObs = results.first as? VNCoreMLFeatureValueObservation,
            let arr = featureObs.featureValue.multiArrayValue else {return}

      if arr.shape.count == 3, arr.shape[1].intValue >= 5, arr.shape[2].intValue > 0 {
        let x0 = arr[[0,0,0]].floatValue
        let y0 = arr[[0,1,0]].floatValue
        let w0 = arr[[0,2,0]].floatValue
        let h0 = arr[[0,3,0]].floatValue
        let c0 = arr[[0,4,0]].floatValue
      }

      let decoded = self.decodeYOLO(arr, confThreshold: Self.confMin, iouThreshold: Self.iouThreshold)

      for b in decoded {
        guard var bb = self.toNormalizedRect(b) else { continue }

        bb.origin.x = max(0, min(1, bb.origin.x))
        bb.origin.y = max(0, min(1, bb.origin.y))
        bb.size.width = max(0, min(1 - bb.origin.x, bb.size.width))
        bb.size.height = max(0, min(1 - bb.origin.y, bb.size.height))

        guard self.isValidBoundingBox(bb) else { continue }

        let center = CGPoint(x: bb.midX, y: bb.midY)
        ballDetections.append((center: center, conf: b.conf, bb: bb))
      }
    }

    request.imageCropAndScaleOption = .scaleFill

    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: getImageOrientation(from: frame),
      options: [:]
    )

    do {
      try handler.perform([request])
    } catch {
      return [
        "width": frame.width,
        "height": frame.height,
        "timestamp": frame.timestamp,
        "error": "perform_failed",
        "message": "\(error)",
        "detections": [],
        "tracked": false      ]
    }

    var chosenDetection: (center: CGPoint, conf: Float, bb: CGRect)? = nil
    var isTracked = false

    if !ballDetections.isEmpty {
      if let smoothed = getSmoothedPosition(ballDetections) {
        chosenDetection = smoothed
      } else if let lastPos = lastBallPosition {
        let sorted = ballDetections.sorted { distance($0.center, lastPos) < distance($1.center, lastPos) }
        let closest = sorted[0]

        if distance(closest.center, lastPos) <= Self.maxMatchDistance {
          chosenDetection = closest
        } else {
          chosenDetection = ballDetections.max(by: { $0.conf < $1.conf })
        }
      } else {
        chosenDetection = ballDetections.max(by: { $0.conf < $1.conf })
      }
    }

    if let chosen = chosenDetection {
      lastBallPosition = chosen.center
      framesSinceLastDetection = 0
      isTracked = true

      detectionHistory.append((chosen.center, chosen.conf, frame.timestamp))
      if detectionHistory.count > maxHistorySize {
        detectionHistory.removeFirst()
      }
    } else {
      framesSinceLastDetection += 1
      if framesSinceLastDetection > Self.maxGapFrames {
        lastBallPosition = nil
        detectionHistory.removeAll()
      }
    }

    var detections: [[String: Any]] = []
    if let chosen = chosenDetection {
      detections.append([
        "x": chosen.bb.origin.x,
        "y": chosen.bb.origin.y,
        "w": chosen.bb.size.width,
        "h": chosen.bb.size.height,
        "centerX": chosen.center.x,
        "centerY": chosen.center.y,
        "confidence": chosen.conf
      ])
    }

    var lastKnown: [String: Any]? = nil
    if let lastPos = lastBallPosition, chosenDetection == nil {
      lastKnown = [
        "centerX": lastPos.x,
        "centerY": lastPos.y,
        "framesSinceSeen": framesSinceLastDetection
      ]
    }

    var response: [String: Any] = [
      "width": frame.width,
      "height": frame.height,
      "timestamp": frame.timestamp,
      "detections": detections,
      "tracked": isTracked,
    ]

    if let last = lastKnown {
      response["lastKnown"] = last
    }

    return response
  }
}
