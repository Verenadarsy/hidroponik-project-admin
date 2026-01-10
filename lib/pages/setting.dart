import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/shared.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Color darkGreen = const Color(0xFF456028);
  final Color mediumGreen = const Color(0xFF94A65E);
  final Color lightGreen = const Color(0xFFDDDDA1);
  final Color creamBackground = const Color(0xFFF8F9FA);

  static const String baseUrl =
      'https://uncollapsable-overfly-blaine.ngrok-free.dev/api';
  String? _token;

  // Settings state
  Map<String, dynamic> settings = {
    'general': {
      'site_name': 'HydroGrow Admin',
      'timezone': 'Asia/Jakarta',
      'maintenance_mode': false,
    },
    'notifications': {
      'email_alerts': true,
      'push_notifications': true,
      'critical_alerts': true,
      'daily_reports': false,
    },
    'sensors': {
      'update_interval': 10,
      'temperature_threshold': 30.0,
      'humidity_threshold': 80.0,
      'ph_min': 6.0,
      'ph_max': 7.5,
    },
    'security': {
      'two_factor_auth': false,
      'session_timeout': 30,
      'login_attempts': 5,
    },
  };

  bool isLoading = false;
  bool hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    _token = await SharedService.getToken();
    // In real app, load settings from API
    // await _loadSettings();
  }

  Future<void> _saveSettings() async {
    setState(() => isLoading = true);

    try {
      final response = await http.put(
        Uri.parse('$baseUrl/admin/settings'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'Accept': 'application/json',
        },
        body: jsonEncode(settings),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          hasUnsavedChanges = false;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error saving settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving settings: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
    }
  }

  void _updateSetting(String category, String key, dynamic value) {
    setState(() {
      settings[category][key] = value;
      hasUnsavedChanges = true;
    });
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text(
          'Are you sure you want to reset all settings to default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetToDefaults();
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _resetToDefaults() {
    setState(() {
      settings = {
        'general': {
          'site_name': 'HydroGrow Admin',
          'timezone': 'Asia/Jakarta',
          'maintenance_mode': false,
        },
        'notifications': {
          'email_alerts': true,
          'push_notifications': true,
          'critical_alerts': true,
          'daily_reports': false,
        },
        'sensors': {
          'update_interval': 10,
          'temperature_threshold': 30.0,
          'humidity_threshold': 80.0,
          'ph_min': 6.0,
          'ph_max': 7.5,
        },
        'security': {
          'two_factor_auth': false,
          'session_timeout': 30,
          'login_attempts': 5,
        },
      };
      hasUnsavedChanges = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings reset to defaults'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Widget _buildGeneralSettings() {
    return _settingsSection(
      title: 'General Settings',
      icon: Icons.settings,
      children: [
        _textSetting(
          label: 'Site Name',
          value: settings['general']['site_name'],
          onChanged: (value) => _updateSetting('general', 'site_name', value),
        ),
        _dropdownSetting(
          label: 'Timezone',
          value: settings['general']['timezone'],
          options: const [
            'Asia/Jakarta',
            'UTC',
            'America/New_York',
            'Europe/London',
          ],
          onChanged: (value) => _updateSetting('general', 'timezone', value),
        ),
        _switchSetting(
          label: 'Maintenance Mode',
          value: settings['general']['maintenance_mode'],
          onChanged: (value) =>
              _updateSetting('general', 'maintenance_mode', value),
        ),
      ],
    );
  }

  Widget _buildNotificationSettings() {
    return _settingsSection(
      title: 'Notification Settings',
      icon: Icons.notifications,
      children: [
        _switchSetting(
          label: 'Email Alerts',
          value: settings['notifications']['email_alerts'],
          onChanged: (value) =>
              _updateSetting('notifications', 'email_alerts', value),
        ),
        _switchSetting(
          label: 'Push Notifications',
          value: settings['notifications']['push_notifications'],
          onChanged: (value) =>
              _updateSetting('notifications', 'push_notifications', value),
        ),
        _switchSetting(
          label: 'Critical Alerts',
          value: settings['notifications']['critical_alerts'],
          onChanged: (value) =>
              _updateSetting('notifications', 'critical_alerts', value),
        ),
        _switchSetting(
          label: 'Daily Reports',
          value: settings['notifications']['daily_reports'],
          onChanged: (value) =>
              _updateSetting('notifications', 'daily_reports', value),
        ),
      ],
    );
  }

  Widget _buildSensorSettings() {
    return _settingsSection(
      title: 'Sensor Settings',
      icon: Icons.sensors,
      children: [
        _sliderSetting(
          label: 'Update Interval (seconds)',
          value: settings['sensors']['update_interval'].toDouble(),
          min: 5,
          max: 60,
          divisions: 11,
          unit: 's',
          onChanged: (value) =>
              _updateSetting('sensors', 'update_interval', value.toInt()),
        ),
        _sliderSetting(
          label: 'Temperature Threshold',
          value: settings['sensors']['temperature_threshold'].toDouble(),
          min: 20,
          max: 40,
          divisions: 20,
          unit: '°C',
          onChanged: (value) =>
              _updateSetting('sensors', 'temperature_threshold', value),
        ),
        _sliderSetting(
          label: 'Humidity Threshold',
          value: settings['sensors']['humidity_threshold'].toDouble(),
          min: 40,
          max: 90,
          divisions: 25,
          unit: '%',
          onChanged: (value) =>
              _updateSetting('sensors', 'humidity_threshold', value),
        ),
        _rangeSliderSetting(
          label: 'pH Range',
          minValue: settings['sensors']['ph_min'].toDouble(),
          maxValue: settings['sensors']['ph_max'].toDouble(),
          min: 4.0,
          max: 9.0,
          divisions: 50,
          onChanged: (min, max) {
            _updateSetting('sensors', 'ph_min', min);
            _updateSetting('sensors', 'ph_max', max);
          },
        ),
      ],
    );
  }

  Widget _buildSecuritySettings() {
    return _settingsSection(
      title: 'Security Settings',
      icon: Icons.security,
      children: [
        _switchSetting(
          label: 'Two-Factor Authentication',
          value: settings['security']['two_factor_auth'],
          onChanged: (value) =>
              _updateSetting('security', 'two_factor_auth', value),
        ),
        _sliderSetting(
          label: 'Session Timeout (minutes)',
          value: settings['security']['session_timeout'].toDouble(),
          min: 5,
          max: 120,
          divisions: 23,
          unit: 'min',
          onChanged: (value) =>
              _updateSetting('security', 'session_timeout', value.toInt()),
        ),
        _sliderSetting(
          label: 'Max Login Attempts',
          value: settings['security']['login_attempts'].toDouble(),
          min: 3,
          max: 10,
          divisions: 7,
          onChanged: (value) =>
              _updateSetting('security', 'login_attempts', value.toInt()),
        ),
      ],
    );
  }

  Widget _settingsSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: darkGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: darkGreen, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: darkGreen,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _textSetting({
    required String label,
    required String value,
    required Function(String) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, color: darkGreen),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: value),
            onChanged: onChanged,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: mediumGreen),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownSetting({
    required String label,
    required String value,
    required List<String> options,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, color: darkGreen),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: value,
              onChanged: onChanged,
              isExpanded: true,
              underline: const SizedBox(),
              items: options.map((option) {
                return DropdownMenuItem(value: option, child: Text(option));
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchSetting({
    required String label,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: darkGreen),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: darkGreen,
          ),
        ],
      ),
    );
  }

  Widget _sliderSetting({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    String unit = '',
    required Function(double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w600, color: darkGreen),
              ),
              Text(
                '${value.toStringAsFixed(unit == '°C' ? 1 : 0)}$unit',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: mediumGreen,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: darkGreen,
            inactiveColor: Colors.grey.shade300,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$min$unit',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                '$max$unit',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rangeSliderSetting({
    required String label,
    required double minValue,
    required double maxValue,
    required double min,
    required double max,
    required int divisions,
    required Function(double, double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w600, color: darkGreen),
              ),
              Text(
                '${minValue.toStringAsFixed(1)} - ${maxValue.toStringAsFixed(1)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: mediumGreen,
                ),
              ),
            ],
          ),
          RangeSlider(
            values: RangeValues(minValue, maxValue),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (values) => onChanged(values.start, values.end),
            activeColor: darkGreen,
            inactiveColor: Colors.grey.shade300,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                min.toStringAsFixed(1),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                max.toStringAsFixed(1),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBackground,
      appBar: AppBar(
        title: const Text('System Settings'),
        backgroundColor: darkGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (hasUnsavedChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Unsaved',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _showResetDialog,
            tooltip: 'Reset to defaults',
          ),
          IconButton(
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save),
            onPressed: isLoading ? null : _saveSettings,
            tooltip: 'Save settings',
          ),
        ],
      ),
      body: isLoading && settings.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildGeneralSettings(),
                  _buildNotificationSettings(),
                  _buildSensorSettings(),
                  _buildSecuritySettings(),

                  // Backup & Restore Section
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.backup,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Backup & Restore',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: darkGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Backup functionality coming soon',
                                        ),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.backup),
                                  label: const Text('Create Backup'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: darkGreen,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Restore functionality coming soon',
                                        ),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.restore),
                                  label: const Text('Restore from Backup'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: darkGreen,
                                    side: BorderSide(color: darkGreen),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
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

                  // System Info
                  Container(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.info,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'System Information',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: darkGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              _infoRow('App Version', '1.0.0'),
                              _infoRow('Last Backup', '2024-01-15 10:30'),
                              _infoRow('Database Size', '25.4 MB'),
                              _infoRow('Server Status', 'Online', status: true),
                              _infoRow('Last Updated', 'Just now'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: hasUnsavedChanges
          ? FloatingActionButton.extended(
              onPressed: _saveSettings,
              backgroundColor: darkGreen,
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save Changes'),
            )
          : null,
    );
  }

  Widget _infoRow(String label, String value, {bool? status}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: darkGreen),
            ),
          ),
          const SizedBox(width: 8),
          if (status != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: status
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: status ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Expanded(
              child: Text(value, style: const TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}
