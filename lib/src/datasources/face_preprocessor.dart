import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../entities/gender_pipeline_config.dart';

/// Lightweight, configurable lighting preprocessing for the gender crop.
///
/// Operates only on the small face crop (not the full frame) to keep the added
/// latency negligible. Intermediate `Mat`s are disposed eagerly and the gamma
/// LUT and CLAHE instances are cached/reused across frames to avoid per-frame
/// allocations.
///
/// Each step is gated independently by [GenderPipelineConfig] so techniques can
/// be enabled or disabled in isolation for A/B testing. [process] always
/// returns a NEW `Mat` (the caller owns and must dispose it); the input is
/// never mutated or disposed.
class FacePreprocessor {
  cv.Mat? _gammaLut;
  double? _gammaLutFor;

  cv.CLAHE? _clahe;
  double? _claheClipFor;
  int? _claheTileFor;

  /// Returns a preprocessed copy of [bgr] according to [cfg].
  cv.Mat process(cv.Mat bgr, GenderPipelineConfig cfg) {
    if (!cfg.preprocessEnabled) return bgr.clone();

    var result = bgr.clone();

    if (cfg.gammaEnabled && _meanLuma(result) < cfg.gammaDarkThreshold) {
      result = _replace(result, _applyGamma(result, cfg.gamma));
    }

    if (cfg.claheEnabled) {
      result = _replace(result, _applyClahe(result, cfg));
    }

    if (cfg.autoContrastEnabled) {
      result = _replace(result, _applyAutoContrast(result));
    }

    return result;
  }

  /// Disposes the original [previous] mat and returns [next].
  cv.Mat _replace(cv.Mat previous, cv.Mat next) {
    previous.dispose();
    return next;
  }

  double _meanLuma(cv.Mat bgr) {
    final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
    final mean = gray.mean().val1;
    gray.dispose();
    return mean;
  }

  cv.Mat _applyGamma(cv.Mat bgr, double gamma) {
    final lut = _gammaLutFor == gamma && _gammaLut != null
        ? _gammaLut!
        : _buildGammaLut(gamma);
    return cv.LUT(bgr, lut);
  }

  cv.Mat _buildGammaLut(double gamma) {
    // out = 255 * (in/255)^(1/gamma); gamma > 1 brightens mid-tones.
    final safeGamma = gamma <= 0 ? 1.0 : gamma;
    final inv = 1.0 / safeGamma;
    final table = List<int>.generate(256, (i) {
      final v = (math.pow(i / 255.0, inv) * 255.0).round();
      return v.clamp(0, 255);
    });
    _gammaLut?.dispose();
    _gammaLut = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, table);
    _gammaLutFor = gamma;
    return _gammaLut!;
  }

  cv.Mat _applyClahe(cv.Mat bgr, GenderPipelineConfig cfg) {
    final clahe = _claheClipFor == cfg.claheClipLimit &&
            _claheTileFor == cfg.claheTileGrid &&
            _clahe != null
        ? _clahe!
        : _buildClahe(cfg);

    final ycrcb = cv.cvtColor(bgr, cv.COLOR_BGR2YCrCb);
    // split() returns a read-only VecMat whose elements are non-owning views;
    // dispose the VecMat as a whole, and the separately-allocated mats below.
    final channels = cv.split(ycrcb);
    ycrcb.dispose();

    cv.Mat? equalized;
    cv.VecMat? mergedVec;
    cv.Mat? mergedYcrcb;
    try {
      equalized = clahe.apply(channels[0]);
      mergedVec = cv.VecMat.fromList([equalized, channels[1], channels[2]]);
      mergedYcrcb = cv.merge(mergedVec);
      return cv.cvtColor(mergedYcrcb, cv.COLOR_YCrCb2BGR);
    } finally {
      mergedYcrcb?.dispose();
      mergedVec?.dispose();
      equalized?.dispose();
      channels.dispose();
    }
  }

  cv.CLAHE _buildClahe(GenderPipelineConfig cfg) {
    _clahe?.dispose();
    _clahe = cv.CLAHE.create(
      cfg.claheClipLimit,
      (cfg.claheTileGrid, cfg.claheTileGrid),
    );
    _claheClipFor = cfg.claheClipLimit;
    _claheTileFor = cfg.claheTileGrid;
    return _clahe!;
  }

  cv.Mat _applyAutoContrast(cv.Mat bgr) {
    final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
    final (minVal, maxVal, _, __) = cv.minMaxLoc(gray);
    gray.dispose();

    final range = maxVal - minVal;
    if (range <= 1) return bgr.clone();

    // Stretch [min,max] -> [0,255]: out = (in - min) * 255/range.
    final alpha = 255.0 / range;
    final beta = -minVal * alpha;
    return cv.convertScaleAbs(bgr, alpha: alpha, beta: beta);
  }

  void dispose() {
    _gammaLut?.dispose();
    _gammaLut = null;
    _gammaLutFor = null;
    _clahe?.dispose();
    _clahe = null;
    _claheClipFor = null;
    _claheTileFor = null;
  }
}
