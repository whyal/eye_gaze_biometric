import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'eye_tracking/eye_tracking_channel.dart';
import 'logging/gaze_jsonl_logger.dart';
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
  static const _calibrationVersion = 'poly_v2_9pt_1s';
  static const _fixationPatternId = '9pt_perm_v1';
  CalibrationModel? _model;
  String? _participantId;

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
    unawaited(GazeJsonlLogger.instance.stopSession());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_participantId == null) {
      return ParticipantEntryScreen(
        onStart: (participantId) async {
          await GazeJsonlLogger.instance.startSession(
            participantId: participantId,
            taskId: 'eye_gaze',
            calibrationVersion: _calibrationVersion,
            fixationPatternId: _fixationPatternId,
          );
          if (!mounted) return;
          setState(() {
            _participantId = participantId;
          });
        },
      );
    }

    if (_model == null) {
      return CalibrationScreen(
        onComplete: (model) => setState(() => _model = model),
      );
    }
    return GazeDemoScreen(
      model: _model!,
      onRedoCalibration: () {
        GazeJsonlLogger.instance.logEvent(event: 'recalibrate');
        setState(() => _model = null);
      },
      onSessionComplete: () async {
        await GazeJsonlLogger.instance.stopSession();
        if (!mounted) return;
        setState(() {
          _participantId = null;
          _model = null;
        });
      },
    );
  }
}

class ParticipantEntryScreen extends StatefulWidget {
  final Future<void> Function(String participantId) onStart;

  const ParticipantEntryScreen({
    super.key,
    required this.onStart,
  });

  @override
  State<ParticipantEntryScreen> createState() =>
      _ParticipantEntryScreenState();
}

