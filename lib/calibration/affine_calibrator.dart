import 'dart:math';
class AffineCalibrator {
  bool calibrated = false;
  late double a, b, c, d, e, f;

  void calibrate(
    List<Point<double>> raw,
    List<Point<double>> screen,
  ) {
    final A = <List<double>>[];
    final B = <double>[];

    for (int i = 0; i < raw.length; i++) {
      A.add([raw[i].x, raw[i].y, 1, 0, 0, 0]);
      A.add([0, 0, 0, raw[i].x, raw[i].y, 1]);
      B.add(screen[i].x);
      B.add(screen[i].y);
    }

    final x = _solve(A, B);
    a = x[0]; b = x[1]; c = x[2];
    d = x[3]; e = x[4]; f = x[5];
    calibrated = true;
  }
  Point<double> apply(Point<double> p) {
    if (!calibrated) return p;
    return Point(
      a * p.x + b * p.y + c,
      d * p.x + e * p.y + f,
    );
  }

  List<double> _solve(List<List<double>> A, List<double> B) {
    final n = A[0].length;
    final AtA = List.generate(n, (_) => List.filled(n, 0.0));
    final AtB = List.filled(n, 0.0);

    for (int i = 0; i < A.length; i++) {
      for (int j = 0; j < n; j++) {
        AtB[j] += A[i][j] * B[i];
        for (int k = 0; k < n; k++) {
          AtA[j][k] += A[i][j] * A[i][k];
        }
      }
    }
    return _gauss(AtA, AtB);
  }

  List<double> _gauss(List<List<double>> A, List<double> B) {
    final n = B.length;
    for (int i = 0; i < n; i++) {
      int max = i;
      for (int k = i + 1; k < n; k++) {
        if (A[k][i].abs() > A[max][i].abs()) max = k;
      }
      final tmpA = A[i]; A[i] = A[max]; A[max] = tmpA;
      final tmpB = B[i]; B[i] = B[max]; B[max] = tmpB;

      for (int k = i + 1; k < n; k++) {
        final f = A[k][i] / A[i][i];
        for (int j = i; j < n; j++) {
          A[k][j] -= f * A[i][j];
        }
        B[k] -= f * B[i];
      }
    }
    final x = List.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      x[i] = B[i];
      for (int j = i + 1; j < n; j++) {
        x[i] -= A[i][j] * x[j];
      }
      x[i] /= A[i][i];
    }
    return x;
  }
}