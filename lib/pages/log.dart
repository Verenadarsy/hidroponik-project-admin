import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/shared.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final Color darkGreen = const Color(0xFF456028);
  final Color mediumGreen = const Color(0xFF94A65E);
  final Color creamBackground = const Color(0xFFF8F9FA);

  static const String baseUrl =
      'https://7e60c5098efd.ngrok-free.app/api';
  String? _token;

  List<dynamic> logs = [];
  bool isLoading = true;
  String selectedFilter = 'all'; // all, info, warning, error
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    _token = await SharedService.getToken();
    await _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => isLoading = true);

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/logs'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == true) {
          setState(() {
            logs = data['data'];
            isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      print('Error loading logs: $e');
    }

    // Fallback dummy data
    _useDummyData();
  }

  void _useDummyData() {
    setState(() {
      logs = [
        {
          'id': 1,
          'level': 'INFO',
          'message': 'Admin dashboard accessed',
          'timestamp': DateTime.now()
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
          'user': 'admin',
          'source': 'dashboard',
        },
        {
          'id': 2,
          'level': 'INFO',
          'message': 'Sensor data updated successfully',
          'timestamp': DateTime.now()
              .subtract(const Duration(minutes: 10))
              .toIso8601String(),
          'source': 'sensor',
          'details': 'Temperature: 25.5°C, Humidity: 65%',
        },
        {
          'id': 3,
          'level': 'WARNING',
          'message': 'High temperature detected',
          'timestamp': DateTime.now()
              .subtract(const Duration(minutes: 15))
              .toIso8601String(),
          'source': 'dht_temp',
          'details': 'Temperature reached 32.5°C',
        },
        {
          'id': 4,
          'level': 'INFO',
          'message': 'System backup completed',
          'timestamp': DateTime.now()
              .subtract(const Duration(minutes: 30))
              .toIso8601String(),
          'source': 'system',
          'details': 'Backup size: 15.2 MB',
        },
        {
          'id': 5,
          'level': 'ERROR',
          'message': 'Database connection timeout',
          'timestamp': DateTime.now()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          'source': 'database',
          'details': 'Retrying connection...',
        },
        {
          'id': 6,
          'level': 'INFO',
          'message': 'User login successful',
          'timestamp': DateTime.now()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
          'user': 'admin',
          'source': 'auth',
        },
        {
          'id': 7,
          'level': 'WARNING',
          'message': 'Low water level detected',
          'timestamp': DateTime.now()
              .subtract(const Duration(hours: 3))
              .toIso8601String(),
          'source': 'ultrasonic',
          'details': 'Water level: 15%',
        },
      ];
      isLoading = false;
    });
  }

  List<dynamic> get filteredLogs {
    List<dynamic> filtered = List.from(logs);

    if (selectedFilter != 'all') {
      filtered = filtered
          .where(
            (log) => log['level'].toLowerCase() == selectedFilter.toLowerCase(),
          )
          .toList();
    }

    if (selectedDate != null) {
      filtered = filtered.where((log) {
        final logDate = DateTime.parse(log['timestamp']);
        return logDate.year == selectedDate!.year &&
            logDate.month == selectedDate!.month &&
            logDate.day == selectedDate!.day;
      }).toList();
    }

    return filtered;
  }

  Color _getLevelColor(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      case 'INFO':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getLevelIcon(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return Icons.error;
      case 'WARNING':
        return Icons.warning;
      case 'INFO':
        return Icons.info;
      default:
        return Icons.circle;
    }
  }

  String _formatDateTime(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  void _showLogDetails(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getLevelIcon(log['level']),
              color: _getLevelColor(log['level']),
            ),
            const SizedBox(width: 8),
            Text('Log Details'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Level', log['level'], _getLevelColor(log['level'])),
              _detailRow('Message', log['message']),
              _detailRow('Timestamp', _formatDateTime(log['timestamp'])),
              if (log['source'] != null) _detailRow('Source', log['source']),
              if (log['user'] != null) _detailRow('User', log['user']),
              if (log['details'] != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Details:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  log['details'],
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.w600, color: darkGreen),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor ?? Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  void _clearFilters() {
    setState(() {
      selectedFilter = 'all';
      selectedDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final levelCounts = {
      'all': logs.length,
      'info': logs.where((log) => log['level'] == 'INFO').length,
      'warning': logs.where((log) => log['level'] == 'WARNING').length,
      'error': logs.where((log) => log['level'] == 'ERROR').length,
    };

    return Scaffold(
      backgroundColor: creamBackground,
      appBar: AppBar(
        title: const Text('Activity Logs'),
        backgroundColor: darkGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filters
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Level Filters
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', 'all', levelCounts['all']!),
                      _filterChip('Info', 'info', levelCounts['info']!),
                      _filterChip(
                        'Warning',
                        'warning',
                        levelCounts['warning']!,
                      ),
                      _filterChip('Error', 'error', levelCounts['error']!),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Date Filter
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: mediumGreen,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                selectedDate != null
                                    ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                                    : 'Select date',
                                style: TextStyle(
                                  color: selectedDate != null
                                      ? darkGreen
                                      : Colors.grey.shade600,
                                ),
                              ),
                              if (selectedDate != null)
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.grey.shade500,
                                      ),
                                      onPressed: () =>
                                          setState(() => selectedDate = null),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (selectedFilter != 'all' || selectedDate != null)
                      TextButton(
                        onPressed: _clearFilters,
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    darkGreen.withValues(alpha: 0.1),
                    mediumGreen.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: mediumGreen.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _logStat('Total Logs', logs.length, Icons.list),
                  _logStat(
                    'Today',
                    logs.where((log) {
                      final logDate = DateTime.parse(log['timestamp']);
                      final today = DateTime.now();
                      return logDate.year == today.year &&
                          logDate.month == today.month &&
                          logDate.day == today.day;
                    }).length,
                    Icons.today,
                  ),
                  _logStat(
                    'Errors',
                    levelCounts['error']!,
                    Icons.error,
                    Colors.red,
                  ),
                ],
              ),
            ),
          ),

          // Logs List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No logs found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (selectedFilter != 'all' || selectedDate != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextButton(
                              onPressed: _clearFilters,
                              child: const Text('Clear filters'),
                            ),
                          ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadLogs,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        final levelColor = _getLevelColor(log['level']);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
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
                            border: Border.all(
                              color: levelColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: levelColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _getLevelIcon(log['level']),
                                color: levelColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              log['message'],
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: darkGreen,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: levelColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        log['level'],
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: levelColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (log['source'] != null) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: mediumGreen.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          log['source'],
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: mediumGreen,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDateTime(log['timestamp']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: mediumGreen,
                            ),
                            onTap: () => _showLogDetails(log),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadLogs,
        backgroundColor: darkGreen,
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }

  Widget _filterChip(String label, String value, int count) {
    final isSelected = selectedFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.2)
                    : darkGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white : darkGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => selectedFilter = value);
        },
        backgroundColor: Colors.white,
        selectedColor: darkGreen,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(color: isSelected ? Colors.white : darkGreen),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? darkGreen : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  Widget _logStat(String label, int count, IconData icon, [Color? iconColor]) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? darkGreen).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor ?? darkGreen, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          count.toString(),
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
}
