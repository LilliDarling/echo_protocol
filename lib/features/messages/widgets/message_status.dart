import 'package:flutter/material.dart';
import '../../../models/echo.dart';

class MessageStatus extends StatelessWidget {
  final EchoStatus status;

  const MessageStatus({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case EchoStatus.pending:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        );

      case EchoStatus.failed:
        return const Icon(
          Icons.error_outline,
          size: 14,
          color: Colors.redAccent,
        );

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
