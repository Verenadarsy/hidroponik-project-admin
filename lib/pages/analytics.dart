import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/shared.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final Color darkGreen = const Color(0xFF456028);
  final Color mediumGreen = const Color(0xFF94A65E);
  final Color lightGreen = const Color(0xFFDDDDA1);
  final Color creamBackground = const Color(0xFFF8F9FA);
  final Color accentBlue = const Color(0xFF5A86AD);
  final Color accentOrange = const Color(0xFFD18B47);
  final Color accentPurple = const Color(0xFF7B68B5);

  static const String baseUrl =
      'https://7e60c5098efd.ngrok-free.app/api';
  String? _token;

  // Analytics data
  Map<String, dynamic> analyticsData = {};
  bool isLoading = true;
  String selectedPeriod = 'week'; // day, week, month, year
  String selectedMetric = 'overview'; // overview, sensors, users, system

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    _token = await SharedService.getToken();
    await _loadAnalyticsData();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => isLoading = true);

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/analytics?period=$selectedPeriod'),
        headers: {
          'ngrok-skip-browser-warning': 'true',
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == true) {
          setState(() {
            analyticsData = data['data'];
            isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      print('Error loading analytics: $e');
    }

    // Fallback dummy data
    _useDummyData();
  }

  void _useDummyData() {
    setState(() {
      analyticsData = {
        'overview': {
          'total_readings': 12560,
          'avg_temperature': 26.5,
          'avg_humidity': 68.2,
          'system_uptime': 99.8,
          'alerts_count': 12,
          'growth_rate': '+2.3%',
        },
        'sensors': {
          'temperature': {
            'avg': 26.5,
            'min': 22.1,
            'max': 31.2,
            'trend': 'stable',
            'data': [24.5, 25.2, 26.8, 27.1, 26.3, 25.9, 26.5],
          },
          'humidity': {
            'avg': 68.2,
            'min': 58.4,
            'max': 78.9,
            'trend': 'rising',
            'data': [65.2, 66.8, 67.1, 68.4, 69.2, 68.8, 68.2],
          },
          'ph': {
            'avg': 6.8,
            'min': 6.2,
            'max': 7.1,
            'trend': 'stable',
            'data': [6.7, 6.8, 6.9, 6.8, 6.7, 6.8, 6.8],
          },
          'light': {
            'avg': 520.5,
            'min': 210.2,
            'max': 850.3,
            'trend': 'rising',
            'data': [480.2, 520.1, 510.8, 525.3, 530.6, 515.2, 520.5],
          },
        },
        'users': {
          'total': 3,
          'active': 2,
          'new_this_week': 1,
          'avg_session': '12m 30s',
          'activity_trend': [5, 8, 12, 10, 15, 18, 20],
        },
        'system': {
          'uptime': '99.8%',
          'avg_response': '145ms',
          'error_rate': '0.2%',
          'data_volume': '2.5GB',
          'performance_trend': [95, 96, 98, 99, 99, 99.5, 99.8],
        },
        'alerts': [
          {
            'type': 'warning',
            'message': 'High temperature detected',
            'time': '2 hours ago',
            'sensor': 'dht_temp',
          },
          {
            'type': 'info',
            'message': 'System backup completed',
            'time': '5 hours ago',
            'source': 'system',
          },
          {
            'type': 'error',
            'message': 'Database connection timeout',
            'time': '1 day ago',
            'source': 'database',
          },
        ],
      };
      isLoading = false;
    });
  }

  Widget _buildOverview() {
    final overview = analyticsData['overview'] ?? {};

    return Column(
      children: [
        // Stats Grid
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.2,
          ),
          children: [
            _metricCard(
              title: 'Total Readings',
              value: '${overview['total_readings'] ?? 0}',
              subtitle: 'Sensor data points',
              icon: Icons.data_usage,
              color: accentBlue,
              trend: '+12%',
            ),
            _metricCard(
              title: 'Avg Temperature',
              value:
                  '${overview['avg_temperature']?.toStringAsFixed(1) ?? '0.0'}°C',
              subtitle: 'Optimal range',
              icon: Icons.thermostat,
              color: Colors.red,
              trend: 'stable',
            ),
            _metricCard(
              title: 'Avg Humidity',
              value:
                  '${overview['avg_humidity']?.toStringAsFixed(1) ?? '0.0'}%',
              subtitle: 'Within range',
              icon: Icons.water_drop,
              color: Colors.blue,
              trend: '+2%',
            ),
            _metricCard(
              title: 'System Uptime',
              value:
                  '${overview['system_uptime']?.toStringAsFixed(1) ?? '0.0'}%',
              subtitle: 'Last 7 days',
              icon: Icons.timeline,
              color: Colors.green,
              trend: '99.9%',
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Growth Chart
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
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
                  Text(
                    'Growth Analysis',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: darkGreen,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      overview['growth_rate'] ?? '+0.0%',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 150,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: const [
                          FlSpot(0, 3),
                          FlSpot(1, 5),
                          FlSpot(2, 8),
                          FlSpot(3, 12),
                          FlSpot(4, 15),
                          FlSpot(5, 18),
                          FlSpot(6, 22),
                        ],
                        isCurved: true,
                        color: darkGreen,
                        barWidth: 3,
                        belowBarData: BarAreaData(
                          show: true,
                          color: darkGreen.withValues(alpha: 0.1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSensorAnalytics() {
    final sensors = analyticsData['sensors'] ?? {};

    return Column(
      children: [
        // Sensor Performance Grid
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
            _sensorMetric(
              name: 'Temperature',
              data: sensors['temperature'] ?? {},
              unit: '°C',
              color: Colors.red,
            ),
            _sensorMetric(
              name: 'Humidity',
              data: sensors['humidity'] ?? {},
              unit: '%',
              color: Colors.blue,
            ),
            _sensorMetric(
              name: 'pH Level',
              data: sensors['ph'] ?? {},
              unit: 'pH',
              color: mediumGreen,
            ),
            _sensorMetric(
              name: 'Light',
              data: sensors['light'] ?? {},
              unit: 'Lux',
              color: Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Sensor Comparison Chart
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sensor Performance Comparison',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: darkGreen,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: 100,
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [
                          BarChartRodData(
                            toY: 85,
                            color: Colors.red,
                            width: 12,
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 1,
                        barRods: [
                          BarChartRodData(
                            toY: 92,
                            color: Colors.blue,
                            width: 12,
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 2,
                        barRods: [
                          BarChartRodData(
                            toY: 78,
                            color: mediumGreen,
                            width: 12,
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 3,
                        barRods: [
                          BarChartRodData(
                            toY: 95,
                            color: Colors.orange,
                            width: 12,
                          ),
                        ],
                      ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            const labels = ['Temp', 'Humid', 'pH', 'Light'];
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                labels[value.toInt()],
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              '${value.toInt()}%',
                              style: const TextStyle(fontSize: 10),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserAnalytics() {
    final users = analyticsData['users'] ?? {};
    final activityTrend = List<int>.from(users['activity_trend'] ?? [1, 2, 3]);

    return Column(
      children: [
        // User Stats
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _userStat(
                    'Total Users',
                    users['total']?.toString() ?? '0',
                    Icons.people,
                  ),
                  _userStat(
                    'Active',
                    users['active']?.toString() ?? '0',
                    Icons.check_circle,
                  ),
                  _userStat(
                    'New',
                    users['new_this_week']?.toString() ?? '0',
                    Icons.person_add,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: Colors.grey.shade200),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Avg Session Duration',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  Text(
                    users['avg_session'] ?? '0m',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: darkGreen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // User Activity Chart
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'User Activity Trend',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: darkGreen,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 150,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: activityTrend.asMap().entries.map((entry) {
                          return FlSpot(
                            entry.key.toDouble(),
                            entry.value.toDouble(),
                          );
                        }).toList(),
                        isCurved: true,
                        color: accentPurple,
                        barWidth: 3,
                        belowBarData: BarAreaData(
                          show: true,
                          color: accentPurple.withValues(alpha: 0.1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSystemAnalytics() {
    final system = analyticsData['system'] ?? {};

    return Column(
      children: [
        // System Performance
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                children: [
                  _systemMetric(
                    'Uptime',
                    system['uptime'] ?? '0%',
                    Icons.timeline,
                    Colors.green,
                  ),
                  _systemMetric(
                    'Avg Response',
                    system['avg_response'] ?? '0ms',
                    Icons.speed,
                    Colors.blue,
                  ),
                  _systemMetric(
                    'Error Rate',
                    system['error_rate'] ?? '0%',
                    Icons.error,
                    Colors.red,
                  ),
                  _systemMetric(
                    'Data Volume',
                    system['data_volume'] ?? '0GB',
                    Icons.storage,
                    Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: Colors.grey.shade200),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Performance Score',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: darkGreen,
                    ),
                  ),
                  Text(
                    'A+',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Alerts List
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
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
                  Text(
                    'Recent Alerts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: darkGreen,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${(analyticsData['alerts'] ?? []).length} alerts',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._buildAlertsList(),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAlertsList() {
    final alerts = List<Map<String, dynamic>>.from(
      analyticsData['alerts'] ?? [],
    );

    if (alerts.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'No alerts in selected period',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ),
      ];
    }

    return alerts.take(5).map((alert) {
      final type = alert['type'] ?? 'info';
      Color color;
      IconData icon;

      switch (type) {
        case 'error':
          color = Colors.red;
          icon = Icons.error;
          break;
        case 'warning':
          color = Colors.orange;
          icon = Icons.warning;
          break;
        default:
          color = Colors.blue;
          icon = Icons.info;
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert['message'] ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: darkGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (alert['sensor'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            alert['sensor'],
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (alert['source'] != null)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            alert['source'],
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        alert['time'] ?? '',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String trend,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: trend.contains('+')
                        ? Colors.green.withValues(alpha: 0.1)
                        : trend.contains('-')
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    trend,
                    style: TextStyle(
                      fontSize: 10,
                      color: trend.contains('+')
                          ? Colors.green
                          : trend.contains('-')
                          ? Colors.red
                          : Colors.blue,
                      fontWeight: FontWeight.w600,
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
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: darkGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sensorMetric({
    required String name,
    required Map<String, dynamic> data,
    required String unit,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: darkGreen,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${data['avg']?.toStringAsFixed(1) ?? '0.0'}$unit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Min:',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${data['min']?.toStringAsFixed(1) ?? '0.0'}$unit',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            'Max:',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${data['max']?.toStringAsFixed(1) ?? '0.0'}$unit',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getTrendColor(
                            data['trend'] ?? 'stable',
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getTrendIcon(data['trend'] ?? 'stable'),
                              size: 10,
                              color: _getTrendColor(data['trend'] ?? 'stable'),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              data['trend'] ?? 'stable',
                              style: TextStyle(
                                fontSize: 10,
                                color: _getTrendColor(
                                  data['trend'] ?? 'stable',
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
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
    );
  }

  Widget _userStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: darkGreen.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: darkGreen, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: darkGreen,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _systemMetric(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: darkGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTrendIcon(String trend) {
    switch (trend) {
      case 'rising':
        return Icons.trending_up;
      case 'falling':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  Color _getTrendColor(String trend) {
    switch (trend) {
      case 'rising':
        return Colors.green;
      case 'falling':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  Widget _periodSelector() {
    const periods = [
      {'label': 'Today', 'value': 'day'},
      {'label': 'Week', 'value': 'week'},
      {'label': 'Month', 'value': 'month'},
      {'label': 'Year', 'value': 'year'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: periods.map((period) {
          final isSelected = selectedPeriod == period['value'];

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(period['label']!),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => selectedPeriod = period['value']!);
                  _loadAnalyticsData();
                }
              },
              selectedColor: darkGreen,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : darkGreen,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _metricSelector() {
    const metrics = [
      {'label': 'Overview', 'value': 'overview', 'icon': Icons.dashboard},
      {'label': 'Sensors', 'value': 'sensors', 'icon': Icons.sensors},
      {'label': 'Users', 'value': 'users', 'icon': Icons.people},
      {'label': 'System', 'value': 'system', 'icon': Icons.computer},
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 2.5,
        ),
        children: metrics.map((metric) {
          final isSelected = selectedMetric == metric['value'];

          return GestureDetector(
            onTap: () {
              setState(() => selectedMetric = metric['value']! as String);
            },
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isSelected ? darkGreen : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? darkGreen : Colors.grey.shade300,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      metric['icon'] as IconData,
                      size: 16,
                      color: isSelected ? Colors.white : darkGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      metric['label']! as String,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : darkGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBackground,
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        backgroundColor: darkGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Export functionality coming soon'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            tooltip: 'Export',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalyticsData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.only(
                // 🔹 PERUBAHAN DI SINI
                left: 16,
                right: 16,
                top: 16,
                bottom: 100, // 🔹 TAMBAHKAN PADDING BOTTOM
              ),
              child: Column(
                children: [
                  // Period Selector
                  _periodSelector(),
                  const SizedBox(height: 16),

                  // Metric Selector
                  _metricSelector(),

                  // Selected Content
                  if (selectedMetric == 'overview') _buildOverview(),
                  if (selectedMetric == 'sensors') _buildSensorAnalytics(),
                  if (selectedMetric == 'users') _buildUserAnalytics(),
                  if (selectedMetric == 'system') _buildSystemAnalytics(),

                  const SizedBox(height: 20),

                  // Summary Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          darkGreen.withValues(alpha: 0.1),
                          mediumGreen.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: mediumGreen.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Analytics Summary',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: darkGreen,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Last updated: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: darkGreen,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.insights,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Live',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
