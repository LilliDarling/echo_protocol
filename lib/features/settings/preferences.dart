import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/theme_provider.dart';

class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
      ),
      body: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return ListView(
            children: [
              _buildSectionHeader(context, 'Appearance'),
              _buildThemeSelector(context, themeProvider),

              const Divider(height: 32),

              _buildSectionHeader(context, 'Notifications'),
              SwitchListTile(
                title: const Text('Push Notifications'),
                subtitle: const Text('Receive notifications for new messages'),
                value: themeProvider.preferences.notifications,
                onChanged: (value) => themeProvider.setNotifications(value),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.notifications,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),

              const Divider(height: 32),

              _buildSectionHeader(context, 'Privacy'),
              _buildAutoDeleteSelector(context, themeProvider),

              const SizedBox(height: 32),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Changes are saved automatically',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildThemeSelector(BuildContext context, ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.palette,
                  color: Colors.purple.shade700,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Theme',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.settings_suggest),
              ),
            ],
            selected: {themeProvider.themeMode},
            onSelectionChanged: (selection) {
              themeProvider.setThemeMode(selection.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAutoDeleteSelector(BuildContext context, ThemeProvider themeProvider) {
    final autoDeleteDays = themeProvider.preferences.autoDeleteDays;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.auto_delete,
          color: Colors.red.shade700,
        ),
      ),
      title: const Text('Auto-Delete Messages'),
      subtitle: Text(_formatAutoDeleteDays(autoDeleteDays)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showAutoDeleteDialog(context, themeProvider, autoDeleteDays),
    );
  }

  String _formatAutoDeleteDays(int days) {
    if (days == 0) return 'Never';
    if (days == 1) return 'After 1 day';
    if (days == 7) return 'After 1 week';
    if (days == 30) return 'After 1 month';
    if (days == 90) return 'After 3 months';
    return 'After $days days';
  }

  void _showAutoDeleteDialog(
    BuildContext context,
    ThemeProvider themeProvider,
    int currentValue,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auto-Delete Messages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAutoDeleteOption(context, themeProvider, 0, 'Never', currentValue),
            _buildAutoDeleteOption(context, themeProvider, 7, '1 week', currentValue),
            _buildAutoDeleteOption(context, themeProvider, 14, '2 weeks', currentValue),
            _buildAutoDeleteOption(context, themeProvider, 30, '1 month', currentValue),
            _buildAutoDeleteOption(context, themeProvider, 90, '3 months', currentValue),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoDeleteOption(
    BuildContext context,
    ThemeProvider themeProvider,
    int days,
    String label,
    int currentValue,
  ) {
    final isSelected = days == currentValue;

    return ListTile(
      title: Text(label),
      trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
      onTap: () {
        themeProvider.setAutoDeleteDays(days);
        Navigator.pop(context);
      },
    );
  }
}
