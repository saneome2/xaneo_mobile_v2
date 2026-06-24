import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../providers/playback_provider.dart';

class VideoMessagePlayer extends StatefulWidget {
  final String videoUrl;
  final String? jwtToken;
  final double duration;
  final String? localPath;
  final String? senderName;

  const VideoMessagePlayer({
    super.key,
    required this.videoUrl,
    this.jwtToken,
    required this.duration,
    this.localPath,
    this.senderName,
  });

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  PlaybackProvider? _playbackProvider;

  @override
  bool get wantKeepAlive {
    if (_playbackProvider == null) return false;
    return _playbackProvider!.currentAudioUrl == widget.videoUrl && _playbackProvider!.isVideo;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newProvider = Provider.of<PlaybackProvider>(context);
    if (_playbackProvider != newProvider) {
      _playbackProvider?.removeListener(_onPlaybackProviderChanged);
      _playbackProvider = newProvider;
      _playbackProvider?.addListener(_onPlaybackProviderChanged);
    }
  }

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      if (widget.localPath != null && widget.localPath!.isNotEmpty) {
        final file = File(widget.localPath!);
        if (await file.exists()) {
          _controller = VideoPlayerController.file(file);
        }
      }

      _controller ??= VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: widget.jwtToken != null
            ? {'Authorization': 'Bearer ${widget.jwtToken}'}
            : {},
      );

      await _controller!.initialize();
      _controller!.setLooping(false);
      _controller!.addListener(_videoListener);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing video message player: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _videoListener() {
    if (_controller == null) return;
    final isPlaying = _controller!.value.isPlaying;
    final isCompleted = _controller!.value.position >= _controller!.value.duration;

    if (isPlaying != _isPlaying) {
      if (mounted) {
        setState(() {
          _isPlaying = isPlaying;
        });
      }
    }

    if (_playbackProvider != null) {
      final isCurrent = _playbackProvider!.currentAudioUrl == widget.videoUrl && _playbackProvider!.isVideo;
      if (isCurrent) {
        if (isCompleted && _playbackProvider!.isPlaying) {
          _playbackProvider!.setPlaying(false);
        } else if (isPlaying != _playbackProvider!.isPlaying && !isCompleted) {
          _playbackProvider!.setPlaying(isPlaying);
        }
      }
    }
  }

  void _onPlaybackProviderChanged() {
    if (_playbackProvider == null || _controller == null || !_isInitialized) return;

    final isCurrent = _playbackProvider!.currentAudioUrl == widget.videoUrl && _playbackProvider!.isVideo;
    if (isCurrent) {
      final shouldBePlaying = _playbackProvider!.isPlaying;
      if (shouldBePlaying && !_controller!.value.isPlaying) {
        if (_controller!.value.position >= _controller!.value.duration) {
          _controller!.seekTo(Duration.zero);
        }
        _controller!.play();
      } else if (!shouldBePlaying && _controller!.value.isPlaying) {
        _controller!.pause();
      }
    } else {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      }
    }
    updateKeepAlive();
  }

  @override
  void dispose() {
    _playbackProvider?.removeListener(_onPlaybackProviderChanged);
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller == null || !_isInitialized) return;
    final playbackProvider = Provider.of<PlaybackProvider>(context, listen: false);
    playbackProvider.playVideo(
      widget.videoUrl,
      'Видеосообщение',
      widget.senderName ?? 'Видеосообщение',
      duration: Duration(milliseconds: (widget.duration * 1000).toInt()),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_hasError) {
      return Container(
        width: 180,
        height: 180,
        decoration: const BoxDecoration(
          color: Colors.black26,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 36),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: 180,
        height: 180,
        decoration: const BoxDecoration(
          color: Colors.black26,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30, width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ],
            ),
            child: ClipOval(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            ),
          ),
          if (!_isPlaying)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 28,
              ),
            ),
        ],
      ),
    );
  }
}

