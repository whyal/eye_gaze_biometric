import 'package:flutter/material.dart';

class GazeDebugView extends StatelessWidget {
  final Offset? gaze;
  final Offset? mapped;
  final Size size;

  const GazeDebugView({
    super.key,
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
