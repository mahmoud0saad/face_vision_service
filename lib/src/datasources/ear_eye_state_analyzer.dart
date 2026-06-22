import 'dart:math';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../vision_constants.dart';
import 'eye_roi_geometry.dart';

/// Estimates open/closed per eye using Eye Aspect Ratio (EAR) from eyelid edges.
class EarEyeStateAnalyzer {
  (String left, String right) analyze(
    cv.Mat frame,
    int fx,
    int fy,
    int fw,
    int fh,
  ) {
    final left = _classifyEye(frame, fx, fy, fw, fh, isLeft: true);
    final right = _classifyEye(frame, fx, fy, fw, fh, isLeft: false);
    return (left, right);
  }

  String _classifyEye(
    cv.Mat frame,
    int fx,
    int fy,
    int fw,
    int fh, {
    required bool isLeft,
  }) {
    final rect = eyeRectFromFaceBox(
      frame.cols,
      frame.rows,
      fx,
      fy,
      fw,
      fh,
      isLeft: isLeft,
    );
    if (rect == null) return 'unknown';

    final roi = frame.region(rect);
    try {
      final ear = _computeEar(roi);
      if (ear < 0) return 'unknown';
      return ear >= kEarOpenThreshold ? 'open' : 'closed';
    } finally {
      roi.dispose();
    }
  }

  double _computeEar(cv.Mat bgrRoi) {
    final w = bgrRoi.cols;
    final h = bgrRoi.rows;
    if (w < kMinEyeCropSize || h < kMinEyeCropSize) return -1;

    final gray = cv.cvtColor(bgrRoi, cv.COLOR_BGR2GRAY);
    final blurred = cv.gaussianBlur(
      gray,
      (kEarBlurKernel, kEarBlurKernel),
      0,
    );
    gray.dispose();

    final edges = cv.sobel(
      blurred,
      cv.MatType.CV_64F,
      0,
      1,
      ksize: 3,
    );
    blurred.dispose();

    try {
      final magnitudes = _collectEdgeMagnitudes(edges);
      if (magnitudes.isEmpty) return -1;

      magnitudes.sort();
      final edgeThreshold = magnitudes[
          ((magnitudes.length - 1) * kEarEdgeQuantile).round().clamp(
            0,
            magnitudes.length - 1,
          )];
      if (edgeThreshold <= 0) return -1;

      final xLeft = 0;
      final xThird = (w / 3).floor().clamp(0, w - 1);
      final xTwoThirds = ((2 * w) / 3).floor().clamp(0, w - 1);
      final xRight = w - 1;

      final upperLeft = _eyelidRow(edges, xLeft, h, isUpper: true);
      final lowerLeft = _eyelidRow(edges, xLeft, h, isUpper: false);
      final upperThird = _eyelidRow(edges, xThird, h, isUpper: true);
      final lowerThird = _eyelidRow(edges, xThird, h, isUpper: false);
      final upperTwoThirds = _eyelidRow(edges, xTwoThirds, h, isUpper: true);
      final lowerTwoThirds = _eyelidRow(edges, xTwoThirds, h, isUpper: false);
      final upperRight = _eyelidRow(edges, xRight, h, isUpper: true);
      final lowerRight = _eyelidRow(edges, xRight, h, isUpper: false);

      final samples = [
        upperLeft,
        lowerLeft,
        upperThird,
        lowerThird,
        upperTwoThirds,
        lowerTwoThirds,
        upperRight,
        lowerRight,
      ];
      if (samples.any((s) => s.$1 < edgeThreshold)) return -1;

      final p1y = (upperLeft.$2 + lowerLeft.$2) / 2;
      final p4y = (upperRight.$2 + lowerRight.$2) / 2;
      final p1 = (xLeft.toDouble(), p1y);
      final p2 = (xThird.toDouble(), upperThird.$2);
      final p3 = (xTwoThirds.toDouble(), upperTwoThirds.$2);
      final p4 = (xRight.toDouble(), p4y);
      final p5 = (xTwoThirds.toDouble(), lowerTwoThirds.$2);
      final p6 = (xThird.toDouble(), lowerThird.$2);

      final a = _dist(p2.$1, p2.$2, p6.$1, p6.$2);
      final b = _dist(p3.$1, p3.$2, p5.$1, p5.$2);
      final c = _dist(p1.$1, p1.$2, p4.$1, p4.$2);
      if (c <= 0 || !a.isFinite || !b.isFinite) return -1;

      final ear = (a + b) / (2 * c);
      if (!ear.isFinite || ear <= 0) return -1;
      return ear;
    } finally {
      edges.dispose();
    }
  }

  List<double> _collectEdgeMagnitudes(cv.Mat edges) {
    final values = <double>[];
    for (var row = 0; row < edges.rows; row++) {
      for (var col = 0; col < edges.cols; col++) {
        final v = edges.atNum(row, col).abs().toDouble();
        if (v.isFinite && v > 0) values.add(v);
      }
    }
    return values;
  }

  (double strength, double row) _eyelidRow(
    cv.Mat edges,
    int col,
    int height, {
    required bool isUpper,
  }) {
    final mid = height ~/ 2;
    final start = isUpper ? 0 : mid;
    final end = isUpper ? mid : height;

    var bestStrength = 0.0;
    var bestRow = start.toDouble();
    for (var row = start; row < end; row++) {
      final strength = edges.atNum(row, col).abs().toDouble();
      if (strength > bestStrength) {
        bestStrength = strength;
        bestRow = row.toDouble();
      }
    }
    return (bestStrength, bestRow);
  }

  double _dist(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return sqrt(dx * dx + dy * dy);
  }
}
