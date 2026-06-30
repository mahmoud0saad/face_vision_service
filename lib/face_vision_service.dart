/// Portable face vision analysis service.
///
/// Runs OpenCV face detection, age/gender classification, and eye state
/// analysis in an isolate. Provides stable face IDs via IoU-based tracking.
library face_vision_service;

export 'src/bundled_models.dart';
export 'src/entities/detected_face.dart';
export 'src/entities/face_analysis_result.dart';
export 'src/entities/preview_frame.dart';
export 'src/entities/raw_image.dart';
export 'src/entities/vision_detection_config.dart';
export 'src/isolate/service_client.dart';
export 'src/live/face_vision_live_session.dart';
export 'src/tracking/face_tracker.dart';
export 'src/widgets/face_vision_live_preview.dart';
