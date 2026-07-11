import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models/account.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiClient {
  String? _token;

  bool get isAuthenticated => _token != null;

  Future<void> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$apiBaseUrl/api/v1/session'),
      body: {'email': email, 'password': password},
    );
    if (res.statusCode == 200) {
      _token = jsonDecode(res.body)['token'] as String;
    } else if (res.statusCode == 401) {
      throw ApiException('E-posta veya şifre hatalı.');
    } else {
      throw ApiException('Giriş başarısız (${res.statusCode}).');
    }
  }

  Future<List<Account>> fetchAccounts() async {
    final res = await http.get(
      Uri.parse('$apiBaseUrl/api/v1/accounts'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (res.statusCode != 200) {
      throw ApiException('Hesaplar alınamadı (${res.statusCode}).');
    }
    final list = jsonDecode(res.body)['accounts'] as List<dynamic>;
    return list
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final apiClient = ApiClient();
