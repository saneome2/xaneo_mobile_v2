import 'dart:io';

class LocalProxy {
  static HttpServer? _server;

  static Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen((HttpRequest request) async {
        final targetUrl = request.uri.queryParameters['url'];
        final jwtToken = request.uri.queryParameters['token'];

        if (targetUrl == null) {
          request.response.statusCode = 400;
          await request.response.close();
          return;
        }

        try {
          final client = HttpClient();
          // Это заставит Dart игнорировать ошибки SSL (поскольку мы уже переопределили HttpOverrides глобально)
          final targetUri = Uri.parse(targetUrl);
          final clientRequest = await client.getUrl(targetUri);

          // Проброс заголовков (особенно Range для видео)
          request.headers.forEach((name, values) {
            if (name.toLowerCase() == 'host') return;
            clientRequest.headers.set(name, values.join(','));
          });

          if (jwtToken != null && jwtToken.isNotEmpty) {
            clientRequest.headers.set('Authorization', 'Bearer $jwtToken');
          }

          final clientResponse = await clientRequest.close();

          request.response.statusCode = clientResponse.statusCode;
          clientResponse.headers.forEach((name, values) {
            request.response.headers.set(name, values.join(','));
          });

          await clientResponse.pipe(request.response);
        } catch (e) {
          request.response.statusCode = 500;
          await request.response.close();
        }
      });
    } catch (e) {
      print('Proxy start error: $e');
    }
  }

  static String getProxyUrl(String targetUrl, {String? jwtToken}) {
    if (_server == null) return targetUrl;
    final uri = Uri(
      scheme: 'http',
      host: _server!.address.address,
      port: _server!.port,
      queryParameters: {
        'url': targetUrl,
        if (jwtToken != null) 'token': jwtToken,
      },
    );
    return uri.toString();
  }
}
