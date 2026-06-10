import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
      final socket = await _openSocketWithFallback(uri);
      _channel = IOWebSocketChannel(socket);
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

  Future<WebSocket> _openSocketWithFallback(Uri uri) async {
    final customClient = _buildDebugHttpClientForSelfSigned(uri);

    try {
      return await WebSocket.connect(
        uri.toString(),
        customClient: customClient,
      );
    } catch (e) {
      final isIpHost = InternetAddress.tryParse(uri.host) != null;
      final isTlsCertIssue = e.toString().contains('CERTIFICATE_VERIFY_FAILED');
      final isPrivate = _isPrivateIp(uri.host);

      if ((!kReleaseMode || isPrivate) && isIpHost && uri.scheme == 'wss' && isTlsCertIssue) {
        final fallbackUri = uri.replace(scheme: 'ws');
        final safeFallbackUri =
            fallbackUri.replace(queryParameters: {'token': '***'});
        debugPrint('WS: TLS handshake failed, fallback to $safeFallbackUri');

        return await WebSocket.connect(fallbackUri.toString());
      }

      rethrow;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _activeChatId = null;

    _subscription?.cancel();
    _subscription = null;

    _channel?.sink.close(ws_status.normalClosure);
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

    if (!kReleaseMode && isIpHost && apiUri.scheme == 'https') {
      debugPrint(
        'WS: debug/profile mode with IP host detected, using debug TLS bypass for self-signed certificate',
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
    if (kReleaseMode && !_isPrivateIp(uri.host)) return null;

    final isIpHost = InternetAddress.tryParse(uri.host) != null;
    if (uri.scheme != 'wss' || !isIpHost) return null;

    final client = HttpClient();
    client.badCertificateCallback = (
      X509Certificate cert,
      String host,
      int port,
    ) {
      debugPrint('WS: accepting self-signed cert in debug/profile/local for $host:$port');
      return true;
    };
    return client;
  }

  bool _isPrivateIp(String host) {
    if (host == 'localhost' || host == '127.0.0.1') return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;

    if (address.type == InternetAddressType.IPv4) {
      final parts = host.split('.').map(int.tryParse).toList();
      if (parts.length == 4 && parts[0] != null) {
        if (parts[0] == 10) return true;
        if (parts[0] == 192 && parts[1] == 168) return true;
        if (parts[0] == 172 && parts[1] != null && parts[1]! >= 16 && parts[1]! <= 31) return true;
      }
    }
    return false;
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
    final baseDelaySeconds = 1 << exponent;
    final jitterMs = Random().nextInt(1000); // random jitter between 0 and 999ms to prevent reconnect storms
    final delay = Duration(milliseconds: baseDelaySeconds * 1000 + jitterMs);
    debugPrint('WS: reconnect in ${baseDelaySeconds}s + ${jitterMs}ms (attempt $_reconnectAttempt)');

    _reconnectTimer = Timer(delay, () {
      final chatId = _activeChatId;
      if (chatId == null) return;
      connect(chatId);
    });
  }
}