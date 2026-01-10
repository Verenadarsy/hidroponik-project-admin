import 'dart:convert';
import 'dart:math';
import 'package:hidroponik_project_admin/models/chatthread.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sensor_model.dart';
import '../models/message_model.dart';

class ApiService {
  static const String baseUrl =
      'https://uncollapsable-overfly-blaine.ngrok-free.dev';

  // Helper untuk headers
  static Map<String, String> _getHeaders(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
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
          'ngrok-skip-browser-warning': 'true',
          'Accept': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      print('📥 Login Response Status: ${response.statusCode}');
      print('📥 Response Body: ${response.body}');

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

        // ✅ PERBAIKAN: Parsing ID dengan benar
        final prefs = await SharedPreferences.getInstance();

        // Debug userData structure
        print('📊 User Data Structure:');
        userData.forEach((key, value) {
          print('  $key: $value (${value.runtimeType})');
        });

        // Handle ID - bisa berupa String atau int
        final dynamic idValue = userData['id'];
        int adminId = 0;

        if (idValue != null) {
          if (idValue is int) {
            adminId = idValue;
          } else if (idValue is String) {
            try {
              adminId = int.parse(idValue);
            } catch (e) {
              print('⚠️ Cannot parse ID string: $idValue');
              adminId = 0;
            }
          } else if (idValue is double) {
            adminId = idValue.toInt();
          }
        }

        // Simpan data ke SharedPreferences
        await prefs.setString('token', token);
        await prefs.setInt('adminId', adminId);
        await prefs.setString(
          'adminName',
          userData['name']?.toString() ?? 'Admin',
        );
        await prefs.setString(
          'adminEmail',
          userData['email']?.toString() ?? '',
        );

        print('✅ Login successful for admin: ${userData['email']}');
        print('✅ Saved admin data - ID: $adminId, Name: ${userData['name']}');
        print('✅ Token saved: ${token.substring(0, min(20, token.length))}...');

        return {'status': true, 'token': token, 'user': userData};
      } else {
        return {
          'status': false,
          'message': responseData['message'] ?? 'Login gagal',
        };
      }
    } catch (e) {
      print('❌ Login error: $e');
      return {'status': false, 'message': 'Terjadi kesalahan: ${e.toString()}'};
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
        final decoded = jsonDecode(response.body);

        print('📊 decoded type: ${decoded.runtimeType}');
        print('📊 decoded[data] type: ${decoded['data']?.runtimeType}');

        return Map<String, dynamic>.from(decoded['data']);
      }

      if (response.statusCode == 401) {
        return {
          'status': false,
          'message': 'Session expired. Please login again.',
          'code': 401,
        };
      }

      if (response.statusCode == 403) {
        return {
          'status': false,
          'message': 'Access denied. Admin only.',
          'code': 403,
        };
      }

      return {
        'status': false,
        'message': 'Failed to load dashboard (${response.statusCode})',
        'code': response.statusCode,
      };
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
        headers: {
          "Authorization": "Bearer $token",
          'ngrok-skip-browser-warning': 'true',
        },
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
    String token,
    int messageId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/messages/$messageId/replies'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'ngrok-skip-browser-warning': 'true',
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

  static Future<Map<String, dynamic>> getUsers({
    required String token,
    int page = 1,
    int perPage = 10,
    String search = '',
  }) async {
    try {
      print('👥 Fetching users - Page: $page, Search: "$search"');

      final url = Uri.parse('$baseUrl/api/admin/users').replace(
        queryParameters: {
          'page': page.toString(),
          'per_page': perPage.toString(),
          if (search.isNotEmpty) 'search': search,
        },
      );

      final response = await http.get(url, headers: _getHeaders(token));
      print('👥 Users Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        print('👥 decoded type: ${decoded.runtimeType}');
        print('👥 data type: ${decoded['data']?.runtimeType}');
        print('👥 users type: ${decoded['data']?['users']?.runtimeType}');

        return Map<String, dynamic>.from(decoded);
      }

      if (response.statusCode == 401) {
        return {'status': false, 'message': 'Session expired', 'code': 401};
      }

      if (response.statusCode == 403) {
        return {'status': false, 'message': 'Access denied', 'code': 403};
      }

      return {
        'status': false,
        'message': 'Failed to load users (${response.statusCode})',
        'code': response.statusCode,
      };
    } catch (e) {
      return _handleError(e);
    }
  }

  // Tambah di ApiService.dart setelah getUserDetails()
  static Future<Map<String, dynamic>> createUser({
    required String token,
    required Map<String, dynamic> userData,
  }) async {
    try {
      print('👤 Creating new user with data: $userData');

      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/users'),
        headers: _getHeaders(token),
        body: jsonEncode(userData),
      );

      print('👤 Create User Response: ${response.statusCode}');
      print('👤 Response Body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Safe type casting
        final dynamic parsedJson = jsonDecode(response.body);
        if (parsedJson is Map) {
          return Map<String, dynamic>.from(parsedJson);
        }
        return {'status': false, 'message': 'Invalid response format'};
      } else if (response.statusCode == 400) {
        return {
          'status': false,
          'message': 'Bad request. Please check your data.',
        };
      } else if (response.statusCode == 409) {
        return {'status': false, 'message': 'Email already exists'};
      } else if (response.statusCode == 403) {
        return {'status': false, 'message': 'Access denied. Admin only.'};
      } else {
        return {
          'status': false,
          'message': 'Failed to create user (${response.statusCode})',
          'body': response.body,
        };
      }
    } catch (e) {
      print('❌ Error creating user: $e');
      return {
        'status': false,
        'message': 'Network error: ${e.toString()}',
        'error': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> updateUserStatus({
    required String token,
    required int userId,
    required bool isActive,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/admin/users/$userId'),
      headers: _getHeaders(token),
      body: jsonEncode({'is_active': isActive}),
    );

    final decoded = jsonDecode(response.body);

    print('🔄 updateUserStatus decoded type: ${decoded.runtimeType}');
    print('🔄 updateUserStatus data type: ${decoded['data']?.runtimeType}');

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    // CAST PAKSA (kasus LinkedMap)
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    throw Exception('Invalid response format');
  }

  static Future<Map<String, dynamic>> getUserDetails({
    required String token,
    required int userId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/users/$userId'),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'status': false, 'message': 'Failed to load user details'};
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  // Di getAllThreads method, perbaiki mapping:
  static Future<List<ChatThread>> getAllThreads(String token) async {
    try {
      print('📦 Fetching all threads...');

      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/messages/threads'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        print('📦 Threads response:');
        print('Success: ${data['success']}');
        print('Total threads: ${data['data']['total_threads']}');

        if (data['success'] == true && data['data']['threads'] != null) {
          final threads = data['data']['threads'] as List;
          final List<ChatThread> chatThreads = [];

          for (var thread in threads) {
            print('📦 Processing thread: ${thread['user_name']}');

            // Parse last message
            AdminMessage? lastAdminMessage;
            if (thread['last_message'] != null) {
              final lastMsg = thread['last_message'];
              lastAdminMessage = AdminMessage(
                id: lastMsg['id'],
                message: lastMsg['content'], // content dari last_message
                senderId: lastMsg['is_admin'] == true ? 0 : thread['user_id'],
                receiverId: null, // Tidak ada di response
                isRead: thread['unread_count'] == 0,
                timestamp: lastMsg['timestamp'] != null
                    ? DateTime.parse(lastMsg['timestamp'])
                    : null,
                sender: Sender(
                  id: thread['user_id'],
                  name: thread['user_name'],
                  email: thread['user_email'],
                ),
              );
            }

            // Create chat thread
            final chatThread = ChatThread(
              threadId: thread['thread_id']?.toString() ?? 'unknown',
              senderId: thread['user_id'],
              senderName: thread['user_name'] ?? 'User',
              senderEmail: thread['user_email'] ?? 'user@email.com',
              messages: lastAdminMessage != null ? [lastAdminMessage] : [],
              unreadCount: thread['unread_count'] ?? 0,
              lastMessageTime: thread['last_message']['timestamp'] != null
                  ? DateTime.parse(thread['last_message']['timestamp'])
                  : DateTime.now(),
              lastMessageId:
                  thread['last_message_id'] ?? thread['last_message']['id'],
            );

            chatThreads.add(chatThread);
          }

          print('📦 Successfully loaded ${chatThreads.length} threads');
          return chatThreads;
        }
      } else {
        print('❌ Threads API failed: ${response.statusCode}');
        print('Response: ${response.body}');
      }
      return [];
    } catch (e) {
      print('❌ Error getting threads: $e');
      return [];
    }
  }

  // Update getThreadMessages untuk parsing yang benar:
  static Future<Map<String, dynamic>> getThreadMessages({
    required String token,
    int? userId,
    String? threadId,
  }) async {
    try {
      print('💬 Fetching thread messages...');

      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/messages/thread').replace(
          queryParameters: {
            if (userId != null) 'user_id': userId.toString(),
            if (threadId != null) 'thread_id': threadId,
          },
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      print('💬 Thread messages response: ${response.statusCode}');

      if (response.statusCode != 200) {
        return {'success': false, 'message': 'HTTP ${response.statusCode}'};
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(
        jsonDecode(response.body),
      );

      if (data['success'] != true || data['data'] == null) {
        return {'success': false, 'message': 'Invalid response'};
      }

      // 🔥 INI KUNCI UTAMA
      final List rawMessages = data['data']['messages'] ?? [];

      final List<AdminMessage> messages = rawMessages
          .map((m) => AdminMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      return {
        'success': true,
        'data': {
          'thread_id': data['data']['thread_id'],
          'user': data['data']['user'],
          'messages': messages,
        },
      };
    } catch (e) {
      print('❌ Error getting thread messages: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<bool> sendNewMessage(
    String token,
    int userId,
    String message,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/messages/reply'),
        headers: {
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'user_id': userId, 'message': message}),
      );

      return response.statusCode == 201;
    } catch (e) {
      print('Error sending new message: $e');
      return false;
    }
  }

  // Method untuk membuat pesan baru (jika tidak ada thread)
  static Future<bool> createNewMessage({
    required String token,
    required int receiverId,
    required String message,
    required int senderId,
  }) async {
    try {
      print('📤 Creating new message to receiver: $receiverId');

      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/messages/new'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'receiver_id': receiverId,
          'message': message,
          'sender_id': senderId,
        }),
      );

      print('📥 Response Status: ${response.statusCode}');
      print('📥 Response Body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true || data['status'] == true;
      }

      return false;
    } catch (e) {
      print('❌ Error creating new message: $e');
      return false;
    }
  }

  // Method untuk mengirim pesan dalam thread (alternative)
  static Future<bool> sendMessageToThread({
    required String token,
    required String threadId,
    required String message,
    required int senderId,
  }) async {
    try {
      print('📤 Sending to thread: $threadId');

      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/messages/thread/$threadId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'message': message, 'sender_id': senderId}),
      );

      print('📥 Response: ${response.statusCode}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }

      return false;
    } catch (e) {
      print('❌ Error sending to thread: $e');
      return false;
    }
  }

  // Your existing sendReply method
  static Future<bool> sendReply({
    required String token,
    required int messageId,
    required String content,
  }) async {
    try {
      print('📤 Replying to message ID: $messageId');
      print('📤 Content: $content');

      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/messages/$messageId/reply'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'content': content}),
      );

      print('📥 Reply Response Status: ${response.statusCode}');
      print('📥 Reply Response Body: ${response.body}');

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('❌ Error sending reply: $e');
      return false;
    }
  }
}
