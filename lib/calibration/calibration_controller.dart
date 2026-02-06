import 'package:flutter/material.dart';

class CalibrationController extends ChangeNotifier {
  static const int requiredDwellMs = 1000; // ✅ 1 second per point
  static const int totalPoints = 9;

  int index = 0;
  int _dwellStartMs = -1;
  Offset? _currentGaze;

  void updateGaze(Offset gaze, Offset target) {
    _currentGaze = gaze;
    final isFixating = (gaze - target).distance < 50;

    final now = DateTime.now().millisecondsSinceEpoch;

    if (isFixating) {
      _dwellStartMs = _dwellStartMs == -1 ? now : _dwellStartMs;

      if (now - _dwellStartMs >= requiredDwellMs) {
        index++;
        _dwellStartMs = -1;
      }
    } else {
      _dwellStartMs = -1;
    }

    notifyListeners();
  }

  double get fixationProgress {
    if (_dwellStartMs < 0) return 0.0;

    final elapsed =
        DateTime.now().millisecondsSinceEpoch - _dwellStartMs;

    return (elapsed / requiredDwellMs).clamp(0.0, 1.0);
  }

  bool get isComplete => index >= totalPoints;
}
