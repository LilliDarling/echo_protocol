import 'package:flutter/material.dart';
import '../../../models/echo.dart';

class MessageOptionsSheet extends StatelessWidget {
  final EchoModel message;
  final String decryptedText;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const MessageOptionsSheet({
    super.key,
    required this.message,
    required this.decryptedText,
    required this.onEdit,
    required this.onDelete,
  });

  static void show(
    BuildContext context, {
    required EchoModel message,
    required String decryptedText,
    required Future<void> Function(EchoModel, String) onEdit,
    required Future<void> Function(EchoModel) onDelete,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => MessageOptionsSheet(
        message: message,
        decryptedText: decryptedText,
        onEdit: () {
          Navigator.pop(ctx);
          _showEditDialog(context, message, decryptedText, onEdit);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _showDeleteConfirmation(context, message, onDelete);
        },
      ),
    );
  }

  static void _showEditDialog(
    BuildContext context,
    EchoModel message,
    String currentText,
    Future<void> Function(EchoModel, String) onEdit,
  ) {
    final controller = TextEditingController(text: currentText);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter new message',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await onEdit(message, controller.text);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to edit message: ${e.toString().replaceAll('Exception: ', '')}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static void _showDeleteConfirmation(
    BuildContext context,
    EchoModel message,
    Future<void> Function(EchoModel) onDelete,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('This message will be deleted for everyone. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await onDelete(message);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete message: ${e.toString().replaceAll('Exception: ', '')}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.type == EchoType.text)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit message'),
              onTap: onEdit,
            ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete message', style: TextStyle(color: Colors.red)),
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}
