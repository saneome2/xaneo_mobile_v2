import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../services/auth/token_storage.dart';

/// Глобальный провайдер воспроизведения голосовых сообщений.
///
/// Аудио проигрывается через [just_audio].
/// Временный файл скачивается с авторизацией (JWT) и кэшируется.
///
/// Seek реализован через пересоздание AudioSource из кэшированного файла,
/// так как ExoPlayer (Android) игнорирует _player.seek() для WebM/Opus файлов.
class PlaybackProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  String? _currentAudioUrl;
  String? _currentFilePath; // Локальный путь к файлу (для пересоздания при seek)
  String _title = '';
  String _subtitle = '';
  bool _isPlaying = false;
  bool _isInitialized = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = false;
  bool _isSeeking = false; // Guard от конкурентных seek
  bool _isVideo = false;

  // После seek() некоторое время positionStream может присылать "хвостовые"
  // события от старого/пересоздаваемого AudioSource с позицией около нуля,
  // даже после того как _isSeeking уже сброшен в false. Запоминаем целевую
  // позицию и игнорируем явно более ранние события короткое время после сика,
  // чтобы UI не дёргался назад.
  Duration? _seekTargetPosition;
  DateTime? _seekCompletedAt;
  static const _seekSettleWindow = Duration(milliseconds: 600);

  String? get currentAudioUrl => _currentAudioUrl;
  String get title => _title;
  String get subtitle => _subtitle;
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isLoading => _isLoading;
  bool get isVideo => _isVideo;

  List<String> _queue = [];
  int _queueIndex = -1;

  PlaybackProvider() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;

      if (state.processingState == ProcessingState.completed) {
        _isPlaying = false;
        _position = Duration.zero;
      }
      notifyListeners();
    });

    _positionSub = _player.positionStream.listen((pos) {
      // Во время reinit (seek/restart) игнорируем промежуточные позиции,
      // чтобы UI не мерцал (setAudioSource сбрасывает позицию в 0)
      if (_isSeeking) return;

      // Сразу после seek() стрим может ещё какое-то время присылать
      // "хвостовые" события от пересоздаваемого AudioSource — обычно
      // позиции около нуля, заметно меньше целевой. Отбрасываем такие
      // явные откаты в течение короткого окна после завершения seek.
      if (_seekTargetPosition != null && _seekCompletedAt != null) {
        final elapsed = DateTime.now().difference(_seekCompletedAt!);
        if (elapsed < _seekSettleWindow) {
          final drift = _seekTargetPosition! - pos;
          if (drift > const Duration(milliseconds: 300)) {
            // Похоже на устаревшее событие — позиция заметно меньше,
            // чем то, куда мы только что сикнули. Игнорируем.
            return;
          }
        } else {
          // Окно истекло — больше не фильтруем
          _seekTargetPosition = null;
          _seekCompletedAt = null;
        }
      }

      _position = pos;
      notifyListeners();
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero && dur != _duration) {
        _duration = dur;
        notifyListeners();
      }
    });
  }

  void setQueue(List<String> urls, int startIndex) {
    _queue = List<String>.from(urls);
    _queueIndex = startIndex;
  }

  /// Запускает воспроизведение [url]. Если это уже текущий трек — переключает play/pause.
  Future<void> play(String url, String title, String subtitle, {
    String? mimeType,
    Duration? duration
  }) async {
    if (_currentAudioUrl == url) {
      _togglePlay();
      return;
    }

    await stop();

    _currentAudioUrl = url;
    _title = title;
    _subtitle = subtitle;
    _isLoading = true;
    _duration = duration ?? Duration.zero;
    notifyListeners();

    try {
      // Локальный файл (только что записанное наше ГС) — играем напрямую,
      // без скачивания. url здесь — это путь к файлу, а не http-ссылка.
      if (!url.startsWith('http')) {
        final localFile = File(url);
        if (await localFile.exists()) {
          _currentFilePath = url;
          await _player.setAudioSource(AudioSource.file(url));
          _isInitialized = true;
          _isLoading = false;

          final playerDuration = _player.duration;
          if (playerDuration != null && playerDuration > Duration.zero) {
            _duration = playerDuration;
          } else if (duration != null) {
            _duration = duration;
          }

          await _player.play();
          notifyListeners();
          return;
        }
      }

      final tempDir = await getTemporaryDirectory();
      String ext = '.ogg';
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
        } else if (mime.contains('m4a') || mime.contains('aac')) {
          ext = '.m4a';
        }
      }

      final safeName = url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final localFilePath = '${tempDir.path}/voice_$safeName$ext';
      final file = File(localFilePath);

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

      _currentFilePath = localFilePath;

      // Загружаем аудио-файл
      await _player.setAudioSource(AudioSource.file(localFilePath));

      _isInitialized = true;
      _isLoading = false;

      final playerDuration = _player.duration;
      if (playerDuration != null && playerDuration > Duration.zero) {
        _duration = playerDuration;
      } else if (duration != null) {
        _duration = duration;
      }

      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Playback error: $e');
      _isLoading = false;
      _isInitialized = false;
      _currentAudioUrl = null;
      _currentFilePath = null;
      notifyListeners();
    }
  }

  void _togglePlay() {
    if (_isVideo) {
      _isPlaying = !_isPlaying;
      notifyListeners();
      return;
    }
    if (!_isInitialized || _isSeeking) return;

    if (_isPlaying) {
      _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        _restartFrom(Duration.zero);
      } else {
        _player.play();
      }
    }
  }

  void pause() {
    if (_isVideo) {
      _isPlaying = false;
      notifyListeners();
    } else {
      if (_isPlaying) {
        _player.pause();
      }
    }
  }

  void resume() {
    if (_isVideo) {
      _isPlaying = true;
      notifyListeners();
    } else {
      if (!_isPlaying && _isInitialized && !_isSeeking) {
        if (_position >= _duration && _duration > Duration.zero) {
          _restartFrom(Duration.zero);
        } else {
          _player.play();
        }
      }
    }
  }

  Future<void> playVideo(String url, String title, String subtitle, {
    Duration? duration
  }) async {
    if (_currentAudioUrl == url && _isVideo) {
      _togglePlay();
      return;
    }

    await stop();

    _isVideo = true;
    _currentAudioUrl = url;
    _title = title;
    _subtitle = subtitle;
    _isPlaying = true;
    _isInitialized = true;
    _duration = duration ?? Duration.zero;
    notifyListeners();
  }

  void setPlaying(bool playing) {
    if (_isPlaying != playing) {
      _isPlaying = playing;
      notifyListeners();
    }
  }

  /// Лёгкое "превью" позиции во время драга слайдера.
  ///
  /// НЕ трогает плеер и НЕ пересоздаёт AudioSource — просто обновляет
  /// локальную _position, чтобы UI (слайдер, таймер) реагировал мгновенно
  /// на каждое движение пальца. Реальный seek() с пересозданием делаем
  /// один раз, когда палец отпущен (onChangeEnd / onHorizontalDragEnd).
  ///
  /// Это нужно, потому что seek() — тяжёлая операция (пересоздание
  /// AudioSource из файла), и если дёргать её на каждый пиксель драга,
  /// guard _isSeeking будет отбрасывать почти все вызовы, и слайдер
  /// будет казаться "залипшим"/неотзывчивым.
  void seekPreview(Duration pos) {
    if (!_isInitialized) return;
    if (_duration == Duration.zero) return;
    if (pos > _duration) pos = _duration;
    if (pos < Duration.zero) pos = Duration.zero;

    _position = pos;
    notifyListeners();
  }

  /// Seek: пересоздаём AudioSource из кэшированного файла и стартуем с нужной позиции.
  /// ExoPlayer (Android) игнорирует _player.seek() для WebM/Opus файлов,
  /// поэтому пересоздание — единственный надёжный способ.
  ///
  /// Это "тяжёлый" метод — вызывать его стоит только один раз на жест
  /// (по отпусканию пальца), а не на каждое промежуточное движение.
  /// Для промежуточных обновлений UI во время драга используйте seekPreview().
  Future<void> seek(Duration pos) async {
    if (!_isInitialized || _isSeeking) return;
    if (_duration == Duration.zero) return;
    if (pos > _duration) pos = _duration;
    if (_currentFilePath == null) return;

    _isSeeking = true;

    _position = pos;
    notifyListeners();
    await _restartFrom(pos);

    // Запоминаем целевую позицию — следующие ~600ms positionStream
    // будет сверяться с ней, чтобы отфильтровать хвостовые события
    // от пересоздаваемого AudioSource (см. _positionSub listener выше).
    _seekTargetPosition = pos;
    _seekCompletedAt = DateTime.now();

    _isSeeking = false;
  }

  /// Пересоздаём плюер с нужной стартовой позицией (для seek, restart и toggle).
  /// Имеет свой try/catch, т.к. _togglePlay/resume вызывают без await.
  ///
  /// ВАЖНО: после setAudioSource() именно await не гарантирует, что
  /// ExoPlayer (Android) уже готов принимать точный seek — он может
  /// формально вернуть управление, пока сам декодер ещё не settled.
  /// Если в этот момент вызвать seek()+play(), позиция иногда "уезжает"
  /// почти к нулю, хотя API уже отрапортовал успех. Поэтому явно ждём
  /// processingState == ready через стрим, прежде чем сикать.
  Future<void> _restartFrom(Duration pos) async {
    if (_currentFilePath == null) return;

    try {
      await _player.setAudioSource(AudioSource.file(_currentFilePath!));

      // Ждём, пока плеер реально готов (а не просто вернул управление из await)
      if (_player.processingState != ProcessingState.ready &&
          _player.processingState != ProcessingState.completed) {
        await _player.playerStateStream
            .firstWhere((state) =>
                state.processingState == ProcessingState.ready ||
                state.processingState == ProcessingState.completed)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => _player.playerState,
            );
      }

      await _player.seek(pos);
      await _player.play();
    } catch (e) {
      debugPrint('❌ _restartFrom error: $e');
    }
  }

  Future<void> stop() async {
    await _player.stop();

    _currentAudioUrl = null;
    _currentFilePath = null;
    _title = '';
    _subtitle = '';
    _isPlaying = false;
    _isInitialized = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isLoading = false;
    _isSeeking = false;
    _isVideo = false;
    _seekTargetPosition = null;
    _seekCompletedAt = null;
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
