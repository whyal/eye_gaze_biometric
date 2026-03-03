import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../eye_tracking/eye_tracking_channel.dart';

class ParticipantSessionInfo {
  final bool participantExists;
  final int existingSessionCount;

  const ParticipantSessionInfo({
    required this.participantExists,
    required this.existingSessionCount,
  });
}

class GazeJsonlLogger {
  GazeJsonlLogger._();
  static final GazeJsonlLogger instance = GazeJsonlLogger._();

  IOSink? _samplesSink;
  IOSink? _eventsSink;
  String? _sessionDirPath;
  String? _samplesFilePath;
  String? _eventsFilePath;
  String _sessionId = '';
  String _participantId = 'UNKNOWN';
  String _taskId = 'default_task';
  Stopwatch? _sessionClock;

  String? get samplesFilePath => _samplesFilePath;
  String? get eventsFilePath => _eventsFilePath;
  String? get sessionDirPath => _sessionDirPath;
  String get sessionId => _sessionId;
  String get participantId => _participantId;

  Future<String> getLogDirectoryPath() async {
    final baseDir = await getApplicationDocumentsDirectory();
    return '${baseDir.path}/sessions';
  }

  Future<ParticipantSessionInfo> getParticipantSessionInfo(
    String participantId,
  ) async {
    final root = Directory(await getLogDirectoryPath());
    final participantDir =
        Directory('${root.path}/${_sanitize(participantId)}');
    if (!participantDir.existsSync()) {
      return const ParticipantSessionInfo(
        participantExists: false,
        existingSessionCount: 0,
      );
    }
    final count = participantDir
        .listSync()
        .whereType<Directory>()
        .length;
    return ParticipantSessionInfo(
      participantExists: true,
      existingSessionCount: count,
    );
  }

  Future<void> startSession({
    required String participantId,
    String taskId = 'default_task',
    int? visitId,
    int? sessionInVisit,
    String calibrationVersion = 'v1',
    String fixationPatternId = '9pt_perm_v1',
    String schemaVersion = '1.0',
  }) async {
    if (_samplesSink != null || _eventsSink != null) return;
    final outDir = Directory(await getLogDirectoryPath());
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    final participantDir =
        Directory('${outDir.path}/${_sanitize(participantId)}');
    final participantInfo =
        await getParticipantSessionInfo(participantId);
    if (!participantDir.existsSync()) {
      participantDir.createSync(recursive: true);
    }
    final now = DateTime.now();
    final existingSessionIds = _listSessionIds(participantDir);
    final inferredVisitId = _inferVisitId(
      existingSessionIds: existingSessionIds,
      now: now,
    );
    final inferredSessionInVisit = _inferSessionInVisit(
      existingSessionIds: existingSessionIds,
      now: now,
    );
    _sessionId = _buildSessionId(now);
    _participantId = participantId;
    _taskId = taskId;
    _sessionDirPath = '${participantDir.path}/$_sessionId';
    Directory(_sessionDirPath!).createSync(recursive: true);
    _samplesFilePath = '$_sessionDirPath/samples.jsonl';
    _eventsFilePath = '$_sessionDirPath/events.jsonl';
    _samplesSink = File(_samplesFilePath!).openWrite(mode: FileMode.append);
    _eventsSink = File(_eventsFilePath!).openWrite(mode: FileMode.append);
    _sessionClock = Stopwatch()..start();
    debugPrint('Gaze JSONL samples file: $_samplesFilePath');
    debugPrint('Gaze JSONL events file: $_eventsFilePath');
    await _writeSessionMeta(
      schemaVersion: schemaVersion,
      sessionStartLocal: now,
      visitId: visitId ?? inferredVisitId,
      sessionInVisit: sessionInVisit ?? inferredSessionInVisit,
      calibrationVersion: calibrationVersion,
      fixationPatternId: fixationPatternId,
      participantExists: participantInfo.participantExists,
    );
    logEvent(event: 'session_start');
  }

  Future<void> stopSession() async {
    if (_samplesSink == null || _eventsSink == null) return;
    logEvent(event: 'session_end');
    await _samplesSink!.flush();
    await _eventsSink!.flush();
    await _samplesSink!.close();
    await _eventsSink!.close();
    debugPrint('Gaze JSONL session closed: $_sessionDirPath');
    _samplesSink = null;
    _eventsSink = null;
    _sessionClock = null;
  }

  void logEvent({
    required String event,
    Map<String, dynamic>? payload,
  }) {
    final base = <String, dynamic>{
      't': _elapsedSec(),
      'type': event,
    };
    if (payload != null) {
      base.addAll(payload);
    }
    _writeEvent(base);
  }

  void logFrame({
    required EyeTrackingSample sample,
    Offset? calibratedNorm,
    required bool isCalibration,
  }) {
    final tSec = _elapsedSec();
    final gaze = calibratedNorm ?? sample.gazeNorm;
    _writeSample({
      't': tSec,
      'eyeL': [
        sample.leftEyeDirCameraXY.dx,
        sample.leftEyeDirCameraXY.dy,
        sample.leftEyeDirCameraZ,
      ],
      'eyeR': [
        sample.rightEyeDirCameraXY.dx,
        sample.rightEyeDirCameraXY.dy,
        sample.rightEyeDirCameraZ,
      ],
      'head': {
        'yaw': sample.headYawRad,
        'pitch': sample.headPitchRad,
        'z': sample.headTranslationZM,
      },
      'blinkL': sample.eyeBlinkLeft,
      'blinkR': sample.eyeBlinkRight,
      'tracking': sample.trackingState,
      'gx': gaze.dx,
      'gy': gaze.dy,
      'is_calibration': isCalibration,
    });
  }

