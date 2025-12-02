import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: GazeTrackerApp()));
}

class GazeTrackerApp extends StatefulWidget {
  const GazeTrackerApp({super.key});

  @override
  State<GazeTrackerApp> createState() => _GazeTrackerAppState();
}

class _GazeTrackerAppState extends State<GazeTrackerApp> {
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableContours: true,
      enableClassification: false,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  bool _isDetecting = false;
  CameraDescription? _frontCamera;

  // Cursor UI State
  Offset _cursorPosition = const Offset(0, 0);

  // --- STABILITY CONFIGURATION ---
  // Increased slightly to provide better smoothing for the drift effect
  final int _windowSize = 8;

  // REMOVED Deadzone for "Drifting" effect.
  // We want continuous updates now, not stepped movements.

  // --- RAW DATA & SMOOTHING BUFFERS ---
  final List<double> _historyX = [];
  final List<double> _historyY = [];
  double _lastStableX = 0.0;
  double _lastStableY = 0.0;

  // --- 9-POINT CALIBRATION STATE ---
  // 0-8: Calibration points. -1: Not calibrating. 9: Finished.
  int _calibrationStep = 0;
  List<Offset> _calibrationPoints = []; // Screen coordinates
  final List<Offset> _recordedEyeVectors = []; // Raw camera vectors

  // Computed Bounds (The "Range of Motion")
  double _eyeMinX = 0;
  double _eyeMaxX = 0;
  double _eyeMinY = 0;
  double _eyeMaxY = 0;

