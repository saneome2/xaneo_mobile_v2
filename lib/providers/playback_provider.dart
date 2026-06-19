import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../services/auth/token_storage.dart';

/// Глобальный провайдер воспроизведения голосовых сообщений.
///
/// Аудио проигрывается через [just_audio] (надёжная инициализация и корректные
/// события завершения). Временный файл скачивается с авторизацией (JWT) и
/// кэшируется во временной директории.
///
/// Публичный API (`currentAudioUrl`, `isPlaying`, `isInitialized`, `position`,
/// `duration`, `isLoading`, `play`/`pause`/`resume`/`seek`/`stop`, очередь
/// `setQueue`/`next`/`previous`) сохранён совместимым с предыдущей версией на
/// video_player — экранам менять ничего не нужно.
class PlaybackProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  String? _currentAudioUrl;
  String _title = '';
  String _subtitle = '';
  bool _isPlaying = false;
  bool _isInitialized = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = false;

  // Текущий проигрываемый трек (для отладки и расширения очереди).
  String? get currentAudioUrl => _currentAudioUrl;
  String get title => _title;
  String get subtitle => _subtitle;
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isLoading => _isLoading;

  // Очередь для next/prev (мини-плеер в main_screen).
  List<String> _queue = [];
  int _queueIndex = -1;

  PlaybackProvider() {
    _playerStateSub = _player.playerStateStream.listen(_onPlayerState);
    _positionSub = _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    _durationSub = _player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    });
  }

  void setQueue(List<String> urls, int startIndex) {
    _queue = List<String>.from(urls);
    _queueIndex = startIndex;
  }

  /// Запускает воспроизведение [url]. Если это уже текущий трек — переключает
  /// play/pause.
  Future<void> play(String url, String title, String subtitle, {String? mimeType}) async {
    if (_currentAudioUrl == url) {
      _togglePlay();
      return;
    }

    await stop();

    _currentAudioUrl = url;
    _title = title;
    _subtitle = subtitle;
    _isLoading = true;
    _isPlaying = false;
    _isInitialized = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();

    try {
      final tempDir = await getTemporaryDirectory();
      String ext = '.m4a';
      if (mimeType != null) {
        final mime = mimeType.toLowerCase();
        if (mime.contains('webm')) {
          ext = '.webm';
        } else if (mime.contains('ogg') || mime.contains('opus')) {
          ext = '.ogg';
        } else if (mime.contains('mp3')) {
          ext = '.mp3';
        } else if (mime.contains('wav')) {
          ext = '.wav';
        }
      }

      final safeName = url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final localFilePath = '${tempDir.path}/voice_$safeName$ext';
      final file = File(localFilePath);

      // Скачиваем только если файла ещё нет в кэше.
      if (!await file.exists()) {
        final freshToken = await TokenStorage().getAccessToken();
        final dio = Dio();
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
          return client;
        };

        final response = await dio.download(
          url,
          localFilePath,
          options: Options(
            headers: freshToken != null && freshToken.isNotEmpty
                ? {'Authorization': 'Bearer $freshToken'}
                : {},
          ),
        );
        if (response.statusCode != 200) {
          throw Exception('Failed to download audio file: ${response.statusCode}');
        }
      }

      // just_audio нативно инициализирует аудио-only файлы.
      await _player.setFilePath(file.path);
      _isInitialized = true;
      _duration = _player.duration ?? Duration.zero;
      _isLoading = false;
      await _player.seek(Duration.zero);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Global playback error: $e');
      _isLoading = false;
      _isPlaying = false;
      _isInitialized = false;
      _currentAudioUrl = null;
      notifyListeners();
    }
  }

  void _onPlayerState(PlayerState state) {
    _isPlaying = state.playing;

    // Корректное завершение трека.
    if (state.processingState == ProcessingState.completed) {
      _isPlaying = false;
      _player.pause();
      _player.seek(Duration.zero);
      _position = Duration.zero;
    }
    notifyListeners();
  }

  void _togglePlay() {
    if (!_isInitialized) return;
    if (_isPlaying) {
      _player.pause();
    } else {
      // Если трек доиграл до конца — перематываем в начало.
      if (_position >= _duration && _duration > Duration.zero) {
        _player.seek(Duration.zero);
      }
      _player.play();
    }
  }

  void pause() {
    if (_isPlaying) {
      _player.pause();
    }
  }

  void resume() {
    if (!_isPlaying && _isInitialized) {
      if (_position >= _duration && _duration > Duration.zero) {
        _player.seek(Duration.zero);
      }
      _player.play();
    }
  }

  Future<void> seek(Duration pos) async {
    if (_isInitialized) {
      await _player.seek(pos);
      _position = pos;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero);
    _currentAudioUrl = null;
    _title = '';
    _subtitle = '';
    _isPlaying = false;
    _isInitialized = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isLoading = false;
    notifyListeners();
  }

  void next() {
    if (_queue.isNotEmpty && _queueIndex < _queue.length - 1) {
      _queueIndex++;
      final nextUrl = _queue[_queueIndex];
      play(nextUrl, 'Голосовое #${_queueIndex + 1}', _subtitle);
    }
  }

  void previous() {
    if (_queue.isNotEmpty && _queueIndex > 0) {
      _queueIndex--;
      final prevUrl = _queue[_queueIndex];
      play(prevUrl, 'Голосовое #${_queueIndex + 1}', _subtitle);
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