  void _writeSample(Map<String, dynamic> row) {
    if (_samplesSink == null) return;
    _samplesSink!.writeln(jsonEncode(row));
  }

  void _writeEvent(Map<String, dynamic> row) {
    if (_eventsSink == null) return;
    _eventsSink!.writeln(jsonEncode(row));
  }

  double _elapsedSec() {
    final sw = _sessionClock;
    if (sw == null) return 0.0;
    return sw.elapsedMicroseconds / 1e6;
  }

  String _buildSessionId(DateTime localNow) {
    final y = localNow.year.toString().padLeft(4, '0');
    final m = localNow.month.toString().padLeft(2, '0');
    final d = localNow.day.toString().padLeft(2, '0');
    final hh = localNow.hour.toString().padLeft(2, '0');
    final mm = localNow.minute.toString().padLeft(2, '0');
    final ss = localNow.second.toString().padLeft(2, '0');
    final suffix = _randomCode(4);
    return '$y$m${d}_$hh$mm${ss}_$suffix';
  }

  List<String> _listSessionIds(Directory participantDir) {
    if (!participantDir.existsSync()) return const [];
    return participantDir
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .toList();
  }

  int _inferVisitId({
    required List<String> existingSessionIds,
    required DateTime now,
  }) {
    final uniqueDates = <String>{};
    for (final id in existingSessionIds) {
      final date = _datePrefixFromSessionId(id);
      if (date != null) uniqueDates.add(date);
    }
    final today = _datePrefix(now);
    if (!uniqueDates.contains(today)) {
      return uniqueDates.length + 1;
    }
    final sorted = uniqueDates.toList()..sort();
    return sorted.indexOf(today) + 1;
  }

  int _inferSessionInVisit({
    required List<String> existingSessionIds,
    required DateTime now,
  }) {
    final today = _datePrefix(now);
    final todayCount = existingSessionIds
        .where((id) => _datePrefixFromSessionId(id) == today)
        .length;
    return todayCount + 1;
  }

  String _datePrefix(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  String? _datePrefixFromSessionId(String id) {
    if (id.length < 8) return null;
    final date = id.substring(0, 8);
    if (!RegExp(r'^\d{8}$').hasMatch(date)) return null;
    return date;
  }

  String _randomCode(int len) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final out = StringBuffer();
    for (var i = 0; i < len; i++) {
      out.write(chars[r.nextInt(chars.length)]);
    }
    return out.toString();
  }

  String _formatLocalIso(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    final offset = dt.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final offH = two(abs.inHours);
    final offM = two(abs.inMinutes.remainder(60));
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${two(dt.month)}-${two(dt.day)}T${two(dt.hour)}:'
        '${two(dt.minute)}:${two(dt.second)}$sign$offH:$offM';
  }

  String _sanitize(String raw) {
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  Future<void> _writeSessionMeta({
    required String schemaVersion,
    required DateTime sessionStartLocal,
    int? visitId,
    int? sessionInVisit,
    required String calibrationVersion,
    required String fixationPatternId,
    required bool participantExists,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final devicePayload = await _deviceInfoPayload();
    final deviceSeed = await _getOrCreateDeviceSeed();
    final deviceIdHash = sha256
        .convert(utf8.encode(deviceSeed))
        .toString();

    final meta = <String, dynamic>{
      'schema_version': schemaVersion,
      'participant_id': _participantId,
      'session_id': _sessionId,
      'session_start_local': _formatLocalIso(sessionStartLocal),
      'visit_id': visitId,
      'session_in_visit': sessionInVisit,
      'participant_exists': participantExists,
      'device_id_hash': deviceIdHash,
      'task_id': _taskId,
      'app_version': packageInfo.version,
      'app_build': packageInfo.buildNumber,
      'calibration_version': calibrationVersion,
      'fixation_pattern_id': fixationPatternId,
      'device_info': {
        'platform': devicePayload['platform'],
        'model': devicePayload['model'],
        'system_name': devicePayload['system_name'],
        'system_version': devicePayload['system_version'],
      },
    };

    final file = File('$_sessionDirPath/session_meta.json');
    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(meta));
    debugPrint('Gaze JSONL session meta file: ${file.path}');
  }

  Future<Map<String, dynamic>> _deviceInfoPayload() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return {
        'platform': 'ios',
        'model': info.utsname.machine,
        'system_name': info.systemName,
        'system_version': info.systemVersion,
      };
    }
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return {
        'platform': 'android',
        'model': '${info.manufacturer} ${info.model}',
        'system_name': 'android',
        'system_version': info.version.release,
      };
    }
    return {
      'platform': Platform.operatingSystem,
      'model': 'unknown',
      'system_name': Platform.operatingSystem,
      'system_version': Platform.operatingSystemVersion,
    };
  }

  Future<String> _getOrCreateDeviceSeed() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final seedFile = File('${baseDir.path}/.device_seed');
    if (seedFile.existsSync()) {
      return seedFile.readAsStringSync();
    }
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final seed = base64UrlEncode(bytes);
    seedFile.writeAsStringSync(seed, flush: true);
    return seed;
  }
}
