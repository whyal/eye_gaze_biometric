import 'package:flutter/material.dart';

class FixTarget {
  final String id;
  final Offset posNorm;

  const FixTarget(this.id, this.posNorm);
}

class FixationTargetDot extends StatelessWidget {
  final Offset target;
  final Size size;

  const FixationTargetDot({
    super.key,
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

class GazeDot extends StatelessWidget {
  const GazeDot({super.key});

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
