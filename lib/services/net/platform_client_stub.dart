import 'package:http/http.dart' as http;

/// Browsers pool connections and negotiate HTTP/2, HTTP/3 and Brotli themselves.
const Duration connectionIdleTimeout = Duration(minutes: 2);

http.Client createPlatformClient() => http.Client();

http.Client ioClient() => http.Client();
