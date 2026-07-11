import 'package:flutter/foundation.dart' show kIsWeb;

// Web (Chrome) reaches the host directly; the Android emulator uses 10.0.2.2.
// Real phone on the same Wi-Fi: use your laptop LAN IP (ipconfig getifaddr en0).
String get apiBaseUrl => kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000';
