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
  // Enhanced Color palette - lebih bold dan modern
  final Color deepForest = const Color(0xFF1B4D3E);
  final Color vibrantGreen = const Color(0xFF2E8B57);
  final Color limeAccent = const Color(0xFF9ACD32);
  final Color mintCream = const Color(0xFFF5FFFA);
  final Color darkTeal = const Color(0xFF006D5B);
  final Color goldAccent = const Color(0xFFFFD700);
  final Color coralRed = const Color(0xFFFF6B6B);
  final Color royalPurple = const Color(0xFF6A5ACD);
  final Color steelBlue = const Color(0xFF4682B4);
  final Color darkSlate = const Color(0xFF2F4F4F);

  // Gradient colors
  final LinearGradient primaryGradient = const LinearGradient(
    colors: [Color(0xFF1B4D3E), Color(0xFF2E8B57)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  final LinearGradient accentGradient = const LinearGradient(
    colors: [Color(0xFF9ACD32), Color(0xFFFFFF00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Weather colors
  final Color weatherBlue = const Color(0xFFA8D8EA);
  final Color weatherLightBlue = const Color(0xFF7FC4DD);
  final Color weatherSun = const Color(0xFFFDB813);
  final Color weatherCloud = const Color(0xFFA8D8EA);

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
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == true) {
          final stats = data['data'];

          setState(() {
            // 1. User Statistics
            activeUsers = stats['users']['active'] ?? 1;

            // 2. PERBAIKAN: Ambil jumlah pesan dari stats dashboard
            // Prioritaskan 'unread', fallback ke 'total_today'
            totalMessages = stats['messages']?['unread'] ?? 0;

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
    if (hasError) return coralRed;
    return systemOnline ? limeAccent : coralRed;
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
        Uri.parse(
          'https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=$adm4Code',
        ),
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
              child: Icon(Icons.wb_sunny, size: size * 0.7, color: weatherSun),
            ),
            Positioned(
              right: 0,
              bottom: size * 0.1,
              child: Icon(Icons.cloud, size: size * 0.5, color: weatherCloud),
            ),
          ],
        ),
      );
    }

    IconData iconData;
    Color iconColor = weatherCloud;

    if (code == 0) {
      iconData = Icons.wb_sunny;
      iconColor = weatherSun;
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
      backgroundColor: mintCream,
      floatingActionButton: FloatingActionButton(
        onPressed: _manualRefresh,
        backgroundColor: vibrantGreen,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white, width: 2),
        ),
        child: isLoading
            ? CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
            : const Icon(Icons.refresh_rounded, size: 26),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Enhanced App bar dengan gradient dan efek glassmorphism
          SliverAppBar(
            expandedHeight: 220,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [deepForest.withOpacity(0.9), darkTeal],
                    stops: const [0.0, 1.0],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(40),
                    bottomRight: Radius.circular(40),
                  ),
                ),
                child: Stack(
                  children: [
                    // Background pattern
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Opacity(
                        opacity: 0.1,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: accentGradient,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -50,
                      left: -50,
                      child: Opacity(
                        opacity: 0.1,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: accentGradient,
                          ),
                        ),
                      ),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 60),
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: accentGradient,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome Back,',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withOpacity(0.9),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'HydroGrow Admin',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 12,
                                      color: _getSystemStatusColor(),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _getSystemStatus(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Icon(
                                Icons.update_rounded,
                                size: 16,
                                color: Colors.white.withOpacity(0.8),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Last update: ${_getLastUpdateTime()}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              if (totalMessages > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: accentGradient,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: limeAccent.withOpacity(0.4),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.notifications_active_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$totalMessages New',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
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
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
            elevation: 15,
            shadowColor: deepForest.withOpacity(0.5),
            backgroundColor: deepForest,
            actions: [
              if (isLoading)
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
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
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        weatherBlue.withOpacity(0.15),
                        weatherLightBlue.withOpacity(0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: weatherBlue.withOpacity(0.3)),
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
                                color: vibrantGreen,
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Loading weather...',
                              style: TextStyle(
                                fontSize: 14,
                                color: deepForest,
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
                              child: _getWeatherIcon(
                                _getCurrentWeatherCode(),
                                size: 36,
                              ),
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
                                        color: deepForest.withOpacity(0.7),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        selectedCity,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: deepForest.withOpacity(0.8),
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
                                      color: deepForest,
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
                                    color: deepForest,
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
                            Icon(
                              Icons.cloud_off,
                              color: Colors.grey.shade400,
                              size: 24,
                            ),
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

                // Stats cards dengan layout baru
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                gradient: accentGradient,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'System Overview',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: deepForest,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const Spacer(),
                            _buildRefreshButton(),
                          ],
                        ),
                      ),
                      // Grid Stats dengan card modern
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.2,
                        children: [
                          _statCard(
                            title: 'Active Users',
                            value: activeUsers.toString(),
                            icon: Icons.supervisor_account_rounded,
                            color: steelBlue,
                            subtitle: 'Users online',
                            accentColor: steelBlue,
                          ),
                          _statCard(
                            title: 'Total Sensors',
                            value: _getTotalSensors().toString(),
                            icon: Icons.device_hub_rounded,
                            color: vibrantGreen,
                            subtitle: 'Active sensors',
                            accentColor: limeAccent,
                          ),
                          _statCard(
                            title: 'Messages',
                            value: totalMessages.toString(),
                            icon: Icons.forum_rounded,
                            color: royalPurple,
                            subtitle: 'Unread',
                            accentColor: Colors.purpleAccent,
                          ),
                          _statCard(
                            title: 'System Status',
                            value: _getSystemStatus(),
                            icon: Icons.cloud_rounded,
                            color: _getSystemStatusColor(),
                            subtitle: systemOnline
                                ? 'Optimal'
                                : 'Needs attention',
                            accentColor: _getSystemStatusColor(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Live Sensor Data section
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                gradient: accentGradient,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Live Sensor Data',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: deepForest,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: vibrantGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: vibrantGreen.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: vibrantGreen,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Real-time',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: vibrantGreen,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Sensor Grid dengan card lebih menarik
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.1,
                        children: [
                          _sensorCard(
                            title: 'Temperature',
                            value: '${temperature.toStringAsFixed(1)}°C',
                            icon: Icons.thermostat_auto_rounded,
                            color: Colors.redAccent,
                            unit: 'Celsius',
                            gradient: LinearGradient(
                              colors: [
                                Colors.redAccent.withOpacity(0.9),
                                Colors.orangeAccent,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          _sensorCard(
                            title: 'Humidity',
                            value: '${humidity.toStringAsFixed(1)}%',
                            icon: Icons.water_drop_rounded,
                            color: Colors.blueAccent,
                            unit: 'Percent',
                            gradient: LinearGradient(
                              colors: [
                                Colors.blueAccent.withOpacity(0.9),
                                Colors.lightBlueAccent,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          _sensorCard(
                            title: 'pH Level',
                            value: phLevel.toStringAsFixed(2),
                            icon: Icons.science_rounded,
                            color: vibrantGreen,
                            unit: 'pH Scale',
                            gradient: LinearGradient(
                              colors: [
                                vibrantGreen.withOpacity(0.9),
                                limeAccent,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          _sensorCard(
                            title: 'EC Level',
                            value: ecLevel.toStringAsFixed(2),
                            icon: Icons.bolt_rounded,
                            color: goldAccent,
                            unit: 'mS/cm',
                            gradient: LinearGradient(
                              colors: [
                                goldAccent.withOpacity(0.9),
                                Colors.amberAccent,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          _sensorCard(
                            title: 'Light',
                            value: '${lightIntensity.toStringAsFixed(0)} Lux',
                            icon: Icons.light_mode_rounded,
                            color: Colors.amber,
                            unit: 'Lux',
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber.withOpacity(0.9),
                                Colors.yellowAccent,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          _sensorCard(
                            title: 'Water Level',
                            value: '${waterLevel.toStringAsFixed(0)}%',
                            icon: Icons.waves_rounded,
                            color: steelBlue,
                            unit: 'Percent',
                            gradient: LinearGradient(
                              colors: [
                                steelBlue.withOpacity(0.9),
                                Colors.lightBlueAccent,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Quick Actions section
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                gradient: accentGradient,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Quick Actions',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: deepForest,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: deepForest.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_getTotalSensors()} Available',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: deepForest,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Quick actions dengan card modern
                      Column(
                        children: [
                          _actionCard(
                            icon: Icons.people_outline_rounded,
                            title: 'User Management',
                            subtitle: 'Manage system users & permissions',
                            color: steelBlue,
                            gradient: LinearGradient(
                              colors: [
                                steelBlue.withOpacity(0.9),
                                Colors.lightBlueAccent,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const UsersPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _actionCard(
                            icon: Icons.sensors_rounded,
                            title: 'Sensor Dashboard',
                            subtitle: 'Detailed sensor analytics & control',
                            color: vibrantGreen,
                            gradient: LinearGradient(
                              colors: [
                                vibrantGreen.withOpacity(0.9),
                                limeAccent,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            badgeCount: _getTotalSensors(),
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
                          const SizedBox(height: 12),
                          _actionCard(
                            icon: Icons.analytics_rounded,
                            title: 'Analytics Center',
                            subtitle: 'Performance reports & insights',
                            color: royalPurple,
                            gradient: LinearGradient(
                              colors: [
                                royalPurple.withOpacity(0.9),
                                Colors.purpleAccent,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AnalyticsPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _actionCard(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'Message Center',
                            subtitle: 'View & respond to user messages',
                            color: Colors.teal,
                            gradient: LinearGradient(
                              colors: [
                                Colors.teal.withOpacity(0.9),
                                Colors.tealAccent,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            badgeCount: totalMessages,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MessagesPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _actionCard(
                            icon: Icons.settings_rounded,
                            title: 'System Settings',
                            subtitle: 'Configure system parameters',
                            color: goldAccent,
                            gradient: LinearGradient(
                              colors: [
                                goldAccent.withOpacity(0.9),
                                Colors.amberAccent,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingsPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _actionCard(
                            icon: Icons.history_toggle_off_rounded,
                            title: 'Activity Log',
                            subtitle: 'System events & audit trail',
                            color: darkSlate,
                            gradient: LinearGradient(
                              colors: [
                                darkSlate.withOpacity(0.9),
                                Colors.grey.shade600,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LogsPage(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // System Info card dengan glassmorphism effect
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        deepForest.withOpacity(0.05),
                        vibrantGreen.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: vibrantGreen.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: accentGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: limeAccent.withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                          isLoading
                              ? Icons.sync_rounded
                              : Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'System Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: deepForest,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isLoading
                                  ? 'Fetching live data from sensors...'
                                  : '${allSensors.length} sensor readings • '
                                        '${_getTotalSensors()} active sensors • '
                                        '$totalMessages new messages\n'
                                        'Last updated: ${_getLastUpdateTime()}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                height: 1.6,
                              ),
                            ),
                            if (!isLoading)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: vibrantGreen.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: systemOnline ? 0.9 : 0.4,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: systemOnline
                                            ? accentGradient
                                            : LinearGradient(
                                                colors: [
                                                  coralRed,
                                                  Colors.orangeAccent,
                                                ],
                                              ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshButton() {
    return InkWell(
      onTap: _manualRefresh,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [vibrantGreen, darkTeal],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: vibrantGreen.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'Refresh',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: mintCream,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [coralRed, Colors.orangeAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: coralRed.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Oops! Something went wrong',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: deepForest,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: vibrantGreen.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Text(
                  errorMessage,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: deepForest,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 5,
                      shadowColor: deepForest.withOpacity(0.4),
                    ),
                    child: const Text(
                      'Back to Login',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _manualRefresh,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: vibrantGreen, width: 2),
                      ),
                      elevation: 3,
                    ),
                    child: Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: vibrantGreen,
                      ),
                    ),
                  ),
                ],
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
    required Color accentColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
            Colors.white.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withOpacity(0.2),
                        accentColor.withOpacity(0.3),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 0.5,
                    ),
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
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: deepForest.withOpacity(0.9),
                  ),
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
    required LinearGradient gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Colors.white, color.withOpacity(0.05)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unit,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 0.5,
                    ),
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
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: deepForest,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
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
    required LinearGradient gradient,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withOpacity(0.2),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, color.withOpacity(0.05)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: coralRed,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: coralRed.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : badgeCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: deepForest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
