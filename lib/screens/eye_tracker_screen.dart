// import 'package:camera/camera.dart';
// import 'package:eye_gaze_biomarkers/services/gaze_service.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
// import 'package:flutter/services.dart';
// import 'dart:math';
// import 'dart:io';

// enum AppStatus { idle, calibration, tracking }

// class EyeTrackerScreen extends StatefulWidget {
//   @override
//   _EyeTrackerScreenState createState() => _EyeTrackerScreenState();
// }

// class _EyeTrackerScreenState extends State<EyeTrackerScreen>
//     with WidgetsBindingObserver {
//   FaceMeshDetector? _meshDetector;
//   CameraController? _controller;
//   final GazeService _gazeService = GazeService();

//   AppStatus _status = AppStatus.idle;
//   bool _isProcessing = false;

//   // DEBUG VISUALIZATION STATE
//   // We explicitly store the transformed points to draw them exactly as the logic sees them
//   Offset? _debugLeftEye;
//   Offset? _debugRightEye;
//   Offset? _debugIris;
//   String _debugInfo = "Initializing...";

//   Offset _gazePoint = Offset(0, 0);
//   int _calibIndex = 0;
//   int _framesCollected = 0;

//   // Calibration Points
//   final List<Offset> _calibPoints = [
//     Offset(40, 40),
//     Offset(340, 40),
//     Offset(40, 680),
//     Offset(340, 680),
//     Offset(190, 360),
//   ];

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _initializeCamera();
//     _meshDetector = FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _controller?.dispose();
//     _meshDetector?.close();
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (_controller == null || !_controller!.value.isInitialized) return;
//     if (state == AppLifecycleState.inactive)
//       _controller?.dispose();
//     else if (state == AppLifecycleState.resumed)
//       _initializeCamera();
//   }

//   Future<void> _initializeCamera() async {
//     final cameras = await availableCameras();
//     // Try to find front camera
//     final frontCamera = cameras.firstWhere(
//       (c) => c.lensDirection == CameraLensDirection.front,
//       orElse: () => cameras.first,
//     );

//     _controller = CameraController(
//       frontCamera,
//       ResolutionPreset.low, // Keep low for performance (320x240 or 640x480)
//       enableAudio: false,
//       imageFormatGroup: Platform.isAndroid
//           ? ImageFormatGroup.nv21
//           : ImageFormatGroup.bgra8888,
//     );

//     await _controller!.initialize();
//     if (mounted) {
//       setState(() {});
//       _controller!.startImageStream((image) {
//         if (_status == AppStatus.idle) return;
//         if (_isProcessing) return;
//         _isProcessing = true;
//         _processCameraImage(image);
//       });
//     }
//   }

//   // === THE CORE TRANSFORMATION LOGIC ===
//   // This converts Camera Pixels (e.g. 480x640) to Screen Pixels (e.g. 1080x1920)
//   Offset _transformPoint(
//     FaceMeshPoint p,
//     Size imageSize,
//     Size screenSize,
//     InputImageRotation rotation,
//   ) {
//     // 1. Get standard X/Y
//     double x = p.x.toDouble();
//     double y = p.y.toDouble();

//     // 2. Adjust for Android Front Camera (Usually rotated 270 degrees)
//     // Image X axis is actually Screen Y axis
//     // Image Y axis is actually Screen X axis (mirrored)

//     // NOTE: If your dots are rotated 90 degrees, swap the logic in these two lines:
//     double screenX =
//         screenSize.width - (y * screenSize.width / imageSize.width);
//     double screenY = x * screenSize.height / imageSize.height;

//     return Offset(screenX, screenY);
//   }

//   Future<void> _processCameraImage(CameraImage image) async {
//     if (_meshDetector == null) return;

//     final WriteBuffer allBytes = WriteBuffer();
//     for (final Plane plane in image.planes) allBytes.putUint8List(plane.bytes);
//     final bytes = allBytes.done().buffer.asUint8List();

//     final Size imageSize = Size(
//       image.width.toDouble(),
//       image.height.toDouble(),
//     );
//     // Most Android front cameras are 270 deg. If dots are sideways, change this to 90 or 0.
//     final rotation = InputImageRotation.rotation270deg;

//     final inputImage = InputImage.fromBytes(
//       bytes: bytes,
//       metadata: InputImageMetadata(
//         size: imageSize,
//         rotation: rotation,
//         format: Platform.isAndroid
//             ? InputImageFormat.nv21
//             : InputImageFormat.bgra8888,
//         bytesPerRow: image.planes[0].bytesPerRow,
//       ),
//     );

//     try {
//       final List<FaceMesh> meshes = await _meshDetector!.processImage(
//         inputImage,
//       );

//       if (meshes.isNotEmpty) {
//         final mesh = meshes.first;
//         final screenSize = MediaQuery.of(context).size;

//         // 1. Get Raw Landmarks
//         final inner = mesh.points.firstWhere((p) => p.index == 33);
//         final outer = mesh.points.firstWhere((p) => p.index == 133);
//         final top = mesh.points.firstWhere((p) => p.index == 159);
//         final bottom = mesh.points.firstWhere((p) => p.index == 145);

//         // 2. Transform to Screen Coordinates IMMEDIATELY
//         // We pass the RAW image width as width, because in 270deg rotation, width corresponds to Y-axis logic
//         // Actually, for the math below to work with the _transformPoint function:
//         // We treat imageWidth as the "Horizontal" span of the camera sensor (which is Y coordinate in buffer)

