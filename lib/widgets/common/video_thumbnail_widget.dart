import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../utils/local_proxy.dart';

class VideoThumbnailWidget extends StatefulWidget {
  final String videoUrl;
  final String? jwtToken;
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const VideoThumbnailWidget({
    Key? key,
    required this.videoUrl,
    this.jwtToken,
    required this.width,
    required this.height,
    required this.borderRadius,
  }) : super(key: key);

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  Uint8List? _thumbnailData;
  bool _isLoading = true;
  static final Map<String, Uint8List> _cache = {};

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final proxyUrl = LocalProxy.getProxyUrl(widget.videoUrl, jwtToken: widget.jwtToken);
    
    if (_cache.containsKey(proxyUrl)) {
      if (mounted) {
        setState(() {
          _thumbnailData = _cache[proxyUrl];
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final uint8list = await VideoThumbnail.thumbnailData(
        video: proxyUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320, // specify the width of the thumbnail, let the height auto-scaled to keep the source aspect ratio
        quality: 50,
      );
      
      if (uint8list != null) {
        _cache[proxyUrl] = uint8list;
      }
      
      if (mounted) {
        setState(() {
          _thumbnailData = uint8list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: widget.borderRadius,
        ),
        child: const Center(
          child: SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
        ),
      );
    }
    
    if (_thumbnailData == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: widget.borderRadius,
        ),
        child: const Center(
          child: Icon(Icons.videocam, color: Colors.white54, size: 36),
        ),
      );
    }
    
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Image.memory(
        _thumbnailData!,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
      ),
    );
  }
}
