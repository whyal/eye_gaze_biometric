import 'dart:io';
import 'package:eye_gaze_biomarkers/services/gaze_service.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock orientation to portrait to prevent math chaos
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    const MaterialApp(
      home: EyeTrackingScreen(),
      debugShowCheckedModeBanner: false,
    ),
  );
}

class EyeTrackingScreen extends StatefulWidget {
  const EyeTrackingScreen({super.key});

  @override
  State<EyeTrackingScreen> createState() => _EyeTrackingScreenState();
}

class _EyeTrackingScreenState extends State<EyeTrackingScreen> {
  CameraController? _controller;
  FaceMeshDetector? _meshDetector;
  final GazeService _gazeService = GazeService();
  bool _isBusy = false;

  // State Machine
  bool _calibrationMode = false;
  int _calibIndex = 0;
  int _framesCollected = 0;
  final int _framesRequired = 20;

  // Calibration Targets
  final List<Offset> _calibPoints = [
    Offset(50, 50),
    Offset(350, 50),
    Offset(50, 700),
    Offset(350, 700),
    Offset(200, 375),
  ];

  Offset _cursorPos = const Offset(0, 0);
  FaceMesh? _lastMesh;
  Size? _cameraImageSize;
  String _debugResolution = "Initializing...";

  @override
  void initState() {
    super.initState();
    _initCamera();
    _meshDetector = FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final frontCam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );

    _controller = CameraController(
      frontCam,
      // SAMSUNG NOTE 8 FIX:
      // 'veryHigh' forces 1920x1080 (16:9), which matches your camera hardware best.
      // 'low' or 'medium' often gives 4:3, causing misalignment.
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();
    if (mounted) {
      // Read the actual size the camera gave us
      Size size = _controller!.value.previewSize!;
      setState(() {
        _debugResolution = "Cam: ${size.height.toInt()}x${size.width.toInt()}";
      });
      _controller!.startImageStream(_processImage);
    }
  }

  // === UNIFIED SCALING LOGIC (Fixes the Note 8 Mismatch) ===
  TransformationData _getScaleData(Size imageSize, Size screenSize) {
    // 1. Standardize Input (Swap X/Y for 270deg rotation)
    // Note 8 Front camera is usually mounted sideways (270deg)
    double imageW = imageSize.height;
    double imageH = imageSize.width;

    // 2. Calculate Scale to COVER the tall screen
    double scaleX = screenSize.width / imageW;
    double scaleY = screenSize.height / imageH;

    // Max scale = Zoom to fill height, crop width
    double scale = scaleX > scaleY ? scaleX : scaleY;

    // 3. Offset to center the video
    double offsetX = (screenSize.width - imageW * scale) / 2;
    double offsetY = (screenSize.height - imageH * scale) / 2;

    return TransformationData(scale: scale, offsetX: offsetX, offsetY: offsetY);
  }

