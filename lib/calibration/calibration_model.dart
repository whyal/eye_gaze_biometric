import 'package:flutter/material.dart';

class CalibrationSample {
  final Offset raw;
  final Offset target;

  const CalibrationSample({
    required this.raw,
    required this.target,
  });
}

class CalibrationModel {
  final List<double> coeffsX; // 6 terms
  final List<double> coeffsY; // 6 terms

  const CalibrationModel({
    required this.coeffsX,
    required this.coeffsY,
  });

  Offset apply(Offset raw) {
    final f = _features(raw.dx, raw.dy);
    final x = _dot(coeffsX, f);
    final y = _dot(coeffsY, f);
    return Offset(x, y);
  }

  static CalibrationModel fromSamples(List<CalibrationSample> samples) {
    return CalibrationModel(
      coeffsX: _fitPolynomial(
        samples,
        (s) => s.target.dx,
      ),
      coeffsY: _fitPolynomial(
        samples,
        (s) => s.target.dy,
      ),
    );
  }

  static List<double> _features(double x, double y) {
    return [
      1.0,
      x,
      y,
      x * x,
      y * y,
      x * y,
    ];
  }

  static double _dot(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  static List<double> _fitPolynomial(
    List<CalibrationSample> samples,
    double Function(CalibrationSample) targetSelector,
  ) {
    if (samples.length < 6) {
      return [0, 1, 0, 0, 0, 0];
    }

    final m = List.generate(6, (_) => List.filled(6, 0.0));
    final b = List.filled(6, 0.0);

    for (final s in samples) {
      final f = _features(s.raw.dx, s.raw.dy);
      for (var i = 0; i < 6; i++) {
        b[i] += f[i] * targetSelector(s);
        for (var j = 0; j < 6; j++) {
          m[i][j] += f[i] * f[j];
        }
      }
    }

    return _solveLinearSystem(m, b);
  }

  static List<double> _solveLinearSystem(
    List<List<double>> a,
    List<double> b,
  ) {
    final n = b.length;
    final m = List.generate(n, (i) => [...a[i], b[i]]);

    for (var i = 0; i < n; i++) {
      var maxRow = i;
      for (var k = i + 1; k < n; k++) {
        if (m[k][i].abs() > m[maxRow][i].abs()) {
          maxRow = k;
        }
      }
      final temp = m[i];
      m[i] = m[maxRow];
      m[maxRow] = temp;

      final pivot = m[i][i];
      if (pivot.abs() < 1e-12) {
        return [0, 1, 0, 0, 0, 0];
      }

      for (var j = i; j <= n; j++) {
        m[i][j] /= pivot;
      }

      for (var r = 0; r < n; r++) {
        if (r == i) continue;
        final factor = m[r][i];
        for (var c = i; c <= n; c++) {
          m[r][c] -= factor * m[i][c];
        }
      }
    }

    return List.generate(n, (i) => m[i][n]);
  }
}
