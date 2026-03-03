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
    private var frameId: Int64 = 0
    private var lastTimestampSec: TimeInterval?

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
        guard let frame = session.currentFrame else { return }

        frameId += 1
        let timestampSec = frame.timestamp
        let timestampNs = Int64(timestampSec * 1_000_000_000.0)
        let fps: Double
        if let prev = lastTimestampSec {
            let dt = max(timestampSec - prev, 1e-6)
            fps = 1.0 / dt
        } else {
            fps = 0.0
        }
        lastTimestampSec = timestampSec

        let gaze = computeGaze(face, frame: frame)
        let head = computeHeadPose(face)
        let eyeDirs = computeEyeDirectionsInCamera(face: face, frame: frame)
        let tracking = trackingStateInfo(frame.camera.trackingState)
        let blend = face.blendShapes

        channel?.invokeMethod("gaze", arguments: [
            "timestamp_ns": timestampNs,
            "frame_id": frameId,
            "effective_fps": fps,
            "tracking_state": tracking.state,
            "tracking_reason": tracking.reason as Any,
            "head_yaw_rad": head.yaw,
            "head_pitch_rad": head.pitch,
            "head_roll_rad": head.roll,
            "head_tx_m": head.tx,
            "head_ty_m": head.ty,
            "head_tz_m": head.tz,
            "head_distance_m": head.distance,
            "left_eye_dir_cam_x": eyeDirs.left.x,
            "left_eye_dir_cam_y": eyeDirs.left.y,
            "left_eye_dir_cam_z": eyeDirs.left.z,
            "right_eye_dir_cam_x": eyeDirs.right.x,
            "right_eye_dir_cam_y": eyeDirs.right.y,
            "right_eye_dir_cam_z": eyeDirs.right.z,
            "eye_blink_left": blend[.eyeBlinkLeft]?.doubleValue ?? 0.0,
            "eye_blink_right": blend[.eyeBlinkRight]?.doubleValue ?? 0.0,
            "eye_wide_left": blend[.eyeWideLeft]?.doubleValue as Any,
            "eye_wide_right": blend[.eyeWideRight]?.doubleValue as Any,
            "eye_squint_left": blend[.eyeSquintLeft]?.doubleValue as Any,
            "eye_squint_right": blend[.eyeSquintRight]?.doubleValue as Any,
            "gaze_x_norm": gaze.normX,
            "gaze_y_norm": gaze.normY,
            "gaze_x_px": gaze.pxX,
            "gaze_y_px": gaze.pxY
        ])
    }

    // Compute normalized screen coordinates from ARKit eye transforms
    private func computeGaze(_ face: ARFaceAnchor, frame: ARFrame) -> (normX: Double, normY: Double, pxX: Double, pxY: Double) {
        // Preferred approach: use ARKit's lookAtPoint and project to screen.
        let lookAtLocal = face.lookAtPoint
        let lookAtWorld4 = face.transform * simd_float4(lookAtLocal.x, lookAtLocal.y, lookAtLocal.z, 1)
        let lookAtWorld = SIMD3<Float>(lookAtWorld4.x, lookAtWorld4.y, lookAtWorld4.z)

        let viewportSize = UIScreen.main.bounds.size
        let projected = frame.camera.projectPoint(
            lookAtWorld,
            orientation: .portrait,
            viewportSize: viewportSize
        )

        let nx = Double(min(max(projected.x / viewportSize.width, 0), 1))
        let ny = Double(min(max(projected.y / viewportSize.height, 0), 1))
        return (nx, ny, Double(projected.x), Double(projected.y))
    }

    private func trackingStateInfo(_ state: ARCamera.TrackingState) -> (state: String, reason: String?) {
        switch state {
        case .normal:
            return ("normal", nil)
        case .notAvailable:
            return ("limited", "not_available")
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return ("limited", "excessive_motion")
            case .insufficientFeatures:
                return ("limited", "insufficient_features")
            case .initializing:
                return ("limited", "initializing")
            case .relocalizing:
                return ("limited", "relocalizing")
            @unknown default:
                return ("limited", "unknown")
            }
        }
    }

    private func computeHeadPose(_ face: ARFaceAnchor) -> (yaw: Double, pitch: Double, roll: Double, tx: Double, ty: Double, tz: Double, distance: Double) {
        let t = face.transform
        let tx = Double(t.columns.3.x)
        let ty = Double(t.columns.3.y)
        let tz = Double(t.columns.3.z)
        let distance = sqrt(tx * tx + ty * ty + tz * tz)

        let r00 = Double(t.columns.0.x)
        let r10 = Double(t.columns.0.y)
        let r20 = Double(t.columns.0.z)
        let r21 = Double(t.columns.1.z)
        let r22 = Double(t.columns.2.z)

        let yaw = atan2(-r20, sqrt(r00 * r00 + r10 * r10))
        let pitch = atan2(r21, r22)
        let roll = atan2(r10, r00)
        return (yaw, pitch, roll, tx, ty, tz, distance)
    }

    private func computeEyeDirectionsInCamera(face: ARFaceAnchor, frame: ARFrame) -> (left: SIMD3<Double>, right: SIMD3<Double>) {
        let leftEyeWorld = face.transform * face.leftEyeTransform
        let rightEyeWorld = face.transform * face.rightEyeTransform

        let leftWorldDir = simd_normalize(-SIMD3<Float>(leftEyeWorld.columns.2.x, leftEyeWorld.columns.2.y, leftEyeWorld.columns.2.z))
        let rightWorldDir = simd_normalize(-SIMD3<Float>(rightEyeWorld.columns.2.x, rightEyeWorld.columns.2.y, rightEyeWorld.columns.2.z))

        let camInv = simd_inverse(frame.camera.transform)
        let leftCam4 = camInv * simd_float4(leftWorldDir.x, leftWorldDir.y, leftWorldDir.z, 0)
        let rightCam4 = camInv * simd_float4(rightWorldDir.x, rightWorldDir.y, rightWorldDir.z, 0)

        let leftCam = simd_normalize(SIMD3<Float>(leftCam4.x, leftCam4.y, leftCam4.z))
        let rightCam = simd_normalize(SIMD3<Float>(rightCam4.x, rightCam4.y, rightCam4.z))

        return (
            SIMD3<Double>(Double(leftCam.x), Double(leftCam.y), Double(leftCam.z)),
            SIMD3<Double>(Double(rightCam.x), Double(rightCam.y), Double(rightCam.z))
        )
    }
}
