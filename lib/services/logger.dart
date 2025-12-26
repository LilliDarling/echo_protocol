import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// Centralized logging service for Echo Protocol
class LoggerService {
  static final Logger _logger = Logger(
    printer: kDebugMode
        ? PrettyPrinter(
            methodCount: 2,
            errorMethodCount: 8,
            lineLength: 120,
            colors: true,
            printEmojis: true,
            dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
          )
        : SimplePrinter(),
    level: kDebugMode ? Level.debug : Level.warning,
  );

  /// Log debug information (development only)
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.d(message, error: error, stackTrace: stackTrace);
    }
  }

  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.i(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Log warnings
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log errors
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    _sendToMonitoring(message, error, stackTrace, Level.error);
  }

  /// Log fatal errors
  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
    _sendToMonitoring(message, error, stackTrace, Level.fatal);
  }

  /// Log security events (for audit trail)
  static void security(String event, Map<String, dynamic>? data) {
    final logData = {
      'timestamp': DateTime.now().toIso8601String(),
      'event': event,
      'data': data,
    };

    if (kDebugMode) {
      _logger.i('🔒 SECURITY EVENT: $event', error: data);
    } else {
      _sendSecurityEvent(logData);
    }
  }

  /// Log authentication events
  static void auth(String event, {String? userId}) {
    if (kDebugMode) {
      _logger.i('🔐 AUTH: $event${userId != null ? ' (User: $userId)' : ''}');
    }
  }

  /// Log encryption operations
  static void encryption(String operation, {bool success = true}) {
    if (kDebugMode) {
      if (success) {
        _logger.d('🔑 ENCRYPTION: $operation - SUCCESS');
      } else {
        _logger.e('🔑 ENCRYPTION: $operation - FAILED');
      }
    }
  }

  static void _sendToMonitoring(
    String message,
    dynamic error,
    StackTrace? stackTrace,
    Level level,
  ) {
    // Production monitoring can be added here when needed
  }

  static void _sendSecurityEvent(Map<String, dynamic> logData) {
    // Production security event logging can be added here when needed
  }
}
