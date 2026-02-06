import 'dart:async';
import 'package:flutter/material.dart';
import 'eye_tracking/eye_tracking_channel.dart';
import 'calibration/calibration_model.dart';
import 'calibration/calibration_screen.dart';

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

class CalibrationFlow extends StatefulWidget {
  const CalibrationFlow({super.key});

  @override
  State<CalibrationFlow> createState() => _CalibrationFlowState();
}

class _CalibrationFlowState extends State<CalibrationFlow> {
  CalibrationModel? _model;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      EyeTrackingChannel.initialize();
    });
  }

  @override
  void dispose() {
    EyeTrackingChannel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_model == null) {
      return CalibrationScreen(
        onComplete: (model) => setState(() => _model = model),
      );
    }
    return GazeDemoScreen(
      model: _model!,
      onRedoCalibration: () => setState(() => _model = null),
    );
  }
}

class GazeDemoScreen extends StatefulWidget {
  final CalibrationModel model;
  final VoidCallback onRedoCalibration;

  const GazeDemoScreen({
    super.key,
    required this.model,
    required this.onRedoCalibration,
  });

  @override
  State<GazeDemoScreen> createState() => _GazeDemoScreenState();
}

class _GazeDemoScreenState extends State<GazeDemoScreen> {
  Offset? _lastGaze;
  Offset? _smoothed;
  StreamSubscription<Offset>? _gazeSub;

  @override
  void initState() {
    super.initState();
    _gazeSub = EyeTrackingChannel.gazeStream.listen((gaze) {
      if (!mounted) return;
      final corrected = widget.model.apply(gaze);
      _smoothed = _smoothed == null
          ? corrected
          : Offset.lerp(_smoothed, corrected, 0.25);
      setState(() => _lastGaze = _smoothed);
    });
  }

  @override
  void dispose() {
    _gazeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (_, constraints) {
          final size = constraints.biggest;
          final mapped = _mapNormalizedToScreen(_lastGaze, size);
          return Stack(
            children: [
              if (mapped != null)
                Positioned(
                  left: mapped.dx - 8,
                  top: mapped.dy - 8,
                  child: const _GazeDot(),
                ),
              Positioned(
                left: 12,
                top: 12,
                child: _GazeDebug(
                  gaze: _lastGaze,
                  mapped: mapped,
                  size: size,
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white24,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: widget.onRedoCalibration,
                  child: const Text('Recalibrate'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Offset? _mapNormalizedToScreen(Offset? normalized, Size size) {
    if (normalized == null) return null;
    const bool invertX = false; // screen-space gaze
    const bool invertY = false;
    final nx = invertX ? (1.0 - normalized.dx) : normalized.dx;
    final ny = invertY ? (1.0 - normalized.dy) : normalized.dy;
    final dx = (nx.clamp(0.0, 1.0) * size.width);
    final dy = (ny.clamp(0.0, 1.0) * size.height);
    return Offset(dx, dy);
  }
}

class _GazeDot extends StatelessWidget {
  const _GazeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.greenAccent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.greenAccent.withOpacity(0.6),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

class _GazeDebug extends StatelessWidget {
  final Offset? gaze;
  final Offset? mapped;
  final Size size;

  const _GazeDebug({
    required this.gaze,
    required this.mapped,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    String fmt(Offset? o) {
      if (o == null) return 'null';
      return '(${o.dx.toStringAsFixed(3)}, ${o.dy.toStringAsFixed(3)})';
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('normalized: ${fmt(gaze)}'),
            Text('mapped:     ${fmt(mapped)}'),
            Text('screen:     ${size.width.toStringAsFixed(0)} x '
                '${size.height.toStringAsFixed(0)}'),
          ],
        ),
      ),
    );
  }
}