//         final Offset pInner = _transformPoint(
//           inner,
//           imageSize,
//           screenSize,
//           rotation,
//         );
//         final Offset pOuter = _transformPoint(
//           outer,
//           imageSize,
//           screenSize,
//           rotation,
//         );
//         final Offset pTop = _transformPoint(
//           top,
//           imageSize,
//           screenSize,
//           rotation,
//         );
//         final Offset pBottom = _transformPoint(
//           bottom,
//           imageSize,
//           screenSize,
//           rotation,
//         );

//         // 3. Calculate Virtual Iris on SCREEN COORDINATES
//         // This ensures the red dot is exactly in the middle of the green dots on screen
//         double irisX = (pInner.dx + pOuter.dx) / 2.0;
//         double irisY = (pTop.dy + pBottom.dy) / 2.0;
//         final Offset pIris = Offset(irisX, irisY);

//         // 4. Update Debug State (So Painter draws exactly this)
//         setState(() {
//           _debugLeftEye = pInner;
//           _debugRightEye = pOuter;
//           _debugIris = pIris;

//           // Debug Text Calculation
//           double eyeW = (pOuter.dx - pInner.dx).abs();
//           double dist = (pIris.dx - pInner.dx).abs();
//           double ratio = eyeW > 0 ? dist / eyeW : 0;
//           _debugInfo =
//               "EyeW: ${eyeW.toStringAsFixed(1)} | Ratio: ${ratio.toStringAsFixed(2)}";
//         });

//         // 5. Pass These Clean Screen Points to Service
//         final irisPt = Point<double>(pIris.dx, pIris.dy);
//         final innerPt = Point<double>(pInner.dx, pInner.dy);
//         final outerPt = Point<double>(pOuter.dx, pOuter.dy);

//         if (_status == AppStatus.calibration) {
//           _framesCollected++;
//           if (_framesCollected > 15)
//             _gazeService.collectSample(irisPt, innerPt, outerPt);
//           if (_framesCollected > 40) {
//             _gazeService.finishCalibrationPoint(_calibIndex);
//             _advanceCalibration();
//           }
//         } else if (_status == AppStatus.tracking) {
//           final screenP = _gazeService.getScreenGaze(
//             irisPt,
//             innerPt,
//             outerPt,
//             screenSize,
//           );
//           setState(() {
//             _gazePoint = screenP;
//           });
//         }
//       } else {
//         setState(() {
//           _debugInfo = "Face: No";
//         });
//       }
//     } catch (e) {
//       print("Error: $e");
//     } finally {
//       _isProcessing = false;
//     }
//   }

//   void _advanceCalibration() {
//     if (_calibIndex < _calibPoints.length - 1) {
//       setState(() {
//         _calibIndex++;
//         _framesCollected = 0;
//       });
//     } else {
//       setState(() {
//         _status = AppStatus.tracking;
//       });
//     }
//   }

//   void _resetApp() {
//     setState(() {
//       _status = AppStatus.idle;
//       _calibIndex = 0;
//       _framesCollected = 0;
//       _gazeService.reset();
//     });
//   }

//   void _startCalibration() {
//     setState(() {
//       _status = AppStatus.calibration;
//       _calibIndex = 0;
//       _framesCollected = 0;
//       _gazeService.reset();
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_controller == null || !_controller!.value.isInitialized)
//       return Center(child: CircularProgressIndicator());

//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         fit: StackFit.expand,
//         children: [
//           CameraPreview(_controller!),

//           // === DEBUG LAYER: Draw exactly what we calculated ===
//           if (_debugLeftEye != null)
//             CustomPaint(
//               painter: SimpleFacePainter(
//                 _debugLeftEye!,
//                 _debugRightEye!,
//                 _debugIris!,
//               ),
//               size: MediaQuery.of(context).size,
//             ),

//           // Status Text
//           Positioned(
//             bottom: 20,
//             left: 10,
//             child: Text(
//               _debugInfo,
//               style: TextStyle(
//                 color: Colors.yellow,
//                 fontSize: 16,
//                 backgroundColor: Colors.black54,
//               ),
//             ),
//           ),

//           // UI Buttons
//           if (_status == AppStatus.idle)
//             Center(
//               child: ElevatedButton(
//                 onPressed: _startCalibration,
//                 child: Text("Start"),
//               ),
//             ),

//           if (_status == AppStatus.calibration)
//             Positioned(
//               left: _calibPoints[_calibIndex].dx - 20,
//               top: _calibPoints[_calibIndex].dy - 20,
//               child: Icon(Icons.gps_fixed, color: Colors.red, size: 40),
//             ),

//           if (_status == AppStatus.tracking)
//             Positioned(
//               left: _gazePoint.dx - 15,
//               top: _gazePoint.dy - 15,
//               child: Container(
//                 width: 30,
//                 height: 30,
//                 color: Colors.blue.withOpacity(0.5),
//               ),
//             ),

//           if (_status != AppStatus.idle)
//             Positioned(
//               top: 30,
//               right: 20,
//               child: IconButton(
//                 icon: Icon(Icons.refresh, color: Colors.white),
//                 onPressed: _resetApp,
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }

// // === SIMPLIFIED PAINTER ===
// // It simply draws the dots we already calculated. No math here.
// class SimpleFacePainter extends CustomPainter {
//   final Offset left;
//   final Offset right;
//   final Offset iris;
//   SimpleFacePainter(this.left, this.right, this.iris);

//   @override
//   void paint(Canvas canvas, Size size) {
//     final pGreen = Paint()
//       ..color = Colors.greenAccent
//       ..strokeWidth = 5
//       ..style = PaintingStyle.fill;
//     final pRed = Paint()
//       ..color = Colors.red
//       ..strokeWidth = 6
//       ..style = PaintingStyle.fill;

//     canvas.drawCircle(left, 5, pGreen);
//     canvas.drawCircle(right, 5, pGreen);
//     canvas.drawCircle(iris, 6, pRed);
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
// }
