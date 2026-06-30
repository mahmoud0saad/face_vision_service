import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../entities/detected_face.dart';
import '../entities/face_analysis_result.dart';
import '../entities/preview_frame.dart';
import '../live/face_vision_live_session.dart';

/// Builds the overlay label text shown above a detected face box.
typedef FaceLabelBuilder = String Function(DetectedFace face);

/// Drop-in widget that renders a [FaceVisionLiveSession]'s live camera feed and
/// draws the detected face boxes/labels on top.
///
/// It subscribes to [FaceVisionLiveSession.previewFrames] for the live image
/// and [FaceVisionLiveSession.results] for the face overlay, decoding raw BGR
/// frames into a [ui.Image] on the fly. Frames are dropped while a decode is in
/// flight to keep the UI responsive.
///
/// The widget tolerates the session being started/stopped after it is mounted:
/// it (re)subscribes automatically while [FaceVisionLiveSession.isRunning].
///
/// ```dart
/// FaceVisionLivePreview(session: mySession)
/// ```
class FaceVisionLivePreview extends StatefulWidget {
  const FaceVisionLivePreview({
    super.key,
    required this.session,
    this.showOverlay = true,
    this.showLabels = true,
    this.boxColor = const Color(0xFF69F0AE),
    this.fit = BoxFit.contain,
    this.labelBuilder,
    this.placeholder,
  });

  /// The live session to render. Must be (or become) started.
  final FaceVisionLiveSession session;

  /// Draw face boxes (and labels when [showLabels]) over the image.
  final bool showOverlay;

  /// Draw a text label above each face box.
  final bool showLabels;

  /// Stroke color for face boxes.
  final Color boxColor;

  /// How the camera image is fitted into the available space.
  /// Supports [BoxFit.contain] (default) and [BoxFit.cover].
  final BoxFit fit;

  /// Optional custom label text for each face.
  final FaceLabelBuilder? labelBuilder;

  /// Shown until the first preview frame is decoded.
  final Widget? placeholder;

  @override
  State<FaceVisionLivePreview> createState() => _FaceVisionLivePreviewState();
}

