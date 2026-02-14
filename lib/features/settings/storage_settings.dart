import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../models/vault/retention_settings.dart';
import '../../services/vault/vault_sync_service.dart';

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
              _buildSectionHeader(context, 'Vault Status'),
              _buildVaultStatusSection(context),
              const Divider(height: 32),
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

  Widget _buildVaultStatusSection(BuildContext context) {
    final vaultService = VaultSyncService();

    return StreamBuilder<VaultSyncState>(
      stream: vaultService.stateStream,
      initialData: vaultService.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? VaultSyncState.idle;

        IconData icon;
        String statusText;
        Color color;

        switch (state) {
          case VaultSyncState.idle:
            icon = Icons.cloud_done;
            statusText = 'Vault synced';
            color = Colors.green;
          case VaultSyncState.uploading:
            icon = Icons.cloud_upload;
            statusText = 'Uploading to vault...';
            color = Colors.blue;
          case VaultSyncState.downloading:
            icon = Icons.cloud_download;
            statusText = 'Downloading from vault...';
            color = Colors.blue;
          case VaultSyncState.error:
            icon = Icons.cloud_off;
            statusText = 'Vault sync error';
            color = Colors.red;
        }

        return Column(
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: state == VaultSyncState.uploading ||
                        state == VaultSyncState.downloading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(icon, color: color),
              ),
              title: Text(statusText),
              subtitle: state == VaultSyncState.error && vaultService.error != null
                  ? Text(
                      vaultService.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.red.shade300, fontSize: 12),
                    )
                  : null,
            ),
            if (state == VaultSyncState.idle || state == VaultSyncState.error)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: vaultService.isSyncing
                        ? null
                        : () {
                            vaultService
                                .uploadUnsyncedMessages()
                                .catchError((_) => 0);
                          },
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Sync Now'),
                  ),
                ),
              ),
          ],
        );
      },
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
