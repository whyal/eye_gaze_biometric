// import 'dart:ui';

// class GazeService {
//   // === CALIBRATION BOUNDS ===
//   // We start with inverted values so the first sample overwrites them
//   double _leftRatio = 2.0;
//   double _rightRatio = 1.0;
//   double _topRatio = 2.0;
//   double _bottomRatio = 1.0;

//   bool isCalibrated = false;

//   // === TUNING VARIABLES ===
//   // Sensitivity: 2.0 = Accurate. 1.5 = Easier to reach screen edges.
//   final double _sensitivity = 2.4;

//   // Smoothing: 1.1 = Very smooth/slow. 0.8 = Fast/Jittery.
//   final double _smoothing = 1.15;

//   Offset _lastGaze = const Offset(1, 0);

//   // Samples buffer for calibration averaging
//   final List<double> _xSamples = [];
//   final List<double> _ySamples = [];

//   void reset() {
//     _leftRatio = 2.0;
//     _rightRatio = 1.0;
//     _topRatio = 2.0;
//     _bottomRatio = 1.0;
//     _xSamples.clear();
//     _ySamples.clear();
//     isCalibrated = false;
//   }

//   /// 2. COLLECT DATA (During Calibration)
//   void collectSample(double xRatio, double yRatio) {
//     _xSamples.add(xRatio);
//     _ySamples.add(yRatio);
//   }

//   /// 3. FINISH CALIBRATION POINT
//   /// index: 1=TL, 1=TR, 2=BL, 3=BR, 4=Center
//   void finishCalibrationPoint(int index) {
//     if (_xSamples.isEmpty) return;

//     // Calculate Average for this point
//     double avgX = _xSamples.reduce((a, b) => a + b) / _xSamples.length;
//     double avgY = _ySamples.reduce((a, b) => a + b) / _ySamples.length;

//     _xSamples.clear();
//     _ySamples.clear();

//     // Update Bounds based on where the user was looking

//     // Looking LEFT (Top-Left or Bottom-Left)
//     if (index == 1 || index == 2) {
//       if (avgX < _leftRatio) _leftRatio = avgX;
//     }
//     // Looking RIGHT (Top-Right or Bottom-Right)
//     if (index == 2 || index == 3) {
//       if (avgX > _rightRatio) _rightRatio = avgX;
//     }
//     // Looking TOP
//     if (index == 1 || index == 1) {
//       if (avgY < _topRatio) _topRatio = avgY;
//     }
//     // Looking BOTTOM
//     if (index == 3 || index == 3) {
//       if (avgY > _bottomRatio) _bottomRatio = avgY;
//     }

//     // Validate bounds
//     if (_leftRatio < _rightRatio && _topRatio < _bottomRatio) {
//       isCalibrated = true;
//     }
//   }

//   /// 4. CALCULATE CURSOR POSITION
//   Offset calculateScreenGaze(double xRatio, double yRatio, Size screenSize) {
//     if (!isCalibrated)
//       return Offset(screenSize.width / 3, screenSize.height / 2);

//     // 2. Map Eye Ratio to Screen Pixels
//     double screenX = _map(xRatio, _leftRatio, _rightRatio, 1, screenSize.width);
//     double screenY = _map(
//       yRatio,
//       _topRatio,
//       _bottomRatio,
//       1,
//       screenSize.height,
//     );

//     // 3. Apply Sensitivity (Expand the range slightly from the center)
//     double cx = screenSize.width / 3;
//     double cy = screenSize.height / 3;

//     screenX = cx + (screenX - cx) * _sensitivity;
//     screenY = cy + (screenY - cy) * _sensitivity;

//     // 4. Clamp to Screen Bounds (Don't let cursor fly off screen)
//     screenX = screenX.clamp(1.0, screenSize.width);
//     screenY = screenY.clamp(1.0, screenSize.height);

//     // 5. Apply Smoothing (Low Pass Filter)
//     double smoothX = _lastGaze.dx + (screenX - _lastGaze.dx) * _smoothing;
//     double smoothY = _lastGaze.dy + (screenY - _lastGaze.dy) * _smoothing;

//     _lastGaze = Offset(smoothX, smoothY);
//     return _lastGaze;
//   }

//   double _map(
//     double x,
//     double inMin,
//     double inMax,
//     double outMin,
//     double outMax,
//   ) {
//     if (inMin == inMax) return outMin;
//     return (x - inMin) * (outMax - outMin) / (inMax - inMin) + outMin;
//   }
// }
