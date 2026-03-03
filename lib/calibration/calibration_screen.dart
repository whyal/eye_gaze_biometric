import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../eye_tracking/eye_tracking_channel.dart';
import '../logging/gaze_jsonl_logger.dart';
import 'calibration_model.dart';

class CalibrationScreen extends StatefulWidget {
  final void Function(CalibrationModel model) onComplete;

  const CalibrationScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<CalibrationScreen> createState() =>
      _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const _points = [
    Alignment.topLeft,
    Alignment.topCenter,
    Alignment.topRight,
    Alignment.centerLeft,
    Alignment.center,
    Alignment.centerRight,
    Alignment.bottomLeft,
    Alignment.bottomCenter,
    Alignment.bottomRight,
  ];

  static const int _requiredDwellMs = 1000;
  static const double _maxStdDev = 0.03;

  StreamSubscription<EyeTrackingSample>? _gazeSub;
  final List<CalibrationSample> _samples = [];
  int _index = 0;
  int _dwellStartMs = -1;
  Offset? _lastGaze;
  Size _lastSize = Size.zero;
  Offset _sumGaze = Offset.zero;
  int _sampleCount = 0;
  final List<Offset> _gazeSamples = [];
  String _statusText = 'Hold still';
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _gazeSub = EyeTrackingChannel.sampleStream.listen((sample) {
      if (!mounted || _index >= _points.length || !_started) return;
      _lastGaze = sample.gazeNorm;
      _logCalibrationFrame(sample);
      _updateFixation();
    });
  }

  @override
  void dispose() {
    _gazeSub?.cancel();
    super.dispose();
  }

  void _updateFixation() {
    if (_lastGaze == null || _lastSize.isEmpty) return;

    final alignment = _points[_index];
    final targetPx = alignment.alongSize(_lastSize);
    final gazeNorm = Offset(
      _lastGaze!.dx.clamp(0.0, 1.0),
      _lastGaze!.dy.clamp(0.0, 1.0),
    );

    final now = DateTime.now().millisecondsSinceEpoch;

    if (_dwellStartMs == -1) {
      _dwellStartMs = now;
      _sumGaze = Offset.zero;
      _sampleCount = 0;
      _gazeSamples.clear();
      _statusText = 'Hold still';
    }

    _sumGaze += gazeNorm;
    _sampleCount += 1;
    _gazeSamples.add(gazeNorm);
    if (now - _dwellStartMs >= _requiredDwellMs) {
      final targetNorm = Offset(
        targetPx.dx / _lastSize.width,
        targetPx.dy / _lastSize.height,
      );
      final avgGaze = _sampleCount == 0
          ? gazeNorm
          : _sumGaze / _sampleCount.toDouble();
      final stdDev = _computeStdDev(_gazeSamples, avgGaze);
      if (stdDev <= _maxStdDev) {
        _samples.add(
          CalibrationSample(raw: avgGaze, target: targetNorm),
        );
        GazeJsonlLogger.instance.logEvent(
          event: 'calibration_point_end',
          payload: {
            'task': 'calibration',
            'trial': _index + 1,
            'status': 'accepted',
          },
        );

        _index += 1;
        _dwellStartMs = -1;

        if (_index >= _points.length) {
          GazeJsonlLogger.instance.logEvent(
            event: 'calibration_end',
            payload: {
              'task': 'calibration',
              'points_collected': _samples.length,
            },
          );
          final model = CalibrationModel.fromSamples(_samples);
          widget.onComplete(model);
        } else {
          _markTargetOn(_index);
        }
      } else {
        _dwellStartMs = -1;
        _statusText = 'Hold still (retry)';
        GazeJsonlLogger.instance.logEvent(
          event: 'calibration_point_end',
          payload: {
            'task': 'calibration',
            'trial': _index + 1,
            'status': 'retry',
            'std_dev': stdDev,
          },
        );
      }
    }

    setState(() {});
  }

  double get _fixationProgress {
    if (_dwellStartMs < 0) return 0.0;
    final elapsed =
        DateTime.now().millisecondsSinceEpoch - _dwellStartMs;
    return (elapsed / _requiredDwellMs).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= _points.length) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Calibration Complete',
            style: TextStyle(color: Colors.white, fontSize: 22),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (_, constraints) {
        _lastSize = constraints.biggest;
        final alignment = _points[_index];

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (!_started)
                _CalibrationIntro(
                  onStart: () {
                    setState(() {
                      _started = true;
                      _index = 0;
                      _dwellStartMs = -1;
                      _samples.clear();
                      _sumGaze = Offset.zero;
                      _sampleCount = 0;
                      _gazeSamples.clear();
                      _statusText = 'Hold still';
                    });
                    GazeJsonlLogger.instance.logEvent(
                      event: 'calibration_start',
                      payload: {
                        'task': 'calibration',
                        'points_total': _points.length,
                      },
                    );
                    _markTargetOn(0);
                  },
                ),
              Align(
                alignment: alignment,
                child: CustomPaint(
                  painter: _RingPainter(_fixationProgress),
                  child: const SizedBox(
                    width: 50,
                    height: 50,
                    child: Center(
                      child: CircleAvatar(
                        radius: 6,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: _CalibrationDebug(
                  gaze: _lastGaze,
                  index: _index + 1,
                  total: _points.length,
                  progress: _fixationProgress,
                  status: _statusText,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

extension on _CalibrationScreenState {
  void _markTargetOn(int pointIndex) {
    final target = _targetForIndex(pointIndex);
    GazeJsonlLogger.instance.logEvent(
      event: 'calibration_point_start',
      payload: {
        'task': 'calibration',
        'trial': pointIndex + 1,
        'tx': target.dx,
        'ty': target.dy,
      },
    );
  }

  Offset _targetForIndex(int pointIndex) {
    if (_lastSize.isEmpty) return const Offset(0.5, 0.5);
    final alignment = _CalibrationScreenState._points[pointIndex];
    final px = alignment.alongSize(_lastSize);
    return Offset(px.dx / _lastSize.width, px.dy / _lastSize.height);
  }

  void _logCalibrationFrame(EyeTrackingSample sample) {
    GazeJsonlLogger.instance.logFrame(
      sample: sample,
      isCalibration: true,
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;

  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;

    final bgPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final fgPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress.clamp(0.0, 1.0),
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress;
}

class _CalibrationDebug extends StatelessWidget {
  final Offset? gaze;
  final int index;
  final int total;
  final double progress;
  final String status;

  const _CalibrationDebug({
    required this.gaze,
    required this.index,
    required this.total,
    required this.progress,
    required this.status,
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
            Text('point: $index / $total'),
            Text('progress: ${progress.toStringAsFixed(2)}'),
            Text('gaze: ${fmt(gaze)}'),
            Text('status: $status'),
          ],
        ),
      ),
    );
  }
}

class _CalibrationIntro extends StatelessWidget {
  final VoidCallback onStart;

  const _CalibrationIntro({
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Calibration Setup',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '• Hold the camera still\n'
              '• Sit at a reasonable distance (30–40 cm)\n'
              '• Keep your head still\n'
              '• Follow each dot with only your eyes',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
              ),
              onPressed: onStart,
              child: const Text(
                'Start Calibration',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _computeStdDev(List<Offset> samples, Offset mean) {
  if (samples.isEmpty) return 0.0;
  double sum = 0.0;
  for (final s in samples) {
    final dx = s.dx - mean.dx;
    final dy = s.dy - mean.dy;
    sum += dx * dx + dy * dy;
  }
  final variance = sum / samples.length;
  return sqrt(variance);
}
