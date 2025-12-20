import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/sensor_model.dart';
import '../models/message_model.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:5000';

  // Helper untuk headers
  static Map<String, String> _getHeaders(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  // Helper untuk error handling
  static Map<String, dynamic> _handleError(dynamic e) {
    print('❌ API Error: $e');
    return {
      'status': false,
      'message': 'Koneksi gagal. Periksa koneksi internet Anda.',
      'error': e.toString(),
    };
  }

  // ========== AUTHENTICATION ==========
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      print('🔐 Login attempt for: $email');

      final response = await http.post(
        Uri.parse('$baseUrl/api/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      print('📥 Login Response Status: ${response.statusCode}');

      // Handle non-200 responses
      if (response.statusCode != 200) {
        return {
          'status': false,
          'message': 'Server error (${response.statusCode})',
        };
      }

      final responseData = jsonDecode(response.body);

      if (responseData['status'] == true) {
        final userData = responseData['user'] as Map<String, dynamic>;
        final role = userData['role']?.toString().toLowerCase() ?? '';

        // Cek role admin
        if (role != 'admin') {
          return {
            'status': false,
            'message': 'Akses ditolak. Hanya admin yang dapat login.',
          };
        }

        final token = responseData['token']?.toString();

        if (token == null || token.isEmpty) {
          return {
            'status': false,
            'message': 'Token tidak ditemukan dalam response',
          };
        }

        print('✅ Login successful for admin: ${userData['email']}');

        return {'status': true, 'token': token, 'user': userData};
      } else {
        return {
          'status': false,
          'message': responseData['message'] ?? 'Login gagal',
        };
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  static Future<Map<String, dynamic>> logout(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/logout'),
        headers: _getHeaders(token),
      );

      return {
        'status': response.statusCode == 200,
        'message': response.statusCode == 200
            ? 'Logout berhasil'
            : 'Logout gagal',
      };
    } catch (e) {
      return _handleError(e);
    }
  }

  // ========== ADMIN DASHBOARD ==========
  static Future<Map<String, dynamic>> getDashboardStats(String token) async {
    try {
      print('📊 Fetching dashboard stats...');

      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/dashboard/stats'),
        headers: _getHeaders(token),
      );

      print('📊 Dashboard Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        return {
          'status': false,
          'message': 'Session expired. Please login again.',
          'code': 401,
        };
      } else if (response.statusCode == 403) {
        return {
          'status': false,
          'message': 'Access denied. Admin only.',
          'code': 403,
        };
      } else {
        return {
          'status': false,
          'message': 'Failed to load dashboard (${response.statusCode})',
          'code': response.statusCode,
        };
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  static Future<Map<String, dynamic>> getQuickStats(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/dashboard/quick-stats'),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'status': false, 'message': 'Failed to load quick stats'};
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  // ========== SENSOR DATA ==========
  static Future<List<SensorData>> fetchSensorData(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/get_sensor_data'),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List sensorList = data['data'] ?? [];

        return sensorList
            .map((e) => SensorData.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } else {
        throw Exception('Failed to load sensor data: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Sensor data error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> controlActuator(
    String name,
    bool state,
    String token,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/control_actuator'),
        headers: _getHeaders(token),
        body: jsonEncode({"name": name, "state": state ? "ON" : "OFF"}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          "status": false,
          "message": "Failed to control actuator (${response.statusCode})",
        };
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  // ========== MESSAGES ==========
  static Future<List<AdminMessage>> getAdminMessages(String token) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/admin/messages"),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List messages = data["data"] ?? [];

        return messages
            .map((m) => AdminMessage.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      } else {
        print('❌ Failed admin messages: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Admin messages error: $e');
      return [];
    }
  }

  static Future<int> getAdminUnreadCount(String token) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/admin/messages/unread-count"),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["unread"] ?? 0;
      }
      return 0;
    } catch (e) {
      print('❌ Unread count error: $e');
      return 0;
    }
  }

  // NEW: Mark message as read
  static Future<bool> markAdminMessageAsRead(
    String token,
    int messageId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/admin/messages/$messageId/read"),
        headers: _getHeaders(token),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Mark admin message read error: $e');
      return false;
    }
  }

  // NEW: Delete message
  static Future<bool> deleteAdminMessage(String token, int messageId) async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/api/admin/messages/$messageId"),
        headers: _getHeaders(token),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Delete admin message error: $e');
      return false;
    }
  }

  // ========== DEBUG/TEST ==========
  static Future<Map<String, dynamic>> testAdminAccess(String token) async {
    try {
      print('🧪 Testing admin access...');

      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/test'),
        headers: {"Authorization": "Bearer $token"},
      );

      print('🧪 Test Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'status': false,
          'message': 'Test failed (${response.statusCode})',
        };
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  static Future<Map<String, dynamic>> getAdminProfile(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/profile'),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'status': true, 'profile': data['profile']};
      } else {
        return {'status': false, 'message': 'Failed to load profile'};
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  // NEW: Sensor history for charts
  static Future<Map<String, dynamic>> getSensorHistory(
    String token,
    String sensorName, {
    int hours = 24,
    int limit = 100,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/dashboard/sensor-history').replace(
          queryParameters: {
            'sensor': sensorName,
            'hours': hours.toString(),
            'limit': limit.toString(),
          },
        ),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'status': false, 'message': 'Failed to load sensor history'};
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  // NEW: Test database connection
  static Future<Map<String, dynamic>> testDatabase(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/debug/database'),
        headers: _getHeaders(token),
      );

      return jsonDecode(response.body);
    } catch (e) {
      return _handleError(e);
    }
  }

  static Future<List<dynamic>> getMessageReplies(
      String token, int messageId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/messages/$messageId/replies'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']['messages'] ?? [];
        }
      }
      return [];
    } catch (e) {
      print('Error getting replies: $e');
      return [];
    }
  }

  static Future<bool> sendReply(
      String token, int messageId, String content) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/messages/$messageId/reply'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'content': content,
        }),
      );

      if (response.statusCode == 201) {
        return true;
      }
      return false;
    } catch (e) {
      print('Error sending reply: $e');
      return false;
    }
  }

  static Future<List<dynamic>> getAllThreads(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/messages/threads'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']['threads'] ?? [];
        }
      }
      return [];
    } catch (e) {
      print('Error getting threads: $e');
      return [];
    }
  }
}