  Offset _transformPoint(
    FaceMeshPoint p,
    TransformationData data,
    Size screenSize,
  ) {
    // 1. Swap X/Y (Rotation)
    double x = p.y.toDouble();
    double y = p.x.toDouble();

    // 2. Apply Scale & Offset
    double screenX = x * data.scale + data.offsetX;
    double screenY = y * data.scale + data.offsetY;

    // 3. Mirror X (Selfie View)
    screenX = screenSize.width - screenX;

    return Offset(screenX, screenY);
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isBusy || _meshDetector == null) return;
    _isBusy = true;
    _cameraImageSize = Size(image.width.toDouble(), image.height.toDouble());

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) allBytes.putUint8List(plane.bytes);
    final bytes = allBytes.done().buffer.asUint8List();

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: _cameraImageSize!,
        rotation: InputImageRotation.rotation270deg,
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );

    try {
      final meshes = await _meshDetector!.processImage(inputImage);
      if (meshes.isNotEmpty) {
        final mesh = meshes.first;
        final size = MediaQuery.of(context).size;
        setState(() {
          _lastMesh = mesh;
        });

        // Get Scaling Data
        final data = _getScaleData(_cameraImageSize!, size);

        // --- EXTRACT & TRANSFORM ---
        final lInner = _transformPoint(
          mesh.points.firstWhere((p) => p.index == 33),
          data,
          size,
        );
        final lOuter = _transformPoint(
          mesh.points.firstWhere((p) => p.index == 133),
          data,
          size,
        );
        final lTop = _transformPoint(
          mesh.points.firstWhere((p) => p.index == 159),
          data,
          size,
        );
        final lBottom = _transformPoint(
          mesh.points.firstWhere((p) => p.index == 145),
          data,
          size,
        );

        final rInner = _transformPoint(
          mesh.points.firstWhere((p) => p.index == 362),
          data,
          size,
        );
        final rOuter = _transformPoint(
          mesh.points.firstWhere((p) => p.index == 263),
          data,
          size,
        );
        final rTop = _transformPoint(
          mesh.points.firstWhere((p) => p.index == 386),
          data,
          size,
        );
        final rBottom = _transformPoint(
          mesh.points.firstWhere((p) => p.index == 374),
          data,
          size,
        );

        Offset lPupil = Offset(
          (lInner.dx + lOuter.dx + lTop.dx + lBottom.dx) / 4,
          (lInner.dy + lOuter.dy + lTop.dy + lBottom.dy) / 4,
        );
        Offset rPupil = Offset(
          (rInner.dx + rOuter.dx + rTop.dx + rBottom.dx) / 4,
          (rInner.dy + rOuter.dy + rTop.dy + rBottom.dy) / 4,
        );

        // --- Gaze Ratios ---
        double getRatio(double v, double min, double max) {
          double range = max - min;
          if (range == 0) return 0.5;
          return (v - min) / range;
        }

        // Horizontal: Relative to Inner/Outer corners
        double lx = getRatio(
          lPupil.dx,
          lInner.dx < lOuter.dx ? lInner.dx : lOuter.dx,
          lInner.dx > lOuter.dx ? lInner.dx : lOuter.dx,
        );
        double rx = getRatio(
          rPupil.dx,
          rInner.dx < rOuter.dx ? rInner.dx : rOuter.dx,
          rInner.dx > rOuter.dx ? rInner.dx : rOuter.dx,
        );

        // Vertical: Relative to Top/Bottom lids
        double ly = getRatio(lPupil.dy, lTop.dy, lBottom.dy);
        double ry = getRatio(rPupil.dy, rTop.dy, rBottom.dy);

        double avgX = (lx + rx) / 2;
        double avgY = (ly + ry) / 2;

        if (_calibrationMode) {
          _framesCollected++;
          if (_framesCollected > 5) _gazeService.collectSample(avgX, avgY);
          if (_framesCollected > _framesRequired) {
            _gazeService.finishCalibrationPoint(_calibIndex);
            _advanceCalibration();
          }
        } else {
          Offset screenPoint = _gazeService.calculateScreenGaze(
            avgX,
            avgY,
            size,
          );
          setState(() {
            _cursorPos = screenPoint;
          });
        }
      }
    } catch (e) {
      print("Error: $e");
    } finally {
      _isBusy = false;
    }
  }

  void _advanceCalibration() {
    if (_calibIndex < _calibPoints.length - 1) {
      setState(() {
        _calibIndex++;
        _framesCollected = 0;
      });
    } else {
      setState(() {
        _calibrationMode = false;
        _calibIndex = 0;
      });
    }
  }

  void _startCalibration() {
    _gazeService.reset();
    setState(() {
      _calibrationMode = true;
      _calibIndex = 0;
      _framesCollected = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ), // Show loading spinner
      );
    }
    final size = MediaQuery.of(context).size;

    // 1. Setup default scale (1.0 means no zoom)
    var scale = 1.0;

    if (_controller != null && _controller!.value.isInitialized) {
      // Note: In portrait mode, Android swaps width & height.
      // So 'cameraHeight' is actually the width of the sensor, and vice versa.
      double cameraW = _controller!.value.previewSize!.height;
      double cameraH = _controller!.value.previewSize!.width;

      // Compare Screen Dimensions vs Camera Dimensions
      double scaleX = size.width / cameraW;
      double scaleY = size.height / cameraH;

      // 3. The "Cover" Logic: Use the LARGER scale
      // This ensures we zoom in enough to eliminate all black bars
      scale = scaleX > scaleY ? scaleX : scaleY;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. SCALED CAMERA PREVIEW
          Transform.scale(
            scale: scale,
            alignment: Alignment
                .center, // Keep the center of the video in the center of screen
            child: CameraPreview(_controller!),
          ),

          // 2. PAINTER (Passes scale data to draw dots correctly on top of scaled video)
          if (_lastMesh != null && _cameraImageSize != null)
            CustomPaint(
              painter: FacePainter(
                mesh: _lastMesh!,
                imageSize: _cameraImageSize!,
                widgetSize: size,
                scaleData: _getScaleData(_cameraImageSize!, size),
              ),
            ),

          // 3. UI LAYERS
          if (!_calibrationMode && !_gazeService.isCalibrated)
            Center(
              child: ElevatedButton(
                onPressed: _startCalibration,
                child: const Text(
                  "Start Calibration",
                  style: TextStyle(fontSize: 24),
                ),
              ),
            ),

          if (_calibrationMode)
            Positioned(
              left: _calibPoints[_calibIndex].dx - 20,
              top: _calibPoints[_calibIndex].dy - 20,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.gps_fixed, color: Colors.red, size: 40),
                  CircularProgressIndicator(
                    value: _framesCollected / _framesRequired,
                    color: Colors.yellow,
                  ),
                ],
              ),
            ),

          if (_gazeService.isCalibrated && !_calibrationMode)
            Positioned(
              left: _cursorPos.dx - 15,
              top: _cursorPos.dy - 15,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),

          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _startCalibration,
            ),
          ),

          // DEBUG INFO (Check Bottom Left)
          Positioned(
            bottom: 20,
            left: 10,
            child: Text(
              "Res: $_debugResolution",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransformationData {
  final double scale;
  final double offsetX;
  final double offsetY;
  TransformationData({
    required this.scale,
    required this.offsetX,
    required this.offsetY,
  });
}

class FacePainter extends CustomPainter {
  final FaceMesh mesh;
  final Size imageSize;
  final Size widgetSize;
  final TransformationData scaleData;

  FacePainter({
    required this.mesh,
    required this.imageSize,
    required this.widgetSize,
    required this.scaleData,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset transform(FaceMeshPoint p) {
      double x = p.y.toDouble();
      double y = p.x.toDouble();

      double screenX = x * scaleData.scale + scaleData.offsetX;
      double screenY = y * scaleData.scale + scaleData.offsetY;

      screenX = widgetSize.width - screenX;
      return Offset(screenX, screenY);
    }

    final Paint green = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;
    final Paint red = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    void drawEye(int inIdx, int outIdx, int topIdx, int botIdx) {
      final inner = mesh.points.firstWhere((p) => p.index == inIdx);
      final outer = mesh.points.firstWhere((p) => p.index == outIdx);
      final top = mesh.points.firstWhere((p) => p.index == topIdx);
      final bottom = mesh.points.firstWhere((p) => p.index == botIdx);

      canvas.drawCircle(transform(inner), 4, green);
      canvas.drawCircle(transform(outer), 4, green);

      double avgX =
          (transform(inner).dx +
              transform(outer).dx +
              transform(top).dx +
              transform(bottom).dx) /
          4;
      double avgY =
          (transform(inner).dy +
              transform(outer).dy +
              transform(top).dy +
              transform(bottom).dy) /
          4;
      canvas.drawCircle(Offset(avgX, avgY), 5, red);
    }

    drawEye(33, 133, 159, 145);
    drawEye(362, 263, 386, 374);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