class _FaceVisionLivePreviewState extends State<FaceVisionLivePreview> {
  StreamSubscription<PreviewFrame>? _previewSub;
  StreamSubscription<FaceAnalysisResult>? _resultsSub;
  Timer? _lifecycleTimer;

  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  ui.Image? _image;
  List<DetectedFace> _faces = const [];
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    _ensureSubscribed();
    // Re-check subscription state periodically so the widget recovers from
    // session start/stop/restart cycles without the caller wiring callbacks.
    _lifecycleTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _syncSubscription(),
    );
  }

  @override
  void didUpdateWidget(covariant FaceVisionLivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _unsubscribe();
      _clearImage();
      _faces = const [];
      _ensureSubscribed();
    }
  }

  void _syncSubscription() {
    if (widget.session.isRunning) {
      _ensureSubscribed();
    } else if (_previewSub != null || _resultsSub != null) {
      _unsubscribe();
      _clearImage();
      _faces = const [];
      _repaint.value++;
    }
  }

  void _ensureSubscribed() {
    if (!widget.session.isRunning || _previewSub != null) return;
    try {
      _previewSub = widget.session.previewFrames.listen(
        _onPreviewFrame,
        onDone: _onStreamDone,
      );
      _resultsSub = widget.session.results.listen(
        _onResult,
        onError: (_) {},
      );
    } catch (_) {
      // Streams not ready yet (start in progress); the lifecycle timer retries.
      _previewSub = null;
      _resultsSub = null;
    }
  }

  void _onStreamDone() {
    _unsubscribe();
    _clearImage();
    _faces = const [];
    _repaint.value++;
  }

  void _unsubscribe() {
    _previewSub?.cancel();
    _previewSub = null;
    _resultsSub?.cancel();
    _resultsSub = null;
  }

  void _onPreviewFrame(PreviewFrame frame) {
    if (_decoding) return;
    _decoding = true;

    final rgba = _bgrToRgba(frame.bgrBytes, frame.width, frame.height);
    ui.decodeImageFromPixels(
      rgba,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (image) {
        _decoding = false;
        if (!mounted) {
          image.dispose();
          return;
        }
        _image?.dispose();
        _image = image;
        _repaint.value++;
      },
    );
  }

  void _onResult(FaceAnalysisResult result) {
    _faces = result.faces;
    _repaint.value++;
  }

  void _clearImage() {
    _image?.dispose();
    _image = null;
  }

  @override
  void dispose() {
    _lifecycleTimer?.cancel();
    _unsubscribe();
    _clearImage();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _repaint,
        builder: (context, _) {
          final image = _image;
          if (image == null) {
            return widget.placeholder ??
                const Center(child: CircularProgressIndicator());
          }
          return ClipRect(
            child: SizedBox.expand(
              child: CustomPaint(
                painter: _LivePreviewPainter(
                  image: image,
                  faces: widget.showOverlay ? _faces : const [],
                  showLabels: widget.showLabels,
                  boxColor: widget.boxColor,
                  fit: widget.fit,
                  labelBuilder: widget.labelBuilder ?? _defaultLabel,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _defaultLabel(DetectedFace f) {
    final parts = <String>['#${f.id}'];
    if (f.genderLabel.isNotEmpty) parts.add(f.genderLabel);
    if (f.ageLabel.isNotEmpty) parts.add(f.ageLabel);
    return parts.join(' ');
  }

  static Uint8List _bgrToRgba(Uint8List bgr, int width, int height) {
    final pixelCount = width * height;
    final rgba = Uint8List(pixelCount * 4);
    var si = 0;
    var di = 0;
    for (var i = 0; i < pixelCount; i++) {
      final b = bgr[si];
      final g = bgr[si + 1];
      final r = bgr[si + 2];
      rgba[di] = r;
      rgba[di + 1] = g;
      rgba[di + 2] = b;
      rgba[di + 3] = 255;
      si += 3;
      di += 4;
    }
    return rgba;
  }
}

class _LivePreviewPainter extends CustomPainter {
  _LivePreviewPainter({
    required this.image,
    required this.faces,
    required this.showLabels,
    required this.boxColor,
    required this.fit,
    required this.labelBuilder,
  });

  final ui.Image image;
  final List<DetectedFace> faces;
  final bool showLabels;
  final Color boxColor;
  final BoxFit fit;
  final FaceLabelBuilder labelBuilder;

  @override
  void paint(Canvas canvas, Size size) {
    if (image.width == 0 || image.height == 0) return;

    final content = Size(image.width.toDouble(), image.height.toDouble());
    final dst = _fittedRect(content, size);

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, content.width, content.height),
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );

    final scaleX = dst.width / content.width;
    final scaleY = dst.height / content.height;
    for (final face in faces) {
      _drawFace(canvas, size, face, dst.left, dst.top, scaleX, scaleY);
    }
  }

  Rect _fittedRect(Size content, Size container) {
    final scaleW = container.width / content.width;
    final scaleH = container.height / content.height;
    final double s;
    switch (fit) {
      case BoxFit.cover:
        s = scaleW > scaleH ? scaleW : scaleH;
        break;
      case BoxFit.fill:
        return Rect.fromLTWH(0, 0, container.width, container.height);
      case BoxFit.contain:
      default:
        s = scaleW < scaleH ? scaleW : scaleH;
        break;
    }
    final w = content.width * s;
    final h = content.height * s;
    return Rect.fromLTWH(
      (container.width - w) / 2,
      (container.height - h) / 2,
      w,
      h,
    );
  }

  void _drawFace(
    Canvas canvas,
    Size size,
    DetectedFace face,
    double offsetX,
    double offsetY,
    double scaleX,
    double scaleY,
  ) {
    final rect = Rect.fromLTWH(
      offsetX + face.x * scaleX,
      offsetY + face.y * scaleY,
      face.width * scaleX,
      face.height * scaleY,
    );

    canvas.drawRect(
      rect,
      Paint()
        ..color = boxColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (!showLabels) return;

    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final textPainter = TextPainter(
      text: TextSpan(
        text: labelBuilder(face),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelWidth = textPainter.width + padding.horizontal;
    final labelHeight = textPainter.height + padding.vertical;
    final labelX = rect.left
        .clamp(0.0, (size.width - labelWidth).clamp(0.0, double.infinity));
    final labelY = (rect.top - labelHeight - 4).clamp(0.0, double.infinity);
    final labelRect = Rect.fromLTWH(labelX, labelY, labelWidth, labelHeight);

    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      Paint()..color = const Color(0xCC000000),
    );

    textPainter.paint(
      canvas,
      Offset(labelX + padding.left, labelY + padding.top),
    );
  }

  @override
  bool shouldRepaint(covariant _LivePreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.faces != faces ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.boxColor != boxColor ||
        oldDelegate.fit != fit;
  }
}
