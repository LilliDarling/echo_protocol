import 'package:logger/logger.dart';

/// Centralized logging service for Echo Protocol
/// Uses the logger package for production-ready logging
class LoggerService {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  /// Log debug information (development only)
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log general information
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warnings
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log errors
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log fatal errors
  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }

  /// Log security events (for audit trail)
  static void security(String event, Map<String, dynamic>? data) {
    _logger.i('🔒 SECURITY EVENT: $event', error: data);
  }

  /// Log authentication events
  static void auth(String event, {String? userId}) {
    _logger.i('🔐 AUTH: $event${userId != null ? ' (User: $userId)' : ''}');
  }

  /// Log encryption operations
  static void encryption(String operation, {bool success = true}) {
    if (success) {
      _logger.d('🔑 ENCRYPTION: $operation - SUCCESS');
    } else {
      _logger.e('🔑 ENCRYPTION: $operation - FAILED');
    }
  }
}
