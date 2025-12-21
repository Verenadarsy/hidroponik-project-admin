import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../services/shared.dart';
import '../models/sensor_model.dart';
import 'user.dart';
import 'sensor.dart';
import 'analytics.dart';
import 'setting.dart';
import 'log.dart';
import 'messages.dart';
import 'splash_screen.dart'; // Import splash screen
import 'login.dart'; // Import login page

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Nature-inspired color palette (SAMA dengan user dashboard)
  final Color deepGreen = const Color(0xFF1B4332);
  final Color forestGreen = const Color(0xFF2D6A4F);
  final Color leafGreen = const Color(0xFF52B788);
  final Color mintGreen = const Color(0xFF95D5B2);
  final Color waterBlue = const Color(0xFF40916C);
  final Color sunlightOrange = const Color(0xFFF48C06);
  final Color soilBrown = const Color(0xFF6F4E37);
  final Color bgGradientStart = const Color(0xFFF8FDF9);
  final Color bgGradientEnd = const Color(0xFFE8F4EA);

  // Additional admin-specific colors
  final Color adminBlue = const Color(0xFF2196F3);
  final Color adminPurple = const Color(0xFF9C27B0);
  final Color adminRed = const Color(0xFFEF5350);

  // API endpoint
  static const String baseUrl = 'http://localhost:5000';

  // State variables
  int _selectedIndex = 0;
  Timer? _refreshTimer;
  String? _token;

  // Sensor data
  double temperature = 0;
  double humidity = 0;
  double phLevel = 0;
  double ecLevel = 0;
  double lightIntensity = 0;
  double waterLevel = 0;
  List<SensorData> allSensors = [];

  // Admin stats
  int activeUsers = 0;
  int totalMessages = 0;
  bool systemOnline = true;
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';

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

    // Setup auto refresh setiap 5 detik (sama seperti user dashboard)
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
      // ignore: use_build_context_synchronously
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
        try {
          final Map<String, dynamic> data = jsonDecode(response.body);

          if (data['status'] == true) {
            final stats = data['data'] as Map<String, dynamic>? ?? {};

            if (kDebugMode) {
              print('📊 Stats keys: ${stats.keys.toList()}');
            }

            setState(() {
              // 1. User Statistics
              final users = stats['users'] as Map<String, dynamic>? ?? {};
              activeUsers = (users['active'] as int?) ?? 1;
              if (activeUsers == 1) {
                activeUsers = (users['total'] as int?) ?? 1;
              }

              // 2. Messages
              final messages = stats['messages'] as Map<String, dynamic>?;
              totalMessages =
                  messages?['unread'] as int? ??
                  messages?['total_today'] as int? ??
                  0;

              // 3. Sensor Statistics
              final sensorStats =
                  stats['sensors'] as Map<String, dynamic>? ?? {};
              final sensorReadings =
                  sensorStats['latest_readings'] as Map<String, dynamic>? ?? {};

              // Update nilai sensor
              temperature = _getSensorValue(sensorReadings, 'dht_temp');
              humidity = _getSensorValue(sensorReadings, 'dht_humid');
              phLevel = _getSensorValue(sensorReadings, 'ph');
              ecLevel = _getSensorValue(sensorReadings, 'ec');
              lightIntensity = _getSensorValue(sensorReadings, 'ldr');
              waterLevel = _getSensorValue(sensorReadings, 'ultrasonic');

              // 4. System Status
              final system = stats['system'] as Map<String, dynamic>? ?? {};
              systemOnline = (system['status'] as String?) == 'online';

              // 5. Update allSensors
              _updateAllSensorsFromReadings(sensorReadings);
            });
            return;
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ JSON Parse Error: $e');
            print('❌ Full response: ${response.body}');
          }
        }
      }

      // Handle error responses
      if (response.statusCode == 401) {
        _handleTokenError('Session expired. Please login again.');
        return;
      } else if (response.statusCode == 403) {
        _handleTokenError('Access denied. Admin permission required.');
        return;
      }

      // Fallback
      if (kDebugMode) {
        print('⚠️ Using fallback data');
      }
      _useFallbackData();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading dashboard stats: $e');
      }
      _useFallbackData();
    }
  }

  double _getSensorValue(Map<String, dynamic> readings, String sensorName) {
    try {
      final sensorData = readings[sensorName] as Map<String, dynamic>?;
      if (sensorData == null) return 0.0;

      final value = sensorData['value'];
      if (value is int) return value.toDouble();
      if (value is double) return value;
      if (value is String) return double.tryParse(value) ?? 0.0;

      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  void _useFallbackData() {
    setState(() {
      activeUsers = 1;
      totalMessages = 0;
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
    int count = 0;
    if (temperature > 0) count++;
    if (humidity > 0) count++;
    if (phLevel > 0) count++;
    if (ecLevel > 0) count++;
    if (lightIntensity > 0) count++;
    if (waterLevel > 0) count++;

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
    if (hasError) return adminRed;
    return systemOnline ? leafGreen : adminRed;
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

    Widget _pollutantInfo(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: deepGreen,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          unit,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

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

  Widget _getWeatherIcon(int? code, {double size = 32}) {
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
              child: Icon(
                Icons.wb_sunny,
                size: size * 0.7,
                color: const Color(0xFFFDB813),
              ),
            ),
            Positioned(
              right: 0,
              bottom: size * 0.1,
              child: Icon(
                Icons.cloud,
                size: size * 0.5,
                color: const Color(0xFFA8D8EA),
              ),
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

    Future<void> _fetchAirQualityData() async {
    setState(() => airQualityLoading = true);

    try {
      final response = await http.get(
        Uri.parse('https://api.waqi.info/feed/bandung/?token=demo'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'ok' && data['data'] != null) {
          setState(() {
            airQualityData = data;

            final aqi = data['data']['aqi'] is int
                ? data['data']['aqi']
                : int.tryParse(data['data']['aqi'].toString()) ?? 0;

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
          // TAMBAHKAN DATA POLLUTANT DI SINI
          setState(() {
            airQualityData = {
              'data': {'aqi': 55},
              'aqi': 55,
              'pm25': 12.5,
              'pm10': 25.3,
              'o3': 45.8,
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

      // TAMBAHKAN DATA POLLUTANT DI SINI JUGA
      setState(() {
        airQualityData = {
          'data': {'aqi': 55},
          'aqi': 55,
          'pm25': 12.5,
          'pm10': 25.3,
          'o3': 45.8,
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
    await Future.delayed(const Duration(milliseconds: 500));
    await _loadAllData();
  }

  Future<void> _logout() async {
    // Show confirmation dialog
    final bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.logout_rounded,
                color: adminRed,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Logout',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: deepGreen,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to logout from admin account?',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: adminRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                elevation: 2,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (!confirm) return;


    // Tampilkan loading sebelum redirect
    setState(() {
      isLoading = true;
    });

    // Tunggu sebentar untuk effect
    await Future.delayed(const Duration(milliseconds: 800));

    // Navigate ke SplashScreen dengan transition yang smooth
    // ignore: use_build_context_synchronously
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const SplashScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
      (route) => false,
    );
  }

  // Navigation handling
  final List<Widget> _pages = [
    // Will be filled with _buildHomePage
    const SizedBox(),
    const UsersPage(),
    const SensorDetailPage(sensorName: 'dht_temp', displayName: 'Temperature'),
    const AnalyticsPage(),
    const MessagesPage(),
    const SettingsPage(),
    const LogsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Tampilkan splash screen jika masih loading dan belum ada error
    if (isLoading && !hasError) {
      return const SplashScreen();
    }

    if (hasError && !isLoading) {
      return _buildErrorScreen();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgGradientStart, bgGradientEnd],
            stops: const [0.0, 1.0],
          ),
        ),
        child: _selectedIndex == 0 ? _buildHomePage() : _pages[_selectedIndex],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(38),
          boxShadow: [
            BoxShadow(
              color: deepGreen.withValues(alpha: 0.12),
              blurRadius: 40,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(38),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  _navItem(Icons.home_rounded, 0),
                  _navItem(Icons.people_rounded, 1),
                  _navItem(Icons.sensors_rounded, 2),
                  _navItem(Icons.analytics_rounded, 3),
                  _navItem(Icons.message_rounded, 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, int index) {
    final selected = index == _selectedIndex;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onItemTapped(index),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 22 : 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: selected
                  ? LinearGradient(
                      colors: [
                        leafGreen.withValues(alpha: 0.95),
                        waterBlue.withValues(alpha: 0.95),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: selected ? null : Colors.white.withValues(alpha: 0.9),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: leafGreen.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: selected ? 22 : 20,
                  color: selected ? Colors.white : Colors.grey.shade700,
                ),
                const SizedBox(height: 4),
                Text(
                  _getNavLabel(index),
                  style: TextStyle(
                    fontSize: 10,
                    color: selected ? Colors.white : Colors.grey.shade600,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getNavLabel(int index) {
    switch (index) {
      case 0:
        return 'Home';
      case 1:
        return 'Users';
      case 2:
        return 'Sensors';
      case 3:
        return 'Analytics';
      case 4:
        return 'Messages';
      default:
        return '';
    }
  }

  Widget _buildHomePage() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        SliverToBoxAdapter(child: _buildContent()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [deepGreen, forestGreen],
          stops: const [0.0, 0.8],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
        boxShadow: [
          BoxShadow(
            color: deepGreen.withValues(alpha: 0.4),
            blurRadius: 40,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // TOP BAR dengan Refresh Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "HydroGrow Admin",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            "System Administration",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Refresh Button
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: GestureDetector(
                          onTap: _manualRefresh,
                          child: Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Notification Button
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Stack(
                          children: [
                            const Icon(
                              Icons.notifications_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                            if (totalMessages > 0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: sunlightOrange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // STATUS CARD
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: leafGreen.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.admin_panel_settings_rounded,
                                  color: leafGreen,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Admin Dashboard",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            systemOnline ? "All Systems Operational" : "System Maintenance",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            systemOnline
                                ? "Monitoring ${_getTotalSensors()} sensors & $activeUsers users"
                                : "System checks in progress",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  systemOnline ? leafGreen : adminRed,
                                  systemOnline ? waterBlue : adminRed.withOpacity(0.8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: (systemOnline ? leafGreen : adminRed)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 15,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  systemOnline ? "System Online" : "System Offline",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Icon(
                      systemOnline ? Icons.verified_rounded : Icons.warning_rounded,
                      color: Colors.white,
                      size: 80,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Weather Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFA8D8EA).withValues(alpha: 0.2),
                  const Color(0xFF7FC4DD).withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
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
                          color: leafGreen,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Loading weather...',
                        style: TextStyle(
                          fontSize: 14,
                          color: deepGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : weatherData != null
                    ? Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: _getWeatherIcon(
                              _getCurrentWeatherCode(),
                              size: 40,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 16,
                                      color: deepGreen.withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      selectedCity,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: deepGreen.withValues(alpha: 0.8),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _getWeatherDesc(_getCurrentWeatherCode()),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: deepGreen,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Current weather conditions',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
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
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: deepGreen,
                                  height: 1,
                                  letterSpacing: -1,
                                ),
                              ),
                              Text(
                                'Celsius',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
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
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Weather unavailable',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
          ),

          const SizedBox(height: 16),

          // Air Quality Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  aqiColor.withValues(alpha: 0.2),
                  aqiColor.withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: airQualityLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: leafGreen,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Loading air quality...',
                        style: TextStyle(
                          fontSize: 14,
                          color: deepGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : airQualityData != null
                    ? Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.air_rounded,
                                  size: 40,
                                  color: aqiColor,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          size: 16,
                                          color:
                                              deepGreen.withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Air Quality',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                deepGreen.withValues(alpha: 0.8),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      aqiStatus,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: deepGreen,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Real-time monitoring',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${airQualityData!['data']['aqi'] ?? airQualityData!['aqi']}',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                      color: aqiColor,
                                      height: 1,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                  Text(
                                    'AQI',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // ======= TAMBAHKAN INI =======
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _pollutantInfo(
                                  'PM2.5',
                                  '${airQualityData!['pm25'] ?? '--'}',
                                  'μg/m³',
                                ),
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: Colors.grey.shade300,
                                ),
                                _pollutantInfo(
                                  'PM10',
                                  '${airQualityData!['pm10'] ?? '--'}',
                                  'μg/m³',
                                ),
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: Colors.grey.shade300,
                                ),
                                _pollutantInfo(
                                  'O₃',
                                  '${airQualityData!['o3'] ?? '--'}',
                                  'ppb',
                                ),
                              ],
                            ),
                          ),
                          // ======= SAMPAI SINI =======
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.air_rounded,
                            color: Colors.grey.shade400,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Air quality unavailable',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
          ),

          const SizedBox(height: 32),

          // System Overview Title
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [leafGreen, waterBlue],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "System Overview",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: deepGreen,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Stats Grid - Warna lebih subtle
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            children: [
              _statCard(
                Icons.people_rounded,
                "Active Users",
                activeUsers.toString(),
                iconColor: adminBlue,
                iconBg: adminBlue.withValues(alpha: 0.1),
              ),
              _statCard(
                Icons.sensors_rounded,
                "Total Sensors",
                _getTotalSensors().toString(),
                iconColor: leafGreen,
                iconBg: leafGreen.withValues(alpha: 0.1),
              ),
              _statCard(
                Icons.message_rounded,
                "Messages",
                totalMessages.toString(),
                iconColor: adminPurple,
                iconBg: adminPurple.withValues(alpha: 0.1),
              ),
              _statCard(
                Icons.wifi_tethering_rounded,
                "System Status",
                _getSystemStatus(),
                iconColor: _getSystemStatusColor(),
                iconBg: _getSystemStatusColor().withValues(alpha: 0.1),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Live Sensor Data Title
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [leafGreen, waterBlue],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Live Sensor Data",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: deepGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Text(
                      "Real-time monitoring",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            children: [
              _quickStat(
                Icons.thermostat_rounded,
                "Temperature",
                "${temperature.toStringAsFixed(1)}°C",
                gradient: LinearGradient(
                  colors: [Colors.red.shade100, Colors.red.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                iconColor: Colors.red.shade600,
                iconBg: Colors.red.shade50,
              ),
              _quickStat(
                Icons.water_drop_rounded,
                "Humidity",
                "${humidity.toStringAsFixed(1)}%",
                gradient: LinearGradient(
                  colors: [Colors.blue.shade100, Colors.blue.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                iconColor: Colors.blue.shade600,
                iconBg: Colors.blue.shade50,
              ),
              _quickStat(
                Icons.wb_sunny_rounded,
                "Light",
                "${lightIntensity.toStringAsFixed(0)} Lux",
                gradient: LinearGradient(
                  colors: [Colors.orange.shade100, Colors.orange.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                iconColor: Colors.orange.shade600,
                iconBg: Colors.orange.shade50,
              ),
              _quickStat(
                Icons.waves_rounded,
                "Water Level",
                "${waterLevel.toStringAsFixed(0)}%",
                gradient: LinearGradient(
                  colors: [
                    waterBlue.withValues(alpha: 0.2),
                    waterBlue.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                iconColor: waterBlue,
                iconBg: mintGreen.withValues(alpha: 0.3),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Quick Actions Title
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [leafGreen, waterBlue],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Quick Actions",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: deepGreen,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Text(
                      "Administration tools",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Quick Actions Cards
          _actionCard(
            icon: Icons.people_outline_rounded,
            title: "User Management",
            subtitle: "Manage system users & permissions",
            color: adminBlue,
            gradient: LinearGradient(
              colors: [
                adminBlue.withValues(alpha: 0.1),
                adminBlue.withValues(alpha: 0.05),
              ],
            ),
            onTap: () => _onItemTapped(1),
          ),

          const SizedBox(height: 16),

          _actionCard(
            icon: Icons.sensors_rounded,
            title: "Sensor Dashboard",
            subtitle: "Detailed sensor analytics & control",
            color: leafGreen,
            gradient: LinearGradient(
              colors: [
                leafGreen.withValues(alpha: 0.1),
                leafGreen.withValues(alpha: 0.05),
              ],
            ),
            badgeCount: _getTotalSensors(),
            onTap: () => _onItemTapped(2),
          ),

          const SizedBox(height: 16),

          _actionCard(
            icon: Icons.analytics_rounded,
            title: "Analytics Center",
            subtitle: "Performance reports & insights",
            color: adminPurple,
            gradient: LinearGradient(
              colors: [
                adminPurple.withValues(alpha: 0.1),
                adminPurple.withValues(alpha: 0.05),
              ],
            ),
            onTap: () => _onItemTapped(3),
          ),

          const SizedBox(height: 16),

          _actionCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: "Message Center",
            subtitle: "View & respond to user messages",
            color: waterBlue,
            gradient: LinearGradient(
              colors: [
                waterBlue.withValues(alpha: 0.1),
                waterBlue.withValues(alpha: 0.05),
              ],
            ),
            badgeCount: totalMessages,
            onTap: () => _onItemTapped(4),
          ),

          const SizedBox(height: 16),

          _actionCard(
            icon: Icons.settings_rounded,
            title: "System Settings",
            subtitle: "Configure system parameters",
            color: sunlightOrange,
            gradient: LinearGradient(
              colors: [
                sunlightOrange.withValues(alpha: 0.1),
                sunlightOrange.withValues(alpha: 0.05),
              ],
            ),
            onTap: () => _onItemTapped(5),
          ),

          const SizedBox(height: 16),

          _actionCard(
            icon: Icons.history_toggle_off_rounded,
            title: "Activity Log",
            subtitle: "System events & audit trail",
            color: deepGreen,
            gradient: LinearGradient(
              colors: [
                deepGreen.withValues(alpha: 0.1),
                deepGreen.withValues(alpha: 0.05),
              ],
            ),
            onTap: () => _onItemTapped(6),
          ),

          const SizedBox(height: 40),

          // System Info Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  leafGreen.withValues(alpha: 0.1),
                  leafGreen.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: leafGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: leafGreen.withValues(alpha: 0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: leafGreen,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "System Information",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: deepGreen,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isLoading
                            ? "Fetching live data from sensors..."
                            : "${allSensors.length} sensor readings • ${_getTotalSensors()} active sensors • $totalMessages new messages\nLast updated: ${_getLastUpdateTime()}",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Logout Button - Styling yang sama dengan card lainnya
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _logout,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      adminRed.withValues(alpha: 0.1),
                      adminRed.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: adminRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: adminRed.withValues(alpha: 0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.logout_rounded,
                        color: adminRed,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Logout",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: deepGreen,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Sign out from admin account",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 24,
                      color: adminRed,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _statCard(
    IconData icon,
    String title,
    String value, {
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: deepGreen.withValues(alpha: 0.7),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: deepGreen,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickStat(
    IconData icon,
    String title,
    String value, {
    required Gradient gradient,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: deepGreen.withValues(alpha: 0.7),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: deepGreen,
                letterSpacing: 0.5,
              ),
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
    required Gradient gradient,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    if (badgeCount != null && badgeCount > 0)
                      Positioned(
                        top: -8,
                        right: -8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: adminRed,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: adminRed.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          child: Center(
                            child: Text(
                              badgeCount > 9 ? '9+' : badgeCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                          fontWeight: FontWeight.w700,
                          color: deepGreen,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 24,
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: bgGradientStart,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgGradientStart, bgGradientEnd],
          ),
        ),
        child: Center(
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
                      colors: [adminRed, Colors.orangeAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: adminRed.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
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
                    color: deepGreen,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: leafGreen.withValues(alpha: 0.2)),
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
                        backgroundColor: leafGreen,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 5,
                        shadowColor: leafGreen.withValues(alpha: 0.4),
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
                          side: BorderSide(color: leafGreen, width: 2),
                        ),
                        elevation: 3,
                      ),
                      child: Text(
                        'Try Again',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: leafGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}