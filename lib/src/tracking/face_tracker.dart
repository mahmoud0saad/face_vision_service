import '../entities/detected_face.dart';
import '../vision_constants.dart';

/// Assigns stable IDs to detected faces across multiple analyze calls.
///
/// Uses IoU (Intersection over Union) on bounding boxes for matching.
/// Tracks are removed after [maxMissedFrames] consecutive misses.
/// Gender and age labels lock after [labelConfirmFrames] consecutive agrees.
class FaceTracker {
  FaceTracker({
    this.iouThreshold = 0.3,
    this.maxMissedFrames = 15,
    this.labelConfirmFrames = kLabelConfirmFrames,
  });

  final double iouThreshold;
  final int maxMissedFrames;
  final int labelConfirmFrames;

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
      final track = _Track(id: id, face: rawFaces[fi]);
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
  _Track({required this.id, required this.face});

  final int id;
  DetectedFace face;
  int missed = 0;

  String? confirmedGender;
  String? confirmedAge;
  String? pendingGender;
  int genderStreak = 0;
  String? pendingAge;
  int ageStreak = 0;

  void updateLabels(DetectedFace raw, int confirmFrames) {
    final gender = _advanceLabel(
      raw.genderLabel,
      confirmedGender,
      pendingGender,
      genderStreak,
      confirmFrames,
    );
    confirmedGender = gender.$1;
    pendingGender = gender.$2;
    genderStreak = gender.$3;

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

  DetectedFace toDetectedFace() => DetectedFace(
        id: id,
        x: face.x,
        y: face.y,
        width: face.width,
        height: face.height,
        genderLabel: confirmedGender ?? '',
        ageLabel: confirmedAge ?? '',
        detectionScore: face.detectionScore,
        leftEyeState: face.leftEyeState,
        rightEyeState: face.rightEyeState,
      );
}

class _IouPair {
  _IouPair(this.trackIdx, this.faceIdx, this.iou);

  final int trackIdx;
  final int faceIdx;
  final double iou;
}
