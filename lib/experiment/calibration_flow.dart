import 'dart:async';
import 'package:flutter/material.dart';
import '../calibration/calibration_model.dart';
import '../calibration/calibration_screen.dart';
import '../eye_tracking/eye_tracking_channel.dart';
import '../logging/gaze_jsonl_logger.dart';
import '../participant/participant_entry_screen.dart';
import 'gaze_demo_screen.dart';

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
