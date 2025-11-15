import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/device_linking.dart';

class DeviceLinkingScreen extends StatefulWidget {
  final String userId;

  const DeviceLinkingScreen({
    super.key,
    required this.userId,
  });

  @override
  State<DeviceLinkingScreen> createState() => _DeviceLinkingScreenState();
}

class _DeviceLinkingScreenState extends State<DeviceLinkingScreen> {
  final DeviceLinkingService _linkingService = DeviceLinkingService();
  DeviceLinkData? _linkData;
  bool _isGenerating = false;
  List<LinkedDevice> _linkedDevices = [];

  @override
  void initState() {
    super.initState();
    _loadLinkedDevices();
  }

  Future<void> _loadLinkedDevices() async {
    final devices = await _linkingService.getLinkedDevices(widget.userId);
    setState(() {
      _linkedDevices = devices;
    });
  }

  Future<void> _generateQRCode() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      final linkData = await _linkingService.generateLinkQRCode(widget.userId);
      setState(() {
        _linkData = linkData;
        _isGenerating = false;
      });

      // Auto-cancel after expiration
      Future.delayed(linkData.timeRemaining, () {
        if (mounted && _linkData?.linkToken == linkData.linkToken) {
          setState(() {
            _linkData = null;
          });
        }
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating QR code: $e')),
        );
      }
    }
  }

  Future<void> _cancelLink() async {
    if (_linkData != null) {
      await _linkingService.cancelDeviceLink(_linkData!.linkToken);
      setState(() {
        _linkData = null;
      });
    }
  }

  Future<void> _removeDevice(String deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Device'),
        content: const Text(
          'Are you sure you want to remove this device? '
          'That device will no longer be able to decrypt messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _linkingService.removeLinkedDevice(widget.userId, deviceId);
        await _loadLinkedDevices();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device removed')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error removing device: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Devices'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Link New Device Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Link New Device',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan this QR code from your other device to link it to your account.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    if (_linkData != null) ...[
                      // Show QR Code
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: QrImageView(
                            data: _linkData!.qrCodeData,
                            version: QrVersions.auto,
                            size: 250,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Expires in ${_linkData!.timeRemaining.inMinutes}:${(_linkData!.timeRemaining.inSeconds % 60).toString().padLeft(2, '0')}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _cancelLink,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ] else ...[
                      // Show Generate Button
                      ElevatedButton.icon(
                        onPressed: _isGenerating ? null : _generateQRCode,
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.qr_code_2),
                        label: Text(_isGenerating ? 'Generating...' : 'Generate QR Code'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Linked Devices Section
            const Text(
              'Your Devices',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (_linkedDevices.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No linked devices',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ..._linkedDevices.map((device) {
                return Card(
                  child: ListTile(
                    leading: Icon(
                      _getPlatformIcon(device.platform),
                      size: 32,
                    ),
                    title: Text(device.deviceName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Platform: ${device.platform}'),
                        Text(
                          'Linked: ${_formatDate(device.linkedAt)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Last active: ${_formatDate(device.lastActive)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _removeDevice(device.deviceId),
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return Icons.android;
      case 'ios':
        return Icons.phone_iphone;
      case 'windows':
        return Icons.computer;
      case 'macos':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.laptop;
      default:
        return Icons.devices;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}
