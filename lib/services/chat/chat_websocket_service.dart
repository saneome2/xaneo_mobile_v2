import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../config/app_config.dart';
import '../auth/token_storage.dart';

class ChatWebSocketService {
  final TokenStorage _tokenStorage;

  ChatWebSocketService({TokenStorage? tokenStorage})
      : _tokenStorage = tokenStorage ?? TokenStorage();

  final StreamController<Map<String, dynamic>> _eventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  IOWebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  String? _activeChatId;
  bool _manualDisconnect = false;
  int _reconnectAttempt = 0;

  Future<void> connect(String chatId) async {
    if (_activeChatId == chatId && _channel != null) return;

    await disconnect();
    _manualDisconnect = false;
    _activeChatId = chatId;

    final token = await _tokenStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      debugPrint('WS: access token is missing, skip connect');
      return;
    }

    final uri = _buildWsUri(chatId, token);
    final safeUri = uri.replace(queryParameters: {'token': '***'});
    debugPrint('WS: connecting to $safeUri');

    try {
      final customClient = _buildDebugHttpClientForSelfSigned(uri);
      _channel = IOWebSocketChannel.connect(
        uri,
        customClient: customClient,
      );
      _subscription = _channel!.stream.listen(
        _handleRawEvent,
        onError: (error) {
          debugPrint('WS: stream error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WS: stream closed');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
      _reconnectAttempt = 0;
    } catch (e) {
      debugPrint('WS: connect error: $e');
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _activeChatId = null;

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
  }

  Future<void> send(Map<String, dynamic> payload) async {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(payload));
  }

  Future<void> dispose() async {
    await disconnect();
    await _eventsController.close();
  }

  Uri _buildWsUri(String chatId, String token) {
    final apiUri = Uri.parse(AppConfig.apiBaseUrl);
    final isIpHost = InternetAddress.tryParse(apiUri.host) != null;
    final shouldUseInsecureWs = apiUri.scheme != 'https';
    final wsScheme = shouldUseInsecureWs ? 'ws' : 'wss';

    if (kDebugMode && isIpHost && apiUri.scheme == 'https') {
      debugPrint(
        'WS: debug mode with IP host detected, using debug TLS bypass for self-signed certificate',
      );
    }

    final query = <String, String>{'token': token};

    return Uri(
      scheme: wsScheme,
      host: apiUri.host,
      port: apiUri.hasPort ? apiUri.port : null,
      path: '/ws/chat/$chatId/',
      queryParameters: query,
    );
  }

  HttpClient? _buildDebugHttpClientForSelfSigned(Uri uri) {
    if (!kDebugMode) return null;

    final isIpHost = InternetAddress.tryParse(uri.host) != null;
    if (uri.scheme != 'wss' || !isIpHost) return null;

    final client = HttpClient();
    client.badCertificateCallback = (
      X509Certificate cert,
      String host,
      int port,
    ) {
      debugPrint('WS: accepting self-signed cert in debug for $host:$port');
      return true;
    };
    return client;
  }

  void _handleRawEvent(dynamic raw) {
    try {
      final parsed = raw is String ? jsonDecode(raw) : raw;
      if (parsed is Map<String, dynamic>) {
        _eventsController.add(parsed);
      } else if (parsed is Map) {
        _eventsController.add(parsed.cast<String, dynamic>());
      }
    } catch (e) {
      debugPrint('WS: failed to parse event: $e');
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _activeChatId == null) return;

    _reconnectTimer?.cancel();
    _reconnectAttempt += 1;

    final exponent = _reconnectAttempt > 6 ? 6 : _reconnectAttempt;
    final delay = Duration(seconds: 1 << exponent);
    debugPrint('WS: reconnect in ${delay.inSeconds}s (attempt $_reconnectAttempt)');

    _reconnectTimer = Timer(delay, () {
      final chatId = _activeChatId;
      if (chatId == null) return;
      connect(chatId);
    });
  }
}