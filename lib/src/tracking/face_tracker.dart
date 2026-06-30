import 'dart:math' as math;

import '../entities/detected_face.dart';
import '../vision_constants.dart';

/// Assigns stable IDs to detected faces across multiple analyze calls.
///
/// Uses IoU (Intersection over Union) on bounding boxes for matching.
/// Tracks are removed after [maxMissedFrames] consecutive misses.
///
/// Age labels lock after [labelConfirmFrames] consecutive agrees. Gender is
/// instead stabilized by averaging the model's per-frame male-probability over
/// a short [smoothingWindow] history per track; the displayed label is always a
/// concrete `M`/`F` (the smoothed confidence is surfaced on the face as
/// metadata). A track's gender history is discarded with the track when it
/// disappears.
class FaceTracker {
  FaceTracker({
    this.iouThreshold = 0.3,
    this.maxMissedFrames = 15,
    this.labelConfirmFrames = kLabelConfirmFrames,
    this.smoothingWindow = kGenderSmoothingWindow,
  });

  final double iouThreshold;
  final int maxMissedFrames;
  final int labelConfirmFrames;

  /// Number of recent per-frame male-probabilities averaged per track.
  final int smoothingWindow;

  int _nextId = 1;
  final List<_Track> _tracks = [];

  /// Assigns IDs to [rawFaces] (which have id=0) and returns new list with
  /// stable IDs filled in.
  List<DetectedFace> assign(List<DetectedFace> rawFaces) {
    if (rawFaces.isEmpty) {
      for (final t in _tracks) {
        t.missed++;
      }
      _tracks.removeWhere((t) => t.missed >= maxMissedFrames);
      return [];
    }

    final matched = List<bool>.filled(rawFaces.length, false);
    final trackMatched = List<bool>.filled(_tracks.length, false);
    final result = List<DetectedFace?>.filled(rawFaces.length, null);

    // Greedy match by best IoU
    final pairs = <_IouPair>[];
    for (var ti = 0; ti < _tracks.length; ti++) {
      for (var fi = 0; fi < rawFaces.length; fi++) {
        final iou = _computeIoU(_tracks[ti].face, rawFaces[fi]);
        if (iou >= iouThreshold) {
          pairs.add(_IouPair(ti, fi, iou));
        }
      }
    }
    pairs.sort((a, b) => b.iou.compareTo(a.iou));

    for (final pair in pairs) {
      if (trackMatched[pair.trackIdx] || matched[pair.faceIdx]) continue;
      trackMatched[pair.trackIdx] = true;
      matched[pair.faceIdx] = true;

      final track = _tracks[pair.trackIdx];
      track.missed = 0;
      track.face = rawFaces[pair.faceIdx];
      track.updateLabels(rawFaces[pair.faceIdx], labelConfirmFrames);
      result[pair.faceIdx] = track.toDetectedFace();
    }

    // Unmatched faces get new IDs
    for (var fi = 0; fi < rawFaces.length; fi++) {
      if (matched[fi]) continue;
      final id = _nextId++;
      final track =
          _Track(id: id, face: rawFaces[fi], smoothingWindow: smoothingWindow);
      track.updateLabels(rawFaces[fi], labelConfirmFrames);
      _tracks.add(track);
      result[fi] = track.toDetectedFace();
    }

    // Unmatched tracks accumulate misses
    for (var ti = 0; ti < trackMatched.length; ti++) {
      if (!trackMatched[ti]) _tracks[ti].missed++;
    }
    _tracks.removeWhere((t) => t.missed >= maxMissedFrames);

    return result.cast<DetectedFace>();
  }

  void reset() {
    _tracks.clear();
    _nextId = 1;
  }

  double _computeIoU(DetectedFace a, DetectedFace b) {
    final x1 = a.x > b.x ? a.x : b.x;
    final y1 = a.y > b.y ? a.y : b.y;
    final x2a = a.x + a.width;
    final x2b = b.x + b.width;
    final x2 = x2a < x2b ? x2a : x2b;
    final y2a = a.y + a.height;
    final y2b = b.y + b.height;
    final y2 = y2a < y2b ? y2a : y2b;

    if (x2 <= x1 || y2 <= y1) return 0.0;

    final intersection = (x2 - x1) * (y2 - y1);
    final areaA = a.width * a.height;
    final areaB = b.width * b.height;
    final union = areaA + areaB - intersection;
    if (union <= 0) return 0.0;
    return intersection / union;
  }
}

class _Track {
  _Track({
    required this.id,
    required this.face,
    required this.smoothingWindow,
  });

  final int id;
  DetectedFace face;
  int missed = 0;
  final int smoothingWindow;

  /// Ring buffer of recent per-frame male-probabilities for this track. Only
  /// frames where gender inference actually ran are pushed.
  final List<double> _maleProbs = [];

  String? confirmedAge;
  String? pendingAge;
  int ageStreak = 0;

  void updateLabels(DetectedFace raw, int confirmFrames) {
    // Gender: accumulate the per-frame probability for temporal smoothing.
    // genderConfidence == 0 means inference was skipped this frame (e.g. the
    // face was below the minimum size), so it is not counted.
    if (raw.genderConfidence > 0) {
      _maleProbs.add(raw.maleProbability);
      while (_maleProbs.length > smoothingWindow) {
        _maleProbs.removeAt(0);
      }
    }

    // Age keeps the existing consecutive-agreement confirmation.
    final age = _advanceLabel(
      raw.ageLabel,
      confirmedAge,
      pendingAge,
      ageStreak,
      confirmFrames,
    );
    confirmedAge = age.$1;
    pendingAge = age.$2;
    ageStreak = age.$3;
  }

  /// Smoothed gender as `(label, avgMaleProb, confidence)`.
  ///
  /// Averages the male-probability history and always reports a concrete `M`/
  /// `F` from the side of the 0.5 decision boundary the average falls on.
  /// `confidence` (distance from 0.5) is still surfaced as metadata so callers
  /// can apply their own filtering. Empty history yields `('', 0, 0)` (gender
  /// inference was skipped, e.g. face below the minimum size).
  (String, double, double) smoothedGender() {
    if (_maleProbs.isEmpty) return ('', 0.0, 0.0);
    var sum = 0.0;
    for (final p in _maleProbs) {
      sum += p;
    }
    final avg = sum / _maleProbs.length;
    final confidence = math.max(avg, 1.0 - avg);
    final label = avg >= 0.5 ? kGenderLabels[0] : kGenderLabels[1];
    return (label, avg, confidence);
  }

  (String?, String?, int) _advanceLabel(
    String raw,
    String? confirmed,
    String? pending,
    int streak,
    int confirmFrames,
  ) {
    if (confirmed != null) return (confirmed, pending, streak);
    if (raw == pending) {
      final next = streak + 1;
      if (next >= confirmFrames) return (raw, raw, next);
      return (null, raw, next);
    }
    return (null, raw, 1);
  }

  DetectedFace toDetectedFace() {
    final gender = smoothedGender();
    return DetectedFace(
      id: id,
      x: face.x,
      y: face.y,
      width: face.width,
      height: face.height,
      genderLabel: gender.$1,
      ageLabel: confirmedAge ?? '',
      detectionScore: face.detectionScore,
      leftEyeState: face.leftEyeState,
      rightEyeState: face.rightEyeState,
      maleProbability: gender.$2,
      genderConfidence: gender.$3,
    );
  }
}

class _IouPair {
  _IouPair(this.trackIdx, this.faceIdx, this.iou);

  final int trackIdx;
  final int faceIdx;
  final double iou;
}
