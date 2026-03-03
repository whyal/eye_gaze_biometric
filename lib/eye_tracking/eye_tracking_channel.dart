import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class EyeTrackingSample {
  final int timestampNs;
  final int frameId;
  final double effectiveFps;
  final String trackingState;
  final String? trackingReason;
  final Offset headTranslationM;
  final double headTranslationZM;
  final double headDistanceM;
  final double headYawRad;
  final double headPitchRad;
  final double headRollRad;
  final Offset leftEyeDirCameraXY;
  final double leftEyeDirCameraZ;
  final Offset rightEyeDirCameraXY;
  final double rightEyeDirCameraZ;
  final double eyeBlinkLeft;
  final double eyeBlinkRight;
  final double? eyeWideLeft;
  final double? eyeWideRight;
  final double? eyeSquintLeft;
  final double? eyeSquintRight;
  final Offset gazeNorm;
  final Offset gazePx;

  const EyeTrackingSample({
    required this.timestampNs,
    required this.frameId,
    required this.effectiveFps,
    required this.trackingState,
    required this.trackingReason,
    required this.headTranslationM,
    required this.headTranslationZM,
    required this.headDistanceM,
    required this.headYawRad,
    required this.headPitchRad,
    required this.headRollRad,
    required this.leftEyeDirCameraXY,
    required this.leftEyeDirCameraZ,
    required this.rightEyeDirCameraXY,
    required this.rightEyeDirCameraZ,
    required this.eyeBlinkLeft,
    required this.eyeBlinkRight,
    required this.eyeWideLeft,
    required this.eyeWideRight,
    required this.eyeSquintLeft,
    required this.eyeSquintRight,
    required this.gazeNorm,
    required this.gazePx,
  });

  static EyeTrackingSample? fromMethodArgs(dynamic arguments) {
    if (arguments is! Map) return null;
    final map = Map<String, dynamic>.from(arguments);
    double d(String key, [double fallback = 0.0]) {
      final v = map[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    double? dNullable(String key) {
      final v = map[key];
      if (v is num) return v.toDouble();
      return null;
    }

    String s(String key, [String fallback = 'unknown']) {
      final v = map[key];
      if (v is String) return v;
      return fallback;
    }

    return EyeTrackingSample(
      timestampNs: (map['timestamp_ns'] as num?)?.toInt() ?? 0,
      frameId: (map['frame_id'] as num?)?.toInt() ?? 0,
      effectiveFps: d('effective_fps'),
      trackingState: s('tracking_state'),
      trackingReason: map['tracking_reason'] as String?,
      headTranslationM: Offset(d('head_tx_m'), d('head_ty_m')),
      headTranslationZM: d('head_tz_m'),
      headDistanceM: d('head_distance_m'),
      headYawRad: d('head_yaw_rad'),
      headPitchRad: d('head_pitch_rad'),
      headRollRad: d('head_roll_rad'),
      leftEyeDirCameraXY: Offset(d('left_eye_dir_cam_x'), d('left_eye_dir_cam_y')),
      leftEyeDirCameraZ: d('left_eye_dir_cam_z'),
      rightEyeDirCameraXY: Offset(d('right_eye_dir_cam_x'), d('right_eye_dir_cam_y')),
      rightEyeDirCameraZ: d('right_eye_dir_cam_z'),
      eyeBlinkLeft: d('eye_blink_left'),
      eyeBlinkRight: d('eye_blink_right'),
      eyeWideLeft: dNullable('eye_wide_left'),
      eyeWideRight: dNullable('eye_wide_right'),
      eyeSquintLeft: dNullable('eye_squint_left'),
      eyeSquintRight: dNullable('eye_squint_right'),
      gazeNorm: Offset(d('gaze_x_norm'), d('gaze_y_norm')),
      gazePx: Offset(d('gaze_x_px'), d('gaze_y_px')),
    );
  }
}

class EyeTrackingChannel {
  static const _channel = MethodChannel('eye_tracking');

  static StreamController<Offset> _gazeStream =
      StreamController.broadcast();
  static StreamController<EyeTrackingSample> _sampleStream =
      StreamController.broadcast();
  static final ValueNotifier<int> gazeEventCount = ValueNotifier<int>(0);
  static final ValueNotifier<int?> lastGazeMs =
      ValueNotifier<int?>(null);

  static Stream<Offset> get gazeStream => _gazeStream.stream;
  static Stream<EyeTrackingSample> get sampleStream => _sampleStream.stream;

  static void initialize() {
    if (_gazeStream.isClosed) {
      _gazeStream = StreamController.broadcast();
    }
    if (_sampleStream.isClosed) {
      _sampleStream = StreamController.broadcast();
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'gaze') {
        final sample = EyeTrackingSample.fromMethodArgs(call.arguments);
        if (sample == null) return;
        _sampleStream.add(sample);
        _gazeStream.add(sample.gazeNorm);
        gazeEventCount.value += 1;
        lastGazeMs.value = DateTime.now().millisecondsSinceEpoch;
      }
    });

    _channel.invokeMethod('start');
  }

  static void dispose() {
    _channel.invokeMethod('stop');
  }
}
