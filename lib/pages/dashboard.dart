import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/shared.dart';
import '../models/sensor_model.dart';
import 'user.dart';
import 'sensor.dart';
import 'analytics.dart';
import 'setting.dart';
import 'log.dart';
import 'messages.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Color palette
  final Color darkGreen = const Color(0xFF456028);
  final Color mediumGreen = const Color(0xFF94A65E);
  final Color lightGreen = const Color(0xFFDDDDA1);
  final Color creamBackground = const Color(0xFFF8F9FA);
  final Color accentBlue = const Color(0xFF5A86AD);
  final Color accentOrange = const Color(0xFFD18B47);
  final Color accentRed = const Color(0xFFC94B4B);
  final Color accentPurple = const Color(0xFF7B68B5);

  // API endpoint - PASTIKAN SAMA DENGAN BACKEND
  static const String baseUrl = 'http://localhost:5000';

  // State variables
  List<SensorData> allSensors = [];
  int activeUsers = 0;
  int totalMessages = 0;
  bool systemOnline = true;
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';
  Timer? _refreshTimer;
  String? _token;

  // Statistik dari sensor data
  double temperature = 0;
  double humidity = 0;
  double phLevel = 0;
  double ecLevel = 0;
  double lightIntensity = 0;
  double waterLevel = 0;

  // Weather data
  Map<String, dynamic>? weatherData;
  bool weatherLoading = false;
  String selectedCity = 'Bandung';
  final Map<String, String> locations = {
    'Bandung': '32.73.19.1001',
    'Jakarta': '31.71.04.1001',
    'Surabaya': '35.78.13.1001',
    'Yogyakarta': '34.71.05.1001',
  };

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeData() async {
    // Ambil token dari shared preferences
    _token = await SharedService.getToken();

    if (_token == null || _token!.isEmpty) {
      _handleTokenError('Session expired. Please login again.');
      return;
    }

    // Load data pertama kali
    await _loadAllData();
    _fetchWeatherData();

    // Setup auto refresh setiap 10 detik
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadAllData();
    });
  }


  void _handleTokenError(String message) {
    setState(() {
      hasError = true;
      errorMessage = message;
      isLoading = false;
    });

    // Redirect ke login setelah 2 detik
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  Future<void> _loadAllData() async {
    if (_token == null || _token!.isEmpty) {
      _handleTokenError('No authentication token found');
      return;
    }

    try {
      setState(() {
        hasError = false;
        errorMessage = '';
      });

      await Future.wait([_loadDashboardStats(), _loadSensorDataFallback()]);

      setState(() => isLoading = false);
    } catch (e) {
      if (kDebugMode) {
        print('Error loading data: $e');
      }
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'Failed to load data: $e';
      });
    }
  }

  Future<void> _loadDashboardStats() async {
    try {
      final url = Uri.parse('$baseUrl/api/admin/dashboard/stats');
      if (kDebugMode) {
        print('🌐 Fetching dashboard stats from: $url');
      }

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );

      if (kDebugMode) {
        print('📥 Dashboard Response Status: ${response.statusCode}');
        print('📥 Dashboard Response Body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == true) {
          final stats = data['data'];

          setState(() {
            // 1. User Statistics
            activeUsers = stats['users']['active'] ?? 1;

            // 2. Update message count dari dashboard stats
            totalMessages =
                (stats['messages']?['total_today'] as num?)?.toInt() ?? 0;

            // 3. Sensor Statistics
            final sensorStats = stats['sensors'];
            final sensorReadings = sensorStats['latest_readings'] ?? {};

            // Update nilai sensor dari latest readings
            temperature = (sensorReadings['dht_temp']?['value'] ?? 0.0)
                .toDouble();
            humidity = (sensorReadings['dht_humid']?['value'] ?? 0.0)
                .toDouble();
            phLevel = (sensorReadings['ph']?['value'] ?? 0.0).toDouble();
            ecLevel = (sensorReadings['ec']?['value'] ?? 0.0).toDouble();
            lightIntensity = (sensorReadings['ldr']?['value'] ?? 0.0)
                .toDouble();
            waterLevel = (sensorReadings['ultrasonic']?['value'] ?? 0.0)
                .toDouble();

            // 4. System Status
            systemOnline = stats['system_status'] == 'online';

            // 5. Update allSensors untuk backward compatibility
            _updateAllSensorsFromReadings(sensorReadings);
          });

          // Juga load messages untuk badge (unread count)
          await _loadMessageCount();

          return;
        }
      }

      // Handle error responses
      if (response.statusCode == 401) {
        // Unauthorized - token expired
        _handleTokenError('Session expired. Please login again.');
        return;
      } else if (response.statusCode == 403) {
        // Forbidden - not admin
        _handleTokenError('Access denied. Admin permission required.');
        return;
      } else if (response.statusCode == 404) {
        if (kDebugMode) {
          print('⚠️ Admin endpoint not found (404), using fallback data');
        }
        _useFallbackData();
      } else {
        if (kDebugMode) {
          print('⚠️ Unexpected response: ${response.statusCode}');
        }
        _useFallbackData();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading dashboard stats: $e');
      }
      _useFallbackData();
    }
  }

  // Method baru untuk load message count
  Future<void> _loadMessageCount() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/user/messages/count'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          // Prioritaskan unread_count jika tersedia, jika tidak gunakan total
          totalMessages = data['unread_count'] ?? data['total'] ?? 0;

          if (kDebugMode) {
            print('📊 Message count loaded: $totalMessages');
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading message count: $e');
      }
      // Tetap gunakan nilai dari dashboard stats jika error
    }
  }

  void _useFallbackData() {
    // Fallback ke data default jika endpoint admin belum tersedia
    setState(() {
      activeUsers = 1; // Hanya admin
      totalMessages = 0; // Belum ada messages
      systemOnline = allSensors.isNotEmpty;
    });
  }

  void _updateAllSensorsFromReadings(Map<String, dynamic> readings) {
    List<SensorData> updatedSensors = [];
    final now = DateTime.now();

    readings.forEach((sensorName, data) {
      if (data != null && data['value'] != null) {
        try {
          final timestamp = data['timestamp'] != null
              ? DateTime.parse(data['timestamp'])
              : now;

          final sensorData = SensorData(
            sensorName: sensorName,
            value: (data['value'] as num).toDouble(),
            timestamp: timestamp,
          );
          updatedSensors.add(sensorData);
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing sensor $sensorName: $e');
          }
        }
      }
    });

    if (updatedSensors.isNotEmpty) {
      setState(() {
        allSensors = updatedSensors;
      });
    }
  }

  Future<void> _loadSensorDataFallback() async {
    // Fallback method jika endpoint admin tidak tersedia
    try {
      final url = Uri.parse('$baseUrl/api/get_sensor_data');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final List data = jsonData['data'] ?? [];

        final List<SensorData> sensors = data
            .map((e) => SensorData.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        setState(() {
          allSensors = sensors;
          // Update individual values
          temperature = _getLatestValue('dht_temp');
          humidity = _getLatestValue('dht_humid');
          phLevel = _getLatestValue('ph');
          ecLevel = _getLatestValue('ec');
          lightIntensity = _getLatestValue('ldr');
          waterLevel = _getLatestValue('ultrasonic');
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading fallback sensor data: $e');
      }
    }
  }

  double _getLatestValue(String sensorName) {
    final items = allSensors.where((e) => e.sensorName == sensorName).toList();
    if (items.isNotEmpty) {
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items.first.value;
    }
    return 0.0;
  }

  int _getTotalSensors() {
    // Jika ada data sensor langsung, hitung dari nilai yang ada
    int count = 0;
    if (temperature > 0) count++;
    if (humidity > 0) count++;
    if (phLevel > 0) count++;
    if (ecLevel > 0) count++;
    if (lightIntensity > 0) count++;
    if (waterLevel > 0) count++;

    // Jika masih 0, coba dari allSensors
    if (count == 0 && allSensors.isNotEmpty) {
      final uniqueSensors = allSensors.map((e) => e.sensorName).toSet();
      return uniqueSensors.length;
    }

    return count;
  }

  String _getSystemStatus() {
    if (isLoading) return 'Loading...';
    if (hasError) return 'Error';
    return systemOnline ? 'Online' : 'Offline';
  }

  Color _getSystemStatusColor() {
    if (isLoading) return Colors.grey;
    if (hasError) return Colors.orange;
    return systemOnline ? Colors.green : Colors.red;
  }

    String _getLastUpdateTime() {
    if (allSensors.isEmpty) {
      return 'No data';
    }

    final latest = allSensors.reduce(
      (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
    );

    final difference = DateTime.now().difference(latest.timestamp);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  // Method untuk fetch weather data
  Future<void> _fetchWeatherData() async {
    setState(() => weatherLoading = true);

    try {
      final adm4Code = locations[selectedCity]!;
      final response = await http.get(
        Uri.parse('https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=$adm4Code'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          weatherData = data;
          weatherLoading = false;
        });
      } else {
        setState(() => weatherLoading = false);
      }
    } catch (e) {
      if (kDebugMode) print('Weather error: $e');
      setState(() => weatherLoading = false);
    }
  }

  int? _getCurrentWeatherCode() {
    if (weatherData == null) return null;
    final data = weatherData!['data'];
    if (data == null || data.isEmpty) return null;
    final cuacaList = data[0]['cuaca'] ?? [];
    if (cuacaList.isEmpty || cuacaList[0].isEmpty) return null;
    return cuacaList[0][0]['weather'] as int?;
  }

  Widget _getWeatherIcon(int? code, {double size = 28}) {
    if (code == null) return Icon(Icons.cloud, size: size, color: Colors.grey);

    // Mostly Clear - matahari + awan
    if (code == 1) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              top: size * 0.1,
              child: Icon(Icons.wb_sunny, size: size * 0.7, color: const Color(0xFFFDB813)),
            ),
            Positioned(
              right: 0,
              bottom: size * 0.1,
              child: Icon(Icons.cloud, size: size * 0.5, color: const Color(0xFFA8D8EA)),
            ),
          ],
        ),
      );
    }

    IconData iconData;
    Color iconColor = const Color(0xFFA8D8EA);

    if (code == 0) {
      iconData = Icons.wb_sunny;
      iconColor = const Color(0xFFFDB813);
    } else if (code == 2) {
      iconData = Icons.cloud_queue;
    } else if (code == 3) {
      iconData = Icons.cloud;
    } else if (code >= 60 && code <= 63) {
      iconData = Icons.cloudy_snowing;
    } else if (code >= 95 && code <= 97) {
      iconData = Icons.thunderstorm;
    } else {
      iconData = Icons.cloud;
    }

    return Icon(iconData, size: size, color: iconColor);
  }

  String _getWeatherDesc(int? code) {
    if (code == null) return 'Unknown';
    if (code == 0) return 'Sunny';
    if (code == 1) return 'Mostly Clear';
    if (code == 2) return 'Partly Cloudy';
    if (code == 3) return 'Cloudy';
    if (code >= 60 && code <= 63) return 'Rainy';
    if (code >= 95 && code <= 97) return 'Thunderstorm';
    return 'Cloudy';
  }


  Future<void> _manualRefresh() async {
    setState(() {
      isLoading = true;
      hasError = false;
    });
    await _loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    // Tampilkan error screen jika ada error
    if (hasError && !isLoading) {
      return _buildErrorScreen();
    }

    return Scaffold(
      backgroundColor: creamBackground,
      floatingActionButton: FloatingActionButton(
        onPressed: _manualRefresh,
        backgroundColor: darkGreen,
        child: isLoading
            ? CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
            : const Icon(Icons.refresh_rounded, color: Colors.white),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App bar with gradient
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [darkGreen, mediumGreen],
                    stops: const [0.0, 0.9],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative circles
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: lightGreen.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -40,
                      left: -40,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          color: lightGreen.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 60),
                          Text(
                            'Hi, Admin 👋',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Welcome to HydroGrow Admin Panel',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Last update: ${_getLastUpdateTime()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.8),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            elevation: 10,
            shadowColor: darkGreen.withOpacity(0.3),
            actions: [
              if (isLoading)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),
              // Badge untuk messages
              if (totalMessages > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 8),
                  child: Badge(
                    backgroundColor: Colors.red,
                    textColor: Colors.white,
                    label: Text(
                      totalMessages > 99 ? '99+' : totalMessages.toString(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Icon(
                      Icons.message_rounded,
                      color: Colors.white.withOpacity(0.9),
                      size: 22,
                    ),
                  ),
                ),
            ],
          ),

          // Main content
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ✅ WEATHER CARD - DI ATAS SYSTEM OVERVIEW
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFA8D8EA).withOpacity(0.15),
                        const Color(0xFF7FC4DD).withOpacity(0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFA8D8EA).withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: weatherLoading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: mediumGreen,
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Loading weather...',
                              style: TextStyle(
                                fontSize: 14,
                                color: darkGreen,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      : weatherData != null
                          ? Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: _getWeatherIcon(_getCurrentWeatherCode(), size: 36),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.location_on,
                                            size: 14,
                                            color: darkGreen.withOpacity(0.7),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            selectedCity,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: darkGreen.withOpacity(0.8),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _getWeatherDesc(_getCurrentWeatherCode()),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: darkGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${weatherData!['data'][0]['cuaca'][0][0]['t'] ?? '--'}°',
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        color: darkGreen,
                                        height: 1,
                                      ),
                                    ),
                                    Text(
                                      'Celsius',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_off, color: Colors.grey.shade400, size: 24),
                                const SizedBox(width: 12),
                                Text(
                                  'Weather unavailable',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                ),

                const SizedBox(height: 24),


                // Stats cards title
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [darkGreen, mediumGreen],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'System Overview',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: darkGreen,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _manualRefresh,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: mediumGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: mediumGreen.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.refresh_rounded,
                                size: 14,
                                color: mediumGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Refresh',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: mediumGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Stats grid
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.15,
                  ),
                  children: [
                    _statCard(
                      title: 'Active Users',
                      value: activeUsers.toString(),
                      icon: Icons.people_alt_rounded,
                      color: accentBlue,
                      subtitle: activeUsers > 1
                          ? '$activeUsers users'
                          : 'Admin only',
                    ),
                    _statCard(
                      title: 'Total Sensors',
                      value: _getTotalSensors().toString(),
                      icon: Icons.sensors_rounded,
                      color: mediumGreen,
                      subtitle: '${allSensors.length} readings',
                    ),
                    _statCard(
                      title: 'Messages',
                      value: totalMessages.toString(),
                      icon: Icons.message_rounded,
                      color: accentPurple,
                      subtitle: totalMessages > 0
                          ? '$totalMessages new'
                          : 'No new messages',
                    ),
                    _statCard(
                      title: 'System Status',
                      value: _getSystemStatus(),
                      icon: Icons.wifi_tethering_rounded,
                      color: _getSystemStatusColor(),
                      subtitle: systemOnline
                          ? 'All systems go'
                          : 'Check system',
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Sensor Data title
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [darkGreen, mediumGreen],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Live Sensor Data',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: darkGreen,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Sensor Data Grid
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.3,
                  ),
                  children: [
                    _sensorCard(
                      title: 'Temperature',
                      value: '${temperature.toStringAsFixed(1)}°C',
                      icon: Icons.thermostat_rounded,
                      color: Colors.red.shade400,
                      unit: 'Celsius',
                    ),
                    _sensorCard(
                      title: 'Humidity',
                      value: '${humidity.toStringAsFixed(1)}%',
                      icon: Icons.water_drop_rounded,
                      color: Colors.blue.shade400,
                      unit: 'Percent',
                    ),
                    _sensorCard(
                      title: 'pH Level',
                      value: phLevel.toStringAsFixed(2),
                      icon: Icons.science_rounded,
                      color: mediumGreen,
                      unit: 'pH',
                    ),
                    _sensorCard(
                      title: 'EC Level',
                      value: ecLevel.toStringAsFixed(2),
                      icon: Icons.bolt_rounded,
                      color: accentOrange,
                      unit: 'mS/cm',
                    ),
                    _sensorCard(
                      title: 'Light',
                      value: '${lightIntensity.toStringAsFixed(0)} Lux',
                      icon: Icons.light_mode_rounded,
                      color: Colors.yellow.shade700,
                      unit: 'Lux',
                    ),
                    _sensorCard(
                      title: 'Water Level',
                      value: '${waterLevel.toStringAsFixed(0)}%',
                      icon: Icons.waves_rounded,
                      color: accentBlue,
                      unit: 'Percent',
                    ),
                  ],
                ),

                // Quick Actions title
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [darkGreen, mediumGreen],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: darkGreen,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Quick actions cards
                _actionCard(
                  icon: Icons.people_outline_rounded,
                  title: 'Manage Users',
                  subtitle: 'View, add, or remove users',
                  color: accentBlue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UsersPage()),
                    );
                  },
                ),

                _actionCard(
                  icon: Icons.sensors_outlined,
                  title: 'Sensor Details',
                  subtitle: 'View detailed sensor data',
                  color: mediumGreen,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SensorDetailPage(
                          sensorName: 'dht_temp',
                          displayName: 'Temperature',
                        ),
                      ),
                    );
                  },
                ),

                _actionCard(
                  icon: Icons.analytics_outlined,
                  title: 'Analytics',
                  subtitle: 'View system performance reports',
                  color: accentPurple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AnalyticsPage()),
                    );
                  },
                ),

                _actionCard(
                  icon: Icons.message_outlined,
                  title: 'User Messages',
                  subtitle: 'View and manage user messages',
                  color: Colors.teal,
                  badgeCount: totalMessages,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MessagesPage()),
                    );
                  },
                ),

                _actionCard(
                  icon: Icons.settings_outlined,
                  title: 'System Settings',
                  subtitle: 'Configure system parameters',
                  color: accentOrange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                ),

                _actionCard(
                  icon: Icons.history_rounded,
                  title: 'Activity Log',
                  subtitle: 'View system activity history',
                  color: Colors.grey.shade600,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LogsPage()),
                    );
                  },
                ),

                const SizedBox(height: 20),

                // Info card dengan data real
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        darkGreen.withOpacity(0.05),
                        mediumGreen.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: mediumGreen.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: mediumGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isLoading
                              ? Icons.sync_rounded
                              : Icons.info_outline_rounded,
                          color: darkGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'System Information',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: darkGreen,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isLoading
                                  ? 'Loading data from database...'
                                  : 'Last update: ${_getLastUpdateTime()}\n'
                                        '${allSensors.length} sensor readings\n'
                                        '${_getTotalSensors()} active sensors\n'
                                        '$totalMessages unread messages',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: creamBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 80, color: accentRed),
              const SizedBox(height: 24),
              Text(
                'Oops! Something went wrong',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: darkGreen,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: darkGreen,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Back to Login',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _manualRefresh,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: darkGreen.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sensorCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String unit,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const Spacer(),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: darkGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        shadowColor: Colors.black.withOpacity(0.05),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: color.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      Icon(icon, color: color, size: 22),
                      if (badgeCount != null && badgeCount > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : badgeCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: darkGreen,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
