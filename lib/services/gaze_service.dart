import 'dart:ui';

class GazeService {
  double _leftRatio = 1.0;
  double _rightRatio = 0.0;
  double _topRatio = 1.0;
  double _bottomRatio = 0.0;

  bool isCalibrated = false;

  // Smoothing variables
  Offset _lastGaze = const Offset(0, 0);
  final double _smoothing = 0.2;
  final List<double> _xSamples = [];
  final List<double> _ySamples = [];

  // NEW: We simply accept the calculated X/Y ratios
  void collectSample(double xRatio, double yRatio) {
    _xSamples.add(xRatio);
    _ySamples.add(yRatio);
  }

  void finishCalibrationPoint(int pointIndex) {
    if (_xSamples.isEmpty) return;

    double avgX = _xSamples.reduce((a, b) => a + b) / _xSamples.length;
    double avgY = _ySamples.reduce((a, b) => a + b) / _ySamples.length;

    _xSamples.clear();
    _ySamples.clear();

    // 0=TL, 1=TR, 2=BL, 3=BR
    if (pointIndex == 0 || pointIndex == 2) {
      // Looking Left
      if (avgX < _leftRatio) _leftRatio = avgX;
    }
    if (pointIndex == 1 || pointIndex == 3) {
      // Looking Right
      if (avgX > _rightRatio) _rightRatio = avgX;
    }
    if (pointIndex == 0 || pointIndex == 1) {
      // Looking Top
      if (avgY < _topRatio) _topRatio = avgY;
    }
    if (pointIndex == 2 || pointIndex == 3) {
      // Looking Bottom
      if (avgY > _bottomRatio) _bottomRatio = avgY;
    }

    if (_leftRatio < _rightRatio && _topRatio < _bottomRatio) {
      isCalibrated = true;
    }
  }

  Offset calculateScreenGaze(double xRatio, double yRatio, Size screenSize) {
    if (!isCalibrated)
      return Offset(screenSize.width / 2, screenSize.height / 2);

    double screenX = _map(xRatio, _leftRatio, _rightRatio, 0, screenSize.width);
    double screenY = _map(
      yRatio,
      _topRatio,
      _bottomRatio,
      0,
      screenSize.height,
    );

    // Smoothing
    double smoothX = _lastGaze.dx + (screenX - _lastGaze.dx) * _smoothing;
    double smoothY = _lastGaze.dy + (screenY - _lastGaze.dy) * _smoothing;

    _lastGaze = Offset(smoothX, smoothY);
    return _lastGaze;
  }

  double _map(
    double x,
    double inMin,
    double inMax,
    double outMin,
    double outMax,
  ) {
    if (inMin == inMax) return outMin;
    return (x - inMin) * (outMax - outMin) / (inMax - inMin) + outMin;
  }

  void reset() {
    _leftRatio = 1.0;
    _rightRatio = 0.0;
    _topRatio = 1.0;
    _bottomRatio = 0.0;
    isCalibrated = false;
  }
}
