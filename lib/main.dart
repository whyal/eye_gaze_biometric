import 'package:flutter/material.dart';
import 'experiment/calibration_flow.dart';

export 'experiment/calibration_flow.dart';

void main() {
  runApp(const GazeTrackerApp());
}

class GazeTrackerApp extends StatelessWidget {
  const GazeTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CalibrationFlow(),
    );
  }
}
