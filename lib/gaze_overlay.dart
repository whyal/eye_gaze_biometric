import 'package:flutter/material.dart';

class GazeOverlay extends StatelessWidget {
  final Offset gaze;

  const GazeOverlay(this.gaze, {super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: gaze.dx - 10,
      top: gaze.dy - 10,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.redAccent.withOpacity(0.7),
        ),
      ),
    );
  }
}
