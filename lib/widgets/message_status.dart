import 'package:flutter/material.dart';
import '../models/echo.dart';

/// Widget displaying message delivery status (sent, delivered, read)
class MessageStatus extends StatelessWidget {
  final EchoStatus status;

  const MessageStatus({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case EchoStatus.sent:
        return const Icon(
          Icons.check,
          size: 14,
          color: Colors.white70,
        );

      case EchoStatus.delivered:
        return const _DoubleCheck(
          color: Colors.white70,
        );

      case EchoStatus.read:
        return const _DoubleCheck(
          color: Colors.lightBlueAccent,
        );
    }
  }
}

/// Double check mark widget for delivered/read status
class _DoubleCheck extends StatelessWidget {
  final Color color;

  const _DoubleCheck({
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 14,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: Icon(
              Icons.check,
              size: 14,
              color: color,
            ),
          ),
          Positioned(
            left: 6,
            child: Icon(
              Icons.check,
              size: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
