import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../calibration/calibration_model.dart';
import '../eye_tracking/eye_tracking_channel.dart';
import '../logging/gaze_jsonl_logger.dart';
import 'widgets/fixation_target_dot.dart';
import 'widgets/gaze_debug_view.dart';
import 'widgets/inter_task_break_overlay.dart';
import 'widgets/reading_page_card.dart';

class GazeDemoScreen extends StatefulWidget {
  final CalibrationModel model;
  final VoidCallback onRedoCalibration;
  final Future<void> Function() onSessionComplete;

  const GazeDemoScreen({
    super.key,
    required this.model,
    required this.onRedoCalibration,
    required this.onSessionComplete,
  });

  @override
  State<GazeDemoScreen> createState() => _GazeDemoScreenState();
}

class _GazeDemoScreenState extends State<GazeDemoScreen> {
  static const _settleMs = 500;
  static const _recordWindowMs = 1200;
  static const _fixationRounds = 1;
  static const _interTaskBreakMs = 12000;
  static const _pursuitInstructionMs = 2000;
  static const _pursuitMotionMs = 16000;
  static const _pursuitPeriodMs = 4000;
  static const _pursuitRadiusNorm = 0.28;
  static const _pursuitCenterNorm = Offset(0.5, 0.5);
  static const _showGazeCursor = false;
  static const _readingPageTimeoutMs = 120000;
  static const List<String> _readingPages = [
    'Morning light filtered through the quiet cafe as the warm aroma of '
        'roasted coffee beans filled the air. A barista carefully poured '
        'steamed milk, sketching a delicate leaf on top of a latte. '
        'Regular customers settled into their favorite window seats with '
        'books and journals.\n\n'
        'Outside, gentle footsteps echoed down the sidewalk as the town '
        'slowly began to awaken for the day.',
  ];

  static const List<FixTarget> _fixationPattern = [
    FixTarget('C', Offset(0.5, 0.5)),
    FixTarget('TR', Offset(0.8, 0.2)),
    FixTarget('ML', Offset(0.2, 0.5)),
    FixTarget('BR', Offset(0.8, 0.8)),
    FixTarget('TM', Offset(0.5, 0.2)),
    FixTarget('BL', Offset(0.2, 0.8)),
    FixTarget('MR', Offset(0.8, 0.5)),
    FixTarget('TL', Offset(0.2, 0.2)),
    FixTarget('BM', Offset(0.5, 0.8)),
  ];

  Offset? _lastGaze;
  Offset? _smoothed;
  bool _sequenceStarted = false;
  bool _fixationRunning = false;
  bool _pursuitInstruction = false;
  bool _pursuitRunning = false;
  bool _readingRunning = false;
  bool _interTaskBreakRunning = false;
  bool _allActivitiesCompleted = false;
  bool _completionNotified = false;
  int _currentRound = 0;
  int _currentTrial = -1;
  int _readingPageIndex = -1;
  int _interTaskBreakRemaining = 0;
  double _interTaskBreakProgress = 0;
  String _nextTaskLabel = '';
  Offset? _pursuitDotNorm;
  bool _disposed = false;
  Timer? _pursuitTicker;
  int _pursuitMoveStartMs = -1;
  StreamSubscription<EyeTrackingSample>? _gazeSub;
  Completer<void>? _readingCompleter;

