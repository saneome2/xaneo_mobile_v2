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

        print('LocalProxy: proxying request for URL: $targetUrl');

        try {
          final client = HttpClient();
          // Explicitly ignore SSL certificate validation for local development
          client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
          
          final targetUri = Uri.parse(targetUrl);
          final clientRequest = await client.getUrl(targetUri);

          // Propagate headers (especially Range for video)
          request.headers.forEach((name, values) {
            if (name.toLowerCase() == 'host') return;
            clientRequest.headers.set(name, values.join(','));
          });

          if (jwtToken != null && jwtToken.isNotEmpty) {
            clientRequest.headers.set('Authorization', 'Bearer $jwtToken');
          }

          final clientResponse = await clientRequest.close();
          print('LocalProxy: Backend returned status ${clientResponse.statusCode} for $targetUrl');

          request.response.statusCode = clientResponse.statusCode;
          clientResponse.headers.forEach((name, values) {
            request.response.headers.set(name, values.join(','));
          });

          await clientResponse.pipe(request.response);
        } catch (e, stack) {
          print('LocalProxy handler error for url $targetUrl: $e\n$stack');
          request.response.statusCode = 500;
          await request.response.close();
        }
      });
    } catch (e) {
      print('Proxy start error: $e');
    }
  }

  static String getProxyUrl(String targetUrl, {String? jwtToken, String? ext}) {
    if (_server == null) return targetUrl;
    
    String path = '/media';
    if (ext != null) {
      path = '/media$ext';
    } else {
      final lower = targetUrl.toLowerCase();
      if (lower.contains('.m4a')) path = '/audio.m4a';
      else if (lower.contains('.mp3')) path = '/audio.mp3';
      else if (lower.contains('.mp4')) path = '/video.mp4';
      else if (lower.contains('.m3u8')) path = '/video.m3u8';
    }

    final uri = Uri(
      scheme: 'http',
      host: _server!.address.address,
      port: _server!.port,
      path: path,
      queryParameters: {
        'url': targetUrl,
        if (jwtToken != null) 'token': jwtToken,
      },
    );
    return uri.toString();
  }
}
