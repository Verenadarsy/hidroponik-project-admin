import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../services/shared.dart';
import '../models/sensor_model.dart';

class SensorDetailPage extends StatefulWidget {
  final String sensorName;
  final String displayName;

  const SensorDetailPage({
    super.key,
    required this.sensorName,
    required this.displayName,
  });

  @override
  State<SensorDetailPage> createState() => _SensorDetailPageState();
}

class _SensorDetailPageState extends State<SensorDetailPage> {
  final Color darkGreen = const Color(0xFF456028);
  final Color mediumGreen = const Color(0xFF94A65E);
  final Color lightGreen = const Color(0xFFDDDDA1);
  final Color creamBackground = const Color(0xFFF8F9FA);

  static const String baseUrl =
      'https://uncollapsable-overfly-blaine.ngrok-free.dev/api';
  String? _token;

  List<SensorData> sensorHistory = [];
  bool isLoading = true;
  Timer? _refreshTimer;
  String selectedTimeRange = '24h'; // 24h, 7d, 30d
  Map<String, dynamic> sensorStats = {};
  double currentValue = 0.0;
  bool isOnline = true;

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
    _token = await SharedService.getToken();
    await _loadSensorData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadSensorData();
    });
  }

  Future<void> _loadSensorData() async {
    if (_token == null) return;

    setState(() => isLoading = true);

    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/admin/sensor-data?sensor=${widget.sensorName}&hours=${_getHoursFromRange()}&limit=100',
        ),
        headers: {
          'Authorization': 'Bearer $_token',
          'ngrok-skip-browser-warning': 'true',
          'Accept': 'application/json',
        },
      );

      print('Sensor data response status: ${response.statusCode}');
      print('Sensor data response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == true) {
          final List<SensorData> history = (data['data'] as List)
              .map((e) => SensorData.fromJson(e))
              .toList();

          setState(() {
            sensorHistory = history;
            if (history.isNotEmpty) {
              currentValue = history.first.value;
              _calculateStats();
            }
            isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      print('Error loading sensor data: $e');
    }

    // Fallback dummy data
    _useDummyData();
  }

  void _useDummyData() {
    final now = DateTime.now();
    final List<SensorData> dummyData = [];

    // Generate dummy data based on sensor type
    double baseValue = _getBaseValueForSensor();

    for (int i = 0; i < 50; i++) {
      final time = now.subtract(Duration(minutes: i * 10));
      final variation = (i % 10) - 5.0; // Some variation
      final value = baseValue + variation;

      dummyData.add(
        SensorData(
          sensorName: widget.sensorName,
          value: value > 0 ? value : 0.1,
          timestamp: time,
        ),
      );
    }

    setState(() {
      sensorHistory = dummyData;
      currentValue = dummyData.isNotEmpty ? dummyData.first.value : 0.0;
      _calculateStats();
      isLoading = false;
    });
  }

  double _getBaseValueForSensor() {
    switch (widget.sensorName) {
      case 'dht_temp':
        return 25.0;
      case 'dht_humid':
        return 65.0;
      case 'ph':
        return 6.8;
      case 'ec':
        return 1.5;
      case 'ldr':
        return 500.0;
      case 'ultrasonic':
        return 75.0;
      default:
        return 50.0;
    }
  }

  int _getHoursFromRange() {
    switch (selectedTimeRange) {
      case '24h':
        return 24;
      case '7d':
        return 168; // 24 * 7
      case '30d':
        return 720; // 24 * 30
      default:
        return 24;
    }
  }

  void _calculateStats() {
    if (sensorHistory.isEmpty) {
      sensorStats = {
        'min': 0.0,
        'max': 0.0,
        'avg': 0.0,
        'latest': 0.0,
        'trend': 'stable',
      };
      return;
    }

    final values = sensorHistory.map((e) => e.value).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final latest = sensorHistory.first.value;

    // Determine trend
    String trend = 'stable';
    if (sensorHistory.length >= 3) {
      final recentAvg =
          sensorHistory.take(3).map((e) => e.value).reduce((a, b) => a + b) / 3;
      final olderAvg =
          sensorHistory
              .skip(3)
              .take(3)
              .map((e) => e.value)
              .reduce((a, b) => a + b) /
          3;

      if (recentAvg > olderAvg + 0.5) trend = 'rising';
      if (recentAvg < olderAvg - 0.5) trend = 'falling';
    }

    // Check if sensor is online (data in last 5 minutes)
    final lastUpdate = sensorHistory.first.timestamp;
    final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));
    isOnline = lastUpdate.isAfter(fiveMinutesAgo);

    setState(() {
      sensorStats = {
        'min': min,
        'max': max,
        'avg': avg,
        'latest': latest,
        'trend': trend,
      };
    });
  }

  Color _getValueColor(double value) {
    switch (widget.sensorName) {
      case 'dht_temp':
        if (value > 30) return Colors.red;
        if (value < 20) return Colors.blue;
        return Colors.green;
      case 'dht_humid':
        if (value > 80) return Colors.orange;
        if (value < 40) return Colors.yellow;
        return Colors.green;
      case 'ph':
        if (value < 6.0 || value > 7.5) return Colors.red;
        return Colors.green;
      case 'ec':
        if (value < 1.0 || value > 2.0) return Colors.orange;
        return Colors.green;
      case 'ultrasonic':
        if (value < 20) return Colors.red;
        if (value < 50) return Colors.orange;
        return Colors.green;
      default:
        return darkGreen;
    }
  }

  String _getUnit() {
    switch (widget.sensorName) {
      case 'dht_temp':
        return '°C';
      case 'dht_humid':
        return '%';
      case 'ph':
        return 'pH';
      case 'ec':
        return 'mS/cm';
      case 'ldr':
        return 'Lux';
      case 'ultrasonic':
        return '%';
      default:
        return 'unit';
    }
  }

  String _getOptimalRange() {
    switch (widget.sensorName) {
      case 'dht_temp':
        return '20-30°C';
      case 'dht_humid':
        return '40-80%';
      case 'ph':
        return '6.0-7.5';
      case 'ec':
        return '1.0-2.0 mS/cm';
      case 'ldr':
        return '>300 Lux';
      case 'ultrasonic':
        return '>50%';
      default:
        return 'N/A';
    }
  }

  bool _isValueOptimal(double value) {
    switch (widget.sensorName) {
      case 'dht_temp':
        return value >= 20 && value <= 30;
      case 'dht_humid':
        return value >= 40 && value <= 80;
      case 'ph':
        return value >= 6.0 && value <= 7.5;
      case 'ec':
        return value >= 1.0 && value <= 2.0;
      case 'ldr':
        return value > 300;
      case 'ultrasonic':
        return value > 50;
      default:
        return true;
    }
  }

  Widget _buildCurrentValueCard() {
    final isOptimal = _isValueOptimal(currentValue);
    final valueColor = _getValueColor(currentValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            valueColor.withValues(alpha: 0.1),
            valueColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: valueColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: darkGreen,
                      ),
                    ),
                    Text(
                      'Current Reading',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          color: isOnline ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${currentValue.toStringAsFixed(widget.sensorName == 'ph' || widget.sensorName == 'ec' ? 2 : 1)}${_getUnit()}',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          color: valueColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isOptimal
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isOptimal ? 'Optimal' : 'Needs Attention',
                          style: TextStyle(
                            fontSize: 12,
                            color: isOptimal ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _getSensorIcon(),
                  size: 60,
                  color: valueColor.withValues(alpha: 0.3),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Optimal range: ${_getOptimalRange()}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      children: [
        _statCard(
          title: 'Minimum',
          value: sensorStats['min']?.toStringAsFixed(1) ?? '0.0',
          unit: _getUnit(),
          icon: Icons.arrow_downward,
          color: Colors.blue,
        ),
        _statCard(
          title: 'Maximum',
          value: sensorStats['max']?.toStringAsFixed(1) ?? '0.0',
          unit: _getUnit(),
          icon: Icons.arrow_upward,
          color: Colors.red,
        ),
        _statCard(
          title: 'Average',
          value: sensorStats['avg']?.toStringAsFixed(1) ?? '0.0',
          unit: _getUnit(),
          icon: Icons.timeline,
          color: Colors.purple,
        ),
        _statCard(
          title: 'Trend',
          value: sensorStats['trend'] ?? 'stable',
          unit: '',
          icon: _getTrendIcon(),
          color: _getTrendColor(),
        ),
      ],
    );
  }

  Widget _buildChart() {
    if (sensorHistory.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Text('No data available')),
      );
    }

    final spots = sensorHistory
        .asMap()
        .map((i, data) => MapEntry(i, FlSpot(i.toDouble(), data.value)))
        .values
        .toList()
        .reversed
        .toList();

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
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
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withValues(alpha: 0.1),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  if (value == 0 || value == spots.length - 1) {
                    final index = value.toInt();
                    if (index < sensorHistory.length) {
                      final time = sensorHistory[index].timestamp;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    }
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          minX: 0,
          maxX: spots.length > 1 ? spots.length - 1 : 1,
          minY: (sensorStats['min'] ?? 0) * 0.9,
          maxY: (sensorStats['max'] ?? 1) * 1.1,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _getValueColor(currentValue),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: _getValueColor(currentValue).withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(8),
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
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _timeRangeButton('24h'),
          _timeRangeButton('7d'),
          _timeRangeButton('30d'),
        ],
      ),
    );
  }

  Widget _timeRangeButton(String range) {
    final isSelected = selectedTimeRange == range;

    return GestureDetector(
      onTap: () {
        setState(() => selectedTimeRange = range);
        _loadSensorData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? darkGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? darkGreen : Colors.grey.shade300,
          ),
        ),
        child: Text(
          range,
          style: TextStyle(
            color: isSelected ? Colors.white : darkGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
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
                if (unit.isNotEmpty)
                  Text(
                    unit,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getSensorIcon() {
    switch (widget.sensorName) {
      case 'dht_temp':
        return Icons.thermostat;
      case 'dht_humid':
        return Icons.water_drop;
      case 'ph':
        return Icons.science;
      case 'ec':
        return Icons.bolt;
      case 'ldr':
        return Icons.light_mode;
      case 'ultrasonic':
        return Icons.waves;
      default:
        return Icons.sensors;
    }
  }

  IconData _getTrendIcon() {
    final trend = sensorStats['trend'] ?? 'stable';
    switch (trend) {
      case 'rising':
        return Icons.trending_up;
      case 'falling':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  Color _getTrendColor() {
    final trend = sensorStats['trend'] ?? 'stable';
    switch (trend) {
      case 'rising':
        return Colors.green;
      case 'falling':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBackground,
      appBar: AppBar(
        title: Text(widget.displayName),
        backgroundColor: darkGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSensorData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 100,
              ),
              child: Column(
                children: [
                  _buildCurrentValueCard(),
                  _buildTimeRangeSelector(),
                  _buildStatsGrid(),
                  const SizedBox(height: 20),
                  Text(
                    'Historical Data',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: darkGreen,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildChart(),
                  const SizedBox(height: 20),

                  // Data Table
                  // Data Table - FULL WIDTH
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Recent Readings',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: darkGreen,
                            ),
                          ),
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: MediaQuery.of(context).size.width - 32,
                            ),
                            child: DataTable(
                              columnSpacing: 0,
                              horizontalMargin: 16,
                              dataRowMinHeight: 50,
                              dataRowMaxHeight: 50,
                              headingRowHeight: 50,
                              headingTextStyle: TextStyle(
                                color: darkGreen,
                                fontWeight: FontWeight.w600,
                              ),
                              columns: [
                                DataColumn(
                                  label: Container(
                                    width:
                                        MediaQuery.of(context).size.width *
                                        0.25,
                                    child: Text(
                                      'Time',
                                      style: TextStyle(
                                        color: darkGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  numeric: false,
                                ),
                                DataColumn(
                                  label: Container(
                                    width:
                                        MediaQuery.of(context).size.width *
                                        0.35,
                                    child: Text(
                                      'Value',
                                      style: TextStyle(
                                        color: darkGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Container(
                                    width:
                                        MediaQuery.of(context).size.width *
                                        0.30,
                                    child: Text(
                                      'Status',
                                      style: TextStyle(
                                        color: darkGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  numeric: false,
                                ),
                              ],
                              rows: sensorHistory.take(10).map((data) {
                                final isOptimal = _isValueOptimal(data.value);
                                final valueColor = _getValueColor(data.value);

                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Container(
                                        width:
                                            MediaQuery.of(context).size.width *
                                            0.25,
                                        child: Text(
                                          '${data.timestamp.hour}:${data.timestamp.minute.toString().padLeft(2, '0')}',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        width:
                                            MediaQuery.of(context).size.width *
                                            0.35,
                                        child: Text(
                                          '${data.value.toStringAsFixed(widget.sensorName == 'ph' || widget.sensorName == 'ec' ? 2 : 1)}${_getUnit()}',
                                          style: TextStyle(
                                            color: valueColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        width:
                                            MediaQuery.of(context).size.width *
                                            0.30,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isOptimal
                                              ? Colors.green.withOpacity(0.1)
                                              : Colors.orange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          isOptimal ? 'Optimal' : 'Check',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isOptimal
                                                ? Colors.green
                                                : Colors.orange,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
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
