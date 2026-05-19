import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:get_thumbnail_video/src/image_format.dart';
import 'package:get_thumbnail_video/src/video_thumbnail_platform.dart';
import 'package:web/web.dart' as web;

// An error code value to error name Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorName = <int, String>{
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// An error code value to description Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorDescription = <int, String>{
  1: 'The user canceled the fetching of the video.',
  2: 'A network error occurred while fetching the video, despite having previously been available.',
  3: 'An error occurred while trying to decode the video, despite having previously been determined to be usable.',
  4: 'The video has been found to be unsuitable (missing or in a format not supported by your browser).',
};

// The default error message, when the error is an empty string
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/message
const String _kDefaultErrorMessage =
    'No further diagnostic information can be determined or provided.';

/// A web implementation of the VideoThumbnailPlatform of the VideoThumbnail plugin.
class VideoThumbnailWeb extends VideoThumbnailPlatform {
  /// Constructs a VideoThumbnailWeb
  VideoThumbnailWeb();

  static void registerWith(Registrar registrar) {
    VideoThumbnailPlatform.instance = VideoThumbnailWeb();
  }

  @override
  Future<XFile> thumbnailFile({
    required String video,
    required Map<String, String>? headers,
    required String? thumbnailPath,
    required ImageFormat imageFormat,
    required int maxHeight,
    required int maxWidth,
    required int timeMs,
    required int quality,
  }) async {
    final blob = await _createThumbnail(
      videoSrc: video,
      headers: headers,
      imageFormat: imageFormat,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      timeMs: timeMs,
      quality: quality,
    );

    return XFile(web.URL.createObjectURL(blob), mimeType: blob.type);
  }

  @override
  Future<Uint8List> thumbnailData({
    required String video,
    required Map<String, String>? headers,
    required ImageFormat imageFormat,
    required int maxHeight,
    required int maxWidth,
    required int timeMs,
    required int quality,
  }) async {
    final blob = await _createThumbnail(
      videoSrc: video,
      headers: headers,
      imageFormat: imageFormat,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      timeMs: timeMs,
      quality: quality,
    );
    final path = web.URL.createObjectURL(blob);
    final file = XFile(path, mimeType: blob.type);
    final bytes = await file.readAsBytes();
    web.URL.revokeObjectURL(path);

    return bytes;
  }

  Future<web.Blob> _createThumbnail({
    required String videoSrc,
    required Map<String, String>? headers,
    required ImageFormat imageFormat,
    required int maxHeight,
    required int maxWidth,
    required int timeMs,
    required int quality,
  }) async {
    final completer = Completer<web.Blob>();

    final video = web.document.createElement('video') as web.HTMLVideoElement;
    final timeSec = math.max(timeMs / 1000, 0).toDouble();
    final fetchVideo = headers != null && headers.isNotEmpty;

    video.onLoadedMetadata.listen((web.Event event) {
      video.currentTime = timeSec;

      if (fetchVideo) {
        web.URL.revokeObjectURL(video.src);
      }
    });

    video.onSeeked.listen((web.Event e) async {
      if (!completer.isCompleted) {
        final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
        final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;

        var localMaxWidth = maxWidth;
        var localMaxHeight = maxHeight;

        if (localMaxWidth == 0 && localMaxHeight == 0) {
          canvas
            ..width = video.videoWidth
            ..height = video.videoHeight;
          ctx.drawImage(video, 0, 0);
        } else {
          final aspectRatio = video.videoWidth / video.videoHeight;
          if (localMaxWidth == 0) {
            localMaxWidth = (localMaxHeight * aspectRatio).round();
          } else if (localMaxHeight == 0) {
            localMaxHeight = (localMaxWidth / aspectRatio).round();
          }

          final inputAspectRatio = localMaxWidth / localMaxHeight;
          if (aspectRatio > inputAspectRatio) {
            localMaxHeight = (localMaxWidth / aspectRatio).round();
          } else {
            localMaxWidth = (localMaxHeight * aspectRatio).round();
          }

          canvas
            ..width = localMaxWidth
            ..height = localMaxHeight;
          ctx.drawImage(video, 0, 0, localMaxWidth.toDouble(), localMaxHeight.toDouble());
        }

        try {
          final blobCompleter = Completer<web.Blob>();
          canvas.toBlob(
            (web.Blob? b) {
              if (b != null) {
                blobCompleter.complete(b);
              } else {
                blobCompleter.completeError(
                  PlatformException(
                    code: 'CANVAS_EXPORT_ERROR',
                    message: 'Failed to create blob from canvas',
                  ),
                );
              }
            }.toJS,
            _imageFormatToCanvasFormat(imageFormat),
            (quality / 100.0).toJS,
          );

          completer.complete(await blobCompleter.future);
        } catch (e, s) {
          completer.completeError(
            PlatformException(
              code: 'CANVAS_EXPORT_ERROR',
              details: e,
              stacktrace: s.toString(),
            ),
            s,
          );
        }
      }
    });

    video.onError.listen((web.Event e) {
      if (!completer.isCompleted) {
        final error = video.error!;
        completer.completeError(
          PlatformException(
            code: _kErrorValueToErrorName[error.code]!,
            message:
                error.message != '' ? error.message : _kDefaultErrorMessage,
            details: _kErrorValueToErrorDescription[error.code],
          ),
        );
      }
    });

    if (fetchVideo) {
      try {
        final blob = await _fetchVideoByHeaders(
          videoSrc: videoSrc,
          headers: headers,
        );

        video.src = web.URL.createObjectURL(blob);
      } catch (e, s) {
        completer.completeError(e, s);
      }
    } else {
      video
        ..crossOrigin = 'Anonymous'
        ..src = videoSrc;
    }

    return completer.future;
  }

  /// Fetching video by [headers].
  ///
  /// To avoid reading the video's bytes into memory, set the
  /// [web.XMLHttpRequest.responseType] to 'blob'. This allows the blob to be stored in
  /// the browser's disk or memory cache.
  Future<web.Blob> _fetchVideoByHeaders({
    required String videoSrc,
    required Map<String, String> headers,
  }) async {
    final completer = Completer<web.Blob>();

    final xhr = web.XMLHttpRequest();
    xhr.open('GET', videoSrc, true);
    xhr.responseType = 'blob';
    headers.forEach((key, value) {
      xhr.setRequestHeader(key, value);
    });

    xhr.onLoad.listen((web.Event value) {
      completer.complete(xhr.response as web.Blob);
    });

    xhr.onError.listen((web.Event value) {
      completer.completeError(
        PlatformException(
          code: 'VIDEO_FETCH_ERROR',
          message: 'Status: ${xhr.statusText}',
        ),
      );
    });

    xhr.send();

    return completer.future;
  }

  String _imageFormatToCanvasFormat(ImageFormat imageFormat) {
    switch (imageFormat) {
      case ImageFormat.JPEG:
        return 'image/jpeg';
      case ImageFormat.PNG:
        return 'image/png';
      case ImageFormat.WEBP:
        return 'image/webp';
    }
  }
}
