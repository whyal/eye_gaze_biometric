//
//  EyeTrackingManager.swift
//  Runner
//
//  Created by Tan Yong Lun on 6/1/26.
//
import ARKit
import Flutter
import simd
import UIKit

class EyeTrackingManager: NSObject, ARSessionDelegate {

    private let session = ARSession()
    private var channel: FlutterMethodChannel?

    func attachChannel(_ channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let config = ARFaceTrackingConfiguration()
        config.isWorldTrackingEnabled = true
        session.delegate = self
        session.run(config)
    }

    func stop() {
        session.pause()
    }

    // Called whenever ARKit updates the face
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.first as? ARFaceAnchor else { return }

        let gaze = computeGaze(face, frame: session.currentFrame)
        channel?.invokeMethod("gaze", arguments: [
            "x": gaze.x,
            "y": gaze.y
        ])
    }

    // Compute normalized screen coordinates from ARKit eye transforms
    private func computeGaze(_ face: ARFaceAnchor, frame: ARFrame?) -> CGPoint {
        // Preferred approach: use ARKit's lookAtPoint and project to screen.
        if let frame = frame {
            let lookAtLocal = face.lookAtPoint
            let lookAtWorld4 = face.transform * simd_float4(lookAtLocal.x, lookAtLocal.y, lookAtLocal.z, 1)
            let lookAtWorld = SIMD3<Float>(lookAtWorld4.x, lookAtWorld4.y, lookAtWorld4.z)

            let viewportSize = UIScreen.main.bounds.size
            let projected = frame.camera.projectPoint(
                lookAtWorld,
                orientation: .portrait,
                viewportSize: viewportSize
            )

            let nx = projected.x / viewportSize.width
            let ny = projected.y / viewportSize.height
            let x = CGFloat(min(max(nx, 0), 1))
            let y = CGFloat(min(max(ny, 0), 1))
            return CGPoint(x: x, y: y)
        }

        // Fallback: angular mapping (less accurate).

        let leftEye = face.leftEyeTransform
        let rightEye = face.rightEyeTransform

        let leftDir = -SIMD3<Float>(leftEye.columns.2.x, leftEye.columns.2.y, leftEye.columns.2.z)
        let rightDir = -SIMD3<Float>(rightEye.columns.2.x, rightEye.columns.2.y, rightEye.columns.2.z)

        let direction = simd_normalize(leftDir + rightDir)
        // Eye-only mode: ignore head translation by using face-origin.
        let origin = SIMD3<Float>(0, 0, 0)

        // Eye-only mapping: use angular direction (yaw/pitch) instead of head translation.
        if abs(direction.z) < 1e-5 {
            return CGPoint(x: 0.5, y: 0.5)
        }
        let yaw = atan2(direction.x, -direction.z)
        let pitch = atan2(direction.y, -direction.z)

        // Tune these to expand/reduce eye-only range.
        let maxYaw: Float = 1.0
        let maxPitch: Float = 1.0

        let nx = (yaw / maxYaw + 1) * 0.5
        let ny = 1 - (pitch / maxPitch + 1) * 0.5

        let x = CGFloat(min(max(nx, 0), 1))
        let y = CGFloat(min(max(ny, 0), 1))

        return CGPoint(x: x, y: y)
    }
}