  // To handle mirroring (Left on screen might be Right on camera)
  bool _invertX = false;
  bool _invertY = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setupCalibrationPoints();
  }

  void _setupCalibrationPoints() {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final padding = 40.0;

    // 9 Points Grid: Top-Left -> Bottom-Right
    _calibrationPoints = [
      Offset(padding, padding), // 0: Top-Left
      Offset(w / 2, padding), // 1: Top-Center
      Offset(w - padding, padding), // 2: Top-Right
      Offset(padding, h / 2), // 3: Mid-Left
      Offset(w / 2, h / 2), // 4: Center
      Offset(w - padding, h / 2), // 5: Mid-Right
      Offset(padding, h - padding), // 6: Bot-Left
      Offset(w / 2, h - padding), // 7: Bot-Center
      Offset(w - padding, h - padding), // 8: Bot-Right
    ];
  }

  Future<void> _initializeCamera() async {
    await Permission.camera.request();
    final cameras = await availableCameras();
    _frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      _frontCamera!,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();
    if (!mounted) return;
    _cameraController!.startImageStream(_processCameraImage);
    setState(() {});
  }

  void _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isDetecting = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        final leftEyeLandmark = face.landmarks[FaceLandmarkType.leftEye];
        final rightEyeLandmark = face.landmarks[FaceLandmarkType.rightEye];
        final leftEyeContour = face.contours[FaceContourType.leftEye];
        final rightEyeContour = face.contours[FaceContourType.rightEye];

        if (leftEyeLandmark != null &&
            rightEyeLandmark != null &&
            leftEyeContour != null &&
            rightEyeContour != null) {
          final leftCentroid = _calculateCentroid(leftEyeContour.points);
          final rightCentroid = _calculateCentroid(rightEyeContour.points);

          double leftGazeX =
              leftEyeLandmark.position.x.toDouble() - leftCentroid.dx;
          double leftGazeY =
              leftEyeLandmark.position.y.toDouble() - leftCentroid.dy;
          double rightGazeX =
              rightEyeLandmark.position.x.toDouble() - rightCentroid.dx;
          double rightGazeY =
              rightEyeLandmark.position.y.toDouble() - rightCentroid.dy;

          // Average the two eyes
          double avgGazeX = (leftGazeX + rightGazeX) / 2;
          double avgGazeY = (leftGazeY + rightGazeY) / 2;

          _processGazeStability(avgGazeX, avgGazeY);
        }
      }
    } catch (e) {
      debugPrint("Error detecting face: $e");
    } finally {
      _isDetecting = false;
    }
  }

  void _processGazeStability(double rawX, double rawY) {
    _historyX.add(rawX);
    _historyY.add(rawY);

    if (_historyX.length > _windowSize) {
      _historyX.removeAt(0);
      _historyY.removeAt(0);
    }

    double smoothedX = _historyX.reduce((a, b) => a + b) / _historyX.length;
    double smoothedY = _historyY.reduce((a, b) => a + b) / _historyY.length;

    // --- CHANGED: REMOVED DEAD ZONE ---
    // We update the stable position every single time to allow for "drift".
    _lastStableX = smoothedX;
    _lastStableY = smoothedY;

    if (_calibrationStep == 9) {
      // 9 means calibration finished
      _updateCursor(_lastStableX, _lastStableY);
    }
  }

  void _updateCursor(double stableX, double stableY) {
    final size = MediaQuery.of(context).size;

    // Normalize X
    double normX = (stableX - _eyeMinX) / (_eyeMaxX - _eyeMinX);
    double normY = (stableY - _eyeMinY) / (_eyeMaxY - _eyeMinY);

    normX = normX.clamp(0.0, 1.0);
    normY = normY.clamp(0.0, 1.0);

    // Map to pixels
    double screenX = normX * size.width;
    double screenY = normY * size.height;

    if (mounted) {
      setState(() {
        _cursorPosition = Offset(screenX, screenY);
      });
    }
  }

  void _nextCalibrationPoint() {
    _recordedEyeVectors.add(Offset(_lastStableX, _lastStableY));

    if (_calibrationStep < 8) {
      setState(() {
        _calibrationStep++;
      });
    } else {
      _finishCalibration();
    }
  }

  void _finishCalibration() {
    if (_recordedEyeVectors.length != 9) return;

    double avgRawLeftX =
        (_recordedEyeVectors[0].dx +
            _recordedEyeVectors[3].dx +
            _recordedEyeVectors[6].dx) /
        3;
    double avgRawRightX =
        (_recordedEyeVectors[2].dx +
            _recordedEyeVectors[5].dx +
            _recordedEyeVectors[8].dx) /
        3;

    double avgRawTopY =
        (_recordedEyeVectors[0].dy +
            _recordedEyeVectors[1].dy +
            _recordedEyeVectors[2].dy) /
        3;
    double avgRawBotY =
        (_recordedEyeVectors[6].dy +
            _recordedEyeVectors[7].dy +
            _recordedEyeVectors[8].dy) /
        3;

    setState(() {
      _eyeMinX = avgRawLeftX;
      _eyeMaxX = avgRawRightX;
      _eyeMinY = avgRawTopY;
      _eyeMaxY = avgRawBotY;
      _calibrationStep = 9; // Finished
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Calibration Complete!")));
  }

  void _resetCalibration() {
    setState(() {
      _calibrationStep = 0;
      _recordedEyeVectors.clear();
    });
  }

  Offset _calculateCentroid(List<math.Point<int>> points) {
    if (points.isEmpty) return Offset.zero;
    double sumX = 0;
    double sumY = 0;
    for (var p in points) {
      sumX += p.x;
      sumY += p.y;
    }
    return Offset(sumX / points.length, sumY / points.length);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bool isCalibrating = _calibrationStep >= 0 && _calibrationStep <= 8;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Main Interaction Area (Visible after calibration)
          if (_calibrationStep == 9)
            Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _buildTestTarget(Colors.red.shade100, "Left Area"),
                      _buildTestTarget(Colors.blue.shade100, "Right Area"),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      _buildTestTarget(Colors.green.shade100, "Bottom Area"),
                    ],
                  ),
                ),
              ],
            ),

          // 2. Calibration UI
          if (isCalibrating)
            Positioned(
              left: _calibrationPoints[_calibrationStep].dx - 30,
              top: _calibrationPoints[_calibrationStep].dy - 30,
              child: GestureDetector(
                onTap: _nextCalibrationPoint,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      "${_calibrationStep + 1}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (isCalibrating)
            const Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Text(
                "Look at the red circle and TAP it.\nKeep your head still.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

          // 3. Reset Button
          if (_calibrationStep == 9)
            Positioned(
              top: 40,
              right: 20,
              child: FloatingActionButton.small(
                onPressed: _resetCalibration,
                child: const Icon(Icons.refresh),
              ),
            ),

          // 4. Debug Data
          Positioned(
            bottom: 40,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black54,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Stable X: ${_lastStableX.toStringAsFixed(2)}"),
                  Text("Stable Y: ${_lastStableY.toStringAsFixed(2)}"),
                  if (_calibrationStep == 9) ...[
                    const SizedBox(height: 4),
                    Text(
                      "Range X: ${_eyeMinX.toStringAsFixed(1)} to ${_eyeMaxX.toStringAsFixed(1)}",
                    ),
                    Text(
                      "Range Y: ${_eyeMinY.toStringAsFixed(1)} to ${_eyeMaxY.toStringAsFixed(1)}",
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 5. The Cursor (Only show after calibration)
          // --- CHANGED: Using AnimatedPositioned for drifting effect ---
          if (_calibrationStep == 9)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300), // Drifting lag
              curve: Curves.easeOut, // Smooth deceleration
              left: _cursorPosition.dx - 15,
              top: _cursorPosition.dy - 15,
              child: IgnorePointer(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.purple,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTestTarget(Color color, String text) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameraController == null) return null;
    final camera = _frontCamera;
    final sensorOrientation = camera!.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isAndroid) {
      var rotationCompensation = _orientations[0]!;
      if (sensorOrientation == 270) {
        rotationCompensation = 270;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    } else {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (image.planes.isEmpty) return null;
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  static const _orientations = {0: 0, 90: 90, 180: 180, 270: 270};
}