  @override
  void initState() {
    super.initState();
    _gazeSub = EyeTrackingChannel.sampleStream.listen((sample) {
      if (!mounted) return;
      final corrected = widget.model.apply(sample.gazeNorm);
      _smoothed = _smoothed == null
          ? corrected
          : Offset.lerp(_smoothed, corrected, 0.25);
      GazeJsonlLogger.instance.logFrame(
        sample: sample,
        calibratedNorm: corrected,
        isCalibration: false,
      );
      setState(() => _lastGaze = _smoothed);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runActivitySequence();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pursuitTicker?.cancel();
    _gazeSub?.cancel();
    if (_readingCompleter != null && !_readingCompleter!.isCompleted) {
      _readingCompleter!.complete();
    }
    super.dispose();
  }

  void _onReadingPageDone() {
    if (_readingCompleter != null && !_readingCompleter!.isCompleted) {
      _readingCompleter!.complete();
    }
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
              if (_fixationRunning && _currentTrial >= 0)
                FixationTargetDot(
                  target: _fixationPattern[_currentTrial].posNorm,
                  size: size,
                ),
              if (_pursuitRunning && _pursuitDotNorm != null)
                FixationTargetDot(
                  target: _pursuitDotNorm!,
                  size: size,
                ),
              if (_showGazeCursor && mapped != null)
                Positioned(
                  left: mapped.dx - 8,
                  top: mapped.dy - 8,
                  child: const GazeDot(),
                ),
              Positioned(
                left: 12,
                top: 12,
                child: GazeDebugView(
                  gaze: _lastGaze,
                  mapped: mapped,
                  size: size,
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: 220,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white24,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        onPressed: widget.onRedoCalibration,
                        child: const Text('Recalibrate'),
                      ),
                    ),
                  ),
                ),
              ),
              if (_pursuitInstruction)
                const Align(
                  alignment: Alignment.center,
                  child: Text(
                    'Follow the moving dot with your eyes only.',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_interTaskBreakRunning)
                InterTaskBreakOverlay(
                  nextTaskLabel: _nextTaskLabel,
                  secondsRemaining: _interTaskBreakRemaining,
                  progress: _interTaskBreakProgress,
                ),
              if (_readingRunning && _readingPageIndex >= 0)
                ReadingPageCard(
                  pageNumber: _readingPageIndex + 1,
                  totalPages: _readingPages.length,
                  text: _readingPages[_readingPageIndex],
                  onDone: _onReadingPageDone,
                ),
              if (_allActivitiesCompleted)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Text(
                      'Fixation + Pursuit + Reading Complete',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
                ),
              if (_fixationRunning)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      'Fixation Round $_currentRound  Trial ${_currentTrial + 1}/9',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
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
    final nx = normalized.dx;
    final ny = normalized.dy;
    final dx = (nx.clamp(0.0, 1.0) * size.width);
    final dy = (ny.clamp(0.0, 1.0) * size.height);
    return Offset(dx, dy);
  }

  Future<void> _runActivitySequence() async {
    if (_sequenceStarted || _disposed) return;
    _sequenceStarted = true;
    await _runFixationRounds();
    if (_disposed) return;
    await _runInterTaskBreak('Pursuit');
    if (_disposed) return;
    await _runPursuitTask();
    if (_disposed) return;
    await _runInterTaskBreak('Reading');
    if (_disposed) return;
    await _runReadingTask();
    if (_disposed) return;
    setState(() {
      _allActivitiesCompleted = true;
    });
    if (!_completionNotified) {
      _completionNotified = true;
      await Future.delayed(const Duration(milliseconds: 1200));
      if (_disposed) return;
      await widget.onSessionComplete();
    }
  }

  Future<void> _runFixationRounds() async {
    setState(() {
      _fixationRunning = true;
      _allActivitiesCompleted = false;
    });

    for (var round = 1; round <= _fixationRounds; round++) {
      if (_disposed) return;
      setState(() => _currentRound = round);
      GazeJsonlLogger.instance.logEvent(
        event: 'fix_round_start',
        payload: {
          'task': 'fixation',
          'round': round,
          'round_total': _fixationRounds,
        },
      );

      for (var i = 0; i < _fixationPattern.length; i++) {
        if (_disposed) return;
        final t = _fixationPattern[i];
        setState(() => _currentTrial = i);

        GazeJsonlLogger.instance.logEvent(
          event: 'target_on',
          payload: {
            'task': 'fixation',
            'round': round,
            'trial': i + 1,
            'target_id': t.id,
            'tx': t.posNorm.dx,
            'ty': t.posNorm.dy,
          },
        );

        await Future.delayed(const Duration(milliseconds: _settleMs));
        if (_disposed) return;

        GazeJsonlLogger.instance.logEvent(
          event: 'record_window_start',
          payload: {
            'task': 'fixation',
            'round': round,
            'trial': i + 1,
          },
        );

        await Future.delayed(const Duration(milliseconds: _recordWindowMs));
        if (_disposed) return;

        GazeJsonlLogger.instance.logEvent(
          event: 'record_window_end',
          payload: {
            'task': 'fixation',
            'round': round,
            'trial': i + 1,
          },
        );
        GazeJsonlLogger.instance.logEvent(
          event: 'target_off',
          payload: {'task': 'fixation', 'round': round, 'trial': i + 1},
        );
      }

      GazeJsonlLogger.instance.logEvent(
        event: 'fix_round_end',
        payload: {
          'task': 'fixation',
          'round': round,
          'round_total': _fixationRounds,
        },
      );
    }

    if (_disposed) return;
    setState(() {
      _fixationRunning = false;
      _currentTrial = -1;
    });
  }

