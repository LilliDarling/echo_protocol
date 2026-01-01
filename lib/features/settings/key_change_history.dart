import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/key_change_event.dart';
import '../../services/partner.dart';

class KeyChangeHistoryScreen extends StatefulWidget {
  const KeyChangeHistoryScreen({super.key});

  @override
  State<KeyChangeHistoryScreen> createState() => _KeyChangeHistoryScreenState();
}

class _KeyChangeHistoryScreenState extends State<KeyChangeHistoryScreen> {
  final PartnerService _partnerService = PartnerService();
  List<KeyChangeEvent>? _events;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final events = await _partnerService.getKeyChangeHistory();
    if (mounted) {
      setState(() {
        _events = events;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Code History'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _events == null || _events!.isEmpty
              ? _buildEmptyState()
              : _buildHistoryList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No security code changes',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Key changes will appear here',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events!.length,
      itemBuilder: (context, index) => _buildEventCard(_events![index]),
    );
  }

  Widget _buildEventCard(KeyChangeEvent event) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: event.acknowledged
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    event.acknowledged ? 'Verified' : 'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: event.acknowledged
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'ID: ${event.visibleId}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  dateFormat.format(event.detectedAt),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  timeFormat.format(event.detectedAt),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              'Previous:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                event.previousFingerprint,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'New:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                event.newFingerprint,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
              ),
            ),
            if (event.acknowledged && event.acknowledgedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Verified on ${dateFormat.format(event.acknowledgedAt!)} at ${timeFormat.format(event.acknowledgedAt!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
