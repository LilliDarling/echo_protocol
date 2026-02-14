import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../models/vault/retention_settings.dart';

class StorageSettingsScreen extends StatelessWidget {
  const StorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage & Backup'),
      ),
      body: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          final currentPolicy = themeProvider.preferences.vaultRetention;

          return ListView(
            children: [
              _buildSectionHeader(context, 'Vault Retention'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Control what gets stored in your encrypted vault backup.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
              _buildPolicyOption(
                context,
                themeProvider,
                RetentionPolicy.everything,
                'Everything',
                'Keep all messages and media forever',
                Icons.cloud_done,
                currentPolicy,
              ),
              _buildPolicyOption(
                context,
                themeProvider,
                RetentionPolicy.smart,
                'Smart',
                'Messages forever, media for 1 year',
                Icons.auto_awesome,
                currentPolicy,
              ),
              _buildPolicyOption(
                context,
                themeProvider,
                RetentionPolicy.minimal,
                'Minimal',
                'Messages forever, media for 30 days',
                Icons.compress,
                currentPolicy,
              ),
              _buildPolicyOption(
                context,
                themeProvider,
                RetentionPolicy.messagesOnly,
                'Messages Only',
                'No media stored in vault',
                Icons.text_snippet,
                currentPolicy,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Your vault is end-to-end encrypted. Only you can read its contents.',
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

  Widget _buildPolicyOption(
    BuildContext context,
    ThemeProvider themeProvider,
    RetentionPolicy policy,
    String title,
    String subtitle,
    IconData icon,
    RetentionPolicy currentPolicy,
  ) {
    final isSelected = policy == currentPolicy;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.teal.shade700 : Colors.grey.shade600,
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
          : null,
      onTap: () => themeProvider.setVaultRetention(policy),
    );
  }
}