  Future<void> _runPursuitTask() async {
    if (_disposed) return;
    setState(() {
      _pursuitInstruction = true;
      _pursuitRunning = false;
      _pursuitDotNorm = null;
    });
    GazeJsonlLogger.instance.logEvent(
      event: 'instruction_start',
      payload: {'task': 'pursuit'},
    );

    await Future.delayed(const Duration(milliseconds: _pursuitInstructionMs));
    if (_disposed) return;

    GazeJsonlLogger.instance.logEvent(
      event: 'instruction_end',
      payload: {'task': 'pursuit'},
    );

    _pursuitMoveStartMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _pursuitInstruction = false;
      _pursuitRunning = true;
      _pursuitDotNorm = _computePursuitDotNorm(0);
    });
    GazeJsonlLogger.instance.logEvent(
      event: 'pursuit_start',
      payload: {
        'task': 'pursuit',
        'pattern': 'circle',
        'radius_norm': _pursuitRadiusNorm,
        'period_sec': _pursuitPeriodMs / 1000.0,
        'duration_sec': _pursuitMotionMs / 1000.0,
        'cx': _pursuitCenterNorm.dx,
        'cy': _pursuitCenterNorm.dy,
      },
    );

    _pursuitTicker?.cancel();
    _pursuitTicker = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (_disposed || !_pursuitRunning) return;
        final elapsed = DateTime.now().millisecondsSinceEpoch - _pursuitMoveStartMs;
        if (elapsed >= _pursuitMotionMs) return;
        setState(() {
          _pursuitDotNorm = _computePursuitDotNorm(elapsed);
        });
      },
    );

    await Future.delayed(const Duration(milliseconds: _pursuitMotionMs));
    if (_disposed) return;
    _pursuitTicker?.cancel();
    _pursuitTicker = null;
    GazeJsonlLogger.instance.logEvent(
      event: 'pursuit_end',
      payload: {'task': 'pursuit'},
    );
    setState(() {
      _pursuitRunning = false;
      _pursuitDotNorm = null;
    });
  }

  Future<void> _runReadingTask() async {
    if (_disposed) return;
    GazeJsonlLogger.instance.logEvent(
      event: 'reading_start',
      payload: {'task': 'reading', 'mode': 'self_paced'},
    );
    setState(() {
      _readingRunning = true;
      _readingPageIndex = 0;
    });
    for (var i = 0; i < _readingPages.length; i++) {
      if (_disposed) return;
      setState(() => _readingPageIndex = i);
      final pageStartMs = DateTime.now().millisecondsSinceEpoch;
      GazeJsonlLogger.instance.logEvent(
        event: 'reading_page_start',
        payload: {'page': i + 1},
      );

      _readingCompleter = Completer<void>();
      await Future.any([
        _readingCompleter!.future,
        Future.delayed(const Duration(milliseconds: _readingPageTimeoutMs)),
      ]);

      if (_disposed) return;
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - pageStartMs;
      GazeJsonlLogger.instance.logEvent(
        event: 'reading_page_end',
        payload: {
          'page': i + 1,
          'duration_ms': elapsedMs,
        },
      );
    }
    if (_disposed) return;
    GazeJsonlLogger.instance.logEvent(
      event: 'reading_end',
      payload: {'task': 'reading'},
    );
    setState(() {
      _readingRunning = false;
      _readingPageIndex = -1;
    });
  }

  Future<void> _runInterTaskBreak(String nextTaskLabel) async {
    if (_disposed) return;

    setState(() {
      _interTaskBreakRunning = true;
      _nextTaskLabel = nextTaskLabel;
      _interTaskBreakRemaining = (_interTaskBreakMs / 1000).ceil();
      _interTaskBreakProgress = 0;
    });

    GazeJsonlLogger.instance.logEvent(
      event: 'break_start',
      payload: {
        'next_task': nextTaskLabel.toLowerCase(),
        'duration_sec': _interTaskBreakMs / 1000.0,
      },
    );

    final stopwatch = Stopwatch()..start();
    while (!_disposed && stopwatch.elapsedMilliseconds < _interTaskBreakMs) {
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final remainingMs = _interTaskBreakMs - elapsedMs;
      setState(() {
        _interTaskBreakRemaining = (remainingMs / 1000).ceil();
        _interTaskBreakProgress =
            elapsedMs.clamp(0, _interTaskBreakMs) / _interTaskBreakMs;
      });
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (_disposed) return;

    GazeJsonlLogger.instance.logEvent(
      event: 'break_end',
      payload: {'next_task': nextTaskLabel.toLowerCase()},
    );

    setState(() {
      _interTaskBreakRunning = false;
      _interTaskBreakRemaining = 0;
      _interTaskBreakProgress = 0;
      _nextTaskLabel = '';
    });
  }

  Offset _computePursuitDotNorm(int elapsedMs) {
    final turn = (elapsedMs % _pursuitPeriodMs) / _pursuitPeriodMs;
    final angle = -math.pi / 2 + (2 * math.pi * turn);
    final x = _pursuitCenterNorm.dx + (_pursuitRadiusNorm * math.cos(angle));
    final y = _pursuitCenterNorm.dy + (_pursuitRadiusNorm * math.sin(angle));
    return Offset(
      x.clamp(0.05, 0.95),
      y.clamp(0.05, 0.95),
    );
  }
}
