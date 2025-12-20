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
  final Color primary = const Color(0xFF2E7D32);
  final Color primaryLight = const Color(0xFF4CAF50);
  final Color primaryDark = const Color(0xFF1B5E20);

  // Neutral Colors
  final Color background = const Color(0xFFF5F7FA);
  final Color surface = Colors.white;
  final Color textPrimary = const Color(0xFF1A1A1A);
  final Color textSecondary = const Color(0xFF6B7280);

  // Accent Colors - minimal usage
  final Color accentBlue = const Color(0xFF2196F3);
  final Color accentOrange = const Color(0xFFFF9800);
  final Color accentRed = const Color(0xFFEF5350);
  final Color accentPurple = const Color(0xFF9C27B0);

  // Sensor Colors
  final Color tempColor = const Color(0xFFEF5350);
  final Color humidColor = const Color(0xFF42A5F5);
  final Color phColor = const Color(0xFF66BB6A);
  final Color ecColor = const Color(0xFFFFB74D);
  final Color lightColor = const Color(0xFFFFA726);
  final Color waterColor = const Color(0xFF29B6F6);

  // Backward compatibility getters
  Color get vibrantGreen => primary;
  Color get limeAccent => primaryLight;
  Color get mintCream => background;
  Color get darkTeal => primaryDark;
  Color get goldAccent => accentOrange;
  Color get coralRed => accentRed;
  Color get royalPurple => accentPurple;
  Color get steelBlue => accentBlue;
  Color get darkSlate => textPrimary;
  Color get darkGreen => primaryDark;
  Color get mediumGreen => primary;
  Color get deepForest => primaryDark;

  // Additional Colors// Design System Constants
  static const double radiusSmall = 12.0;
  static const double radiusMedium = 16.0;
  static const double radiusLarge = 20.0;
  static const double radiusXLarge = 24.0;

  static const double spacingXSmall = 8.0;
  static const double spacingSmall = 12.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;
  static const double spacingXLarge = 32.0;

  static const double fontSmall = 12.0;
  static const double fontMedium = 14.0;
  static const double fontLarge = 16.0;
  static const double fontXLarge = 20.0;
  static const double fontTitle = 24.0;

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

  // Air Quality data
    Map<String, dynamic>? airQualityData;
    bool airQualityLoading = false;
    String aqiStatus = 'Good';
    Color aqiColor = Colors.green;

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
    _fetchAirQualityData();

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
    if (hasError) return accentRed;
    return systemOnline ? primaryLight : accentRed;
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

    Future<void> _fetchAirQualityData() async {
      setState(() => airQualityLoading = true);

      try {
        final response = await http.get(
          Uri.parse('https://api.waqi.info/feed/bandung/?token=demo'),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // ✅ PERBAIKAN: Cek struktur response yang benar
          if (data['status'] == 'ok' && data['data'] != null) {
            setState(() {
              airQualityData = data;

              // ✅ PERBAIKAN: Ambil AQI langsung sebagai int
              final aqi = data['data']['aqi'] is int
                  ? data['data']['aqi']
                  : int.tryParse(data['data']['aqi'].toString()) ?? 0;

              // Set status berdasarkan AQI
              if (aqi <= 50) {
                aqiStatus = 'Good';
                aqiColor = Colors.green;
              } else if (aqi <= 100) {
                aqiStatus = 'Moderate';
                aqiColor = Colors.yellow;
              } else if (aqi <= 150) {
                aqiStatus = 'Unhealthy for Sensitive';
                aqiColor = Colors.orange;
              } else {
                aqiStatus = 'Unhealthy';
                aqiColor = Colors.red;
              }

              airQualityLoading = false;
            });
          } else {
            // ✅ Jika API gagal, gunakan data dummy
            setState(() {
              airQualityData = {
                'data': {'aqi': 55}
              };
              aqiStatus = 'Good';
              aqiColor = Colors.green;
              airQualityLoading = false;
            });
          }
        } else {
          setState(() => airQualityLoading = false);
        }
      } catch (e) {
        if (kDebugMode) print('Air quality error: $e');

        // ✅ FALLBACK: Gunakan data dummy jika error
        setState(() {
          airQualityData = {
            'data': {'aqi': 55}
          };
          aqiStatus = 'Good';
          aqiColor = Colors.green;
          airQualityLoading = false;
        });
      }
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
      backgroundColor: background,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.small(
        onPressed: _manualRefresh,
        backgroundColor: primary,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.refresh, size: 20),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Enhanced App bar dengan gradient dan efek glassmorphism
          SliverAppBar(
            expandedHeight: 160, // KURANGI dari 220
            floating: false,
            pinned: true,
            backgroundColor: primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  color: primary, // HAPUS gradient
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24), // KURANGI dari 40
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'HydroGrow Dashboard',
                                    style: TextStyle(
                                      fontSize: 24, // KONSISTEN
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Admin Panel',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Status badge - lebih kecil
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _getSystemStatusColor(),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _getSystemStatus(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.white.withOpacity(0.7),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Updated ${_getLastUpdateTime()}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                            if (totalMessages > 0) ...[
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: accentRed,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.notifications,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$totalMessages',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            elevation: 4, // KURANGI dari 15
            shadowColor: Colors.black26,
          ),
          // Main content
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ✅ WEATHER CARD - DI ATAS SYSTEM OVERVIEW
                Row(
                  children: [
                    // Weather Card - Compact
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(radiusMedium),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: weatherLoading
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : weatherData != null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _getWeatherIcon(
                                            _getCurrentWeatherCode(),
                                            size: 32,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${weatherData!['data'][0]['cuaca'][0][0]['t'] ?? '--'}°C',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  _getWeatherDesc(_getCurrentWeatherCode()),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : Center(
                                    child: Text(
                                      'No data',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Air Quality Card - Compact
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(radiusMedium),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: airQualityLoading
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : airQualityData != null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.air,
                                            size: 32,
                                            color: aqiColor,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${airQualityData!['data']['aqi']}',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: aqiColor,
                                                  ),
                                                ),
                                                Text(
                                                  aqiStatus,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : Center(
                                    child: Text(
                                      'No data',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24), // SPACING KONSISTEN

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
                          color: primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'System Overview',
                        style: TextStyle(
                          fontSize: fontXLarge,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
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
                          color: primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: primary.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 14,
                              color: primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Refresh',
                              style: TextStyle(
                                fontSize: fontSmall,
                                color: primary,
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
                      color: primary,
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
                                color: primaryLight,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Live Sensor Data',
                              style: TextStyle(
                                fontSize: fontXLarge,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: primary.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Real-time',
                                    style: TextStyle(
                                      fontSize: fontSmall,
                                      color: primary,
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
                                Colors.redAccent.withValues(alpha: 0.9),
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
                                Colors.blueAccent.withValues(alpha: 0.9),
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
                            color: phColor,
                            unit: 'pH Scale',
                            gradient: const LinearGradient(colors: []),
                          ),
                          _sensorCard(
                            title: 'EC Level',
                            value: ecLevel.toStringAsFixed(2),
                            icon: Icons.bolt_rounded,
                            color: ecColor,
                            unit: 'mS/cm',
                            gradient: const LinearGradient(colors: []),
                          ),
                          _sensorCard(
                            title: 'Light',
                            value: '${lightIntensity.toStringAsFixed(0)} Lux',
                            icon: Icons.light_mode_rounded,
                            color: Colors.amber,
                            unit: 'Lux',
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber.withValues(alpha: 0.9),
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
                            color: waterColor,
                            unit: 'Percent',
                            gradient: const LinearGradient(colors: []),
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
                                color: primaryLight,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Quick Actions',
                              style: TextStyle(
                                fontSize: fontXLarge,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_getTotalSensors()} Available',
                                style: TextStyle(
                                  fontSize: fontSmall,
                                  color: primary,
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
                            color: accentBlue,
                            gradient: const LinearGradient(colors: []),
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
                            color: primary,
                            gradient: const LinearGradient(colors: []),
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
                            color: accentPurple,
                            gradient: const LinearGradient(colors: []),
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
                            gradient: const LinearGradient(colors: []),
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
                            color: accentOrange,
                            gradient: const LinearGradient(colors: []),
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
                            color: Colors.grey.shade700,
                            gradient: const LinearGradient(colors: []),
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
                        primary.withOpacity(0.05),
                        primaryLight.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: primary.withOpacity(0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isLoading
                              ? Icons.sync_rounded
                              : Icons.info_outline_rounded,
                          color: primary,
                          size: 24,
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
                                fontSize: fontLarge,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
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
                                    color: primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: systemOnline ? 0.9 : 0.4,
                                    child: Container(
                                    decoration: BoxDecoration(
                                      color: systemOnline ? primaryLight : accentRed,
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
          color: primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: primary.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            const Text(
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
      backgroundColor: background,
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
                  colors: [accentRed, Colors.orangeAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accentRed.withOpacity(0.3),
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
                  color: textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: primary.withOpacity(0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
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
                      backgroundColor: primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 5,
                      shadowColor: primary.withOpacity(0.4),
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
                        side: BorderSide(color: primary, width: 2),
                      ),
                      elevation: 3,
                    ),
                    child: Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: primary,
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
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radiusMedium),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  subtitle.split(' ').last, // ambil kata terakhir aja
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sensorCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String unit,
    required LinearGradient gradient, // tidak dipakai lagi
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radiusMedium),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pollutantInfo(String label, String value, String unit) {
  return Column(
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
      ),
      Text(
        unit,
        style: TextStyle(
          fontSize: 10,
          color: primary,
        ),
      ),
    ],
  );
}

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required LinearGradient gradient, // tidak dipakai
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radiusMedium),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(radiusMedium),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: accentRed,
                          shape: BoxShape.circle,
                          border: Border.all(color: surface, width: 2),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Center(
                          child: Text(
                            badgeCount > 9 ? '9+' : badgeCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
