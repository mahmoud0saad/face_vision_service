import '../entities/detected_face.dart';

/// Assigns stable IDs to detected faces across multiple analyze calls.
///
/// Uses IoU (Intersection over Union) on bounding boxes for matching.
/// Tracks are removed after [maxMissedFrames] consecutive misses.
class FaceTracker {
  FaceTracker({this.iouThreshold = 0.3, this.maxMissedFrames = 3});

  final double iouThreshold;
  final int maxMissedFrames;

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
      result[pair.faceIdx] = _withId(rawFaces[pair.faceIdx], track.id);
    }

    // Unmatched faces get new IDs
    for (var fi = 0; fi < rawFaces.length; fi++) {
      if (matched[fi]) continue;
      final id = _nextId++;
      _tracks.add(_Track(id: id, face: rawFaces[fi]));
      result[fi] = _withId(rawFaces[fi], id);
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

  DetectedFace _withId(DetectedFace f, int id) => DetectedFace(
        id: id,
        x: f.x,
        y: f.y,
        width: f.width,
        height: f.height,
        genderLabel: f.genderLabel,
        ageLabel: f.ageLabel,
        detectionScore: f.detectionScore,
        leftEyeState: f.leftEyeState,
        rightEyeState: f.rightEyeState,
      );
}

class _Track {
  _Track({required this.id, required this.face});

  final int id;
  DetectedFace face;
  int missed = 0;
}

class _IouPair {
  _IouPair(this.trackIdx, this.faceIdx, this.iou);

  final int trackIdx;
  final int faceIdx;
  final double iou;
}