class _ParticipantEntryScreenState extends State<ParticipantEntryScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatParticipantId(int n) => 'P${n.toString().padLeft(3, '0')}';

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final numericId = int.parse(_controller.text.trim());
    final participantId = _formatParticipantId(numericId);
    setState(() => _submitting = true);
    final info = await GazeJsonlLogger.instance
        .getParticipantSessionInfo(participantId);
    setState(() {
      _hint = info.participantExists
          ? 'Existing user: $participantId (${info.existingSessionCount} prior sessions)'
          : 'New user: $participantId';
    });
    await widget.onStart(participantId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Participant Setup',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Enter participant number (e.g. 12 -> P012)',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Participant Number',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white38),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.greenAccent),
                    ),
                  ),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'Enter a participant number';
                    final n = int.tryParse(v);
                    if (n == null || n <= 0) return 'Enter a positive integer';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (_hint != null)
                  Text(
                    _hint!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(_submitting ? 'Starting...' : 'Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
  static const _fixationRounds = 2;
  static const _pursuitInstructionMs = 2000;
  static const _pursuitMotionMs = 28000;
  static const _pursuitPeriodMs = 4000;
  static const _pursuitRadiusNorm = 0.28;
  static const _pursuitCenterNorm = Offset(0.5, 0.5);
  static const _readingPageMs = 20000;
  static const List<String> _readingPages = [
    'Cities may seem busy and unpredictable, but behind the scenes they '
        'depend on many organized systems. These systems work quietly every '
        'day to make sure that people can live comfortably. Most people only '
        'notice them when something stops working.\n\n'
        'One important system is water supply. Clean water travels through a '
        'large network of underground pipes. Pumping stations move the water '
        'from treatment plants to homes and buildings. Engineers monitor the '
        'system to make sure water pressure stays stable. At the same time, '
        'wastewater from sinks and toilets must be collected and cleaned '
        'before it is released safely. This process uses filters, chemicals, '
        'and helpful bacteria to remove waste.\n\n'
        'Electricity is another essential service. Power plants generate '
        'electricity using different energy sources, such as natural gas, '
        'wind, or solar power. The electricity travels through transmission '
        'lines and then into local neighborhoods. Substations reduce the '
        'voltage so it can be used safely in homes and offices. Today, many '
        'cities use “smart grids” that help detect outages quickly and '
        'balance supply and demand.',
    'Transportation systems also play a major role in daily life. Traffic '
        'lights are programmed to reduce congestion and improve safety. '
        'Public buses and trains follow schedules designed to move large '
        'numbers of people efficiently. Maintenance teams regularly inspect '
        'roads, bridges, and rail tracks. Even small problems in one part of '
        'the transportation system can cause delays across the city.\n\n'
        'Communication networks connect everything together. Fiber-optic '
        'cables carry large amounts of information very quickly. Wireless '
        'towers and routers help people access the internet and make phone '
        'calls. As more devices connect to the network, managing data traffic '
        'becomes more complex. Reliable communication is especially important '
        'during emergencies.',
    'Cities also rely on delivery systems to bring food, medicine, and other '
        'goods to stores and homes. Distribution centers organize shipments '
        'using computer software. Delivery drivers follow routes planned to '
        'save time and fuel. Temperature-controlled trucks help keep food '
        'fresh during transport.\n\n'
        'All of these systems are connected. If electricity fails, water '
        'treatment plants may stop working. If roads are blocked, deliveries '
        'may be delayed. Because everything is linked, city planners focus on '
        'improving reliability and preparing for unexpected problems.\n\n'
        'Although these systems are often invisible, they are carefully '
        'managed every day. Engineers, technicians, and planners monitor '
        'equipment, repair damage, and update technology. Their work ensures '
        'that when someone turns on a tap, switches on a light, or takes a '
        'bus, everything functions as expected.\n\n'
        'The smooth operation of a city depends on constant planning and '
        'teamwork. Even though most people do not see these systems, they '
        'play a crucial role in modern life.',
  ];

  static const List<_FixTarget> _fixationPattern = [
    _FixTarget('C', Offset(0.5, 0.5)),
    _FixTarget('TR', Offset(0.8, 0.2)),
    _FixTarget('ML', Offset(0.2, 0.5)),
    _FixTarget('BR', Offset(0.8, 0.8)),
    _FixTarget('TM', Offset(0.5, 0.2)),
    _FixTarget('BL', Offset(0.2, 0.8)),
    _FixTarget('MR', Offset(0.8, 0.5)),
    _FixTarget('TL', Offset(0.2, 0.2)),
    _FixTarget('BM', Offset(0.5, 0.8)),
  ];

  Offset? _lastGaze;
  Offset? _smoothed;
  bool _sequenceStarted = false;
  bool _fixationRunning = false;
  bool _pursuitInstruction = false;
  bool _pursuitRunning = false;
  bool _readingRunning = false;
  bool _allActivitiesCompleted = false;
  bool _completionNotified = false;
  int _currentRound = 0;
  int _currentTrial = -1;
  int _readingPageIndex = -1;
  Offset? _pursuitDotNorm;
  bool _disposed = false;
  Timer? _pursuitTicker;
  int _pursuitMoveStartMs = -1;
  StreamSubscription<EyeTrackingSample>? _gazeSub;

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
              if (_fixationRunning && _currentTrial >= 0)
                _FixationTargetDot(
                  target: _fixationPattern[_currentTrial].posNorm,
                  size: size,
                ),
              if (_pursuitRunning && _pursuitDotNorm != null)
                _FixationTargetDot(
                  target: _pursuitDotNorm!,
                  size: size,
                ),
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
              if (_readingRunning && _readingPageIndex >= 0)
                _ReadingPageCard(
                  pageNumber: _readingPageIndex + 1,
                  text: _readingPages[_readingPageIndex],
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
    await _runPursuitTask();
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
      payload: {'task': 'reading'},
    );
    setState(() {
      _readingRunning = true;
      _readingPageIndex = 0;
    });
    for (var i = 0; i < _readingPages.length; i++) {
      if (_disposed) return;
      setState(() => _readingPageIndex = i);
      GazeJsonlLogger.instance.logEvent(
        event: 'reading_page_start',
        payload: {'page': i + 1},
      );
      await Future.delayed(const Duration(milliseconds: _readingPageMs));
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

class _FixTarget {
  final String id;
  final Offset posNorm;

  const _FixTarget(this.id, this.posNorm);
}

class _FixationTargetDot extends StatelessWidget {
  final Offset target;
  final Size size;

  const _FixationTargetDot({
    required this.target,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: target.dx * size.width - 8,
      top: target.dy * size.height - 8,
      child: Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
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
            color: Colors.greenAccent.withValues(alpha: 0.6),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

class _ReadingPageCard extends StatelessWidget {
  final int pageNumber;
  final String text;

  const _ReadingPageCard({
    required this.pageNumber,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 820),
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reading Page $pageNumber / 3',
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
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
