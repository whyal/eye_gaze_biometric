import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class EyeTrackingChannel {
  static const _channel = MethodChannel('eye_tracking');

  static StreamController<Offset> _gazeStream =
      StreamController.broadcast();
  static final ValueNotifier<int> gazeEventCount = ValueNotifier<int>(0);
  static final ValueNotifier<int?> lastGazeMs =
      ValueNotifier<int?>(null);

  static Stream<Offset> get gazeStream => _gazeStream.stream;

  static void initialize() {
    if (_gazeStream.isClosed) {
      _gazeStream = StreamController.broadcast();
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'gaze') {
        final x = call.arguments['x'] as double;
        final y = call.arguments['y'] as double;
        _gazeStream.add(Offset(x, y));
        gazeEventCount.value += 1;
        lastGazeMs.value = DateTime.now().millisecondsSinceEpoch;
      }
    });

    _channel.invokeMethod('start');
  }

  static void dispose() {
    _channel.invokeMethod('stop');
  }
}
