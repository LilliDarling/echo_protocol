import 'package:flutter/services.dart';
import 'dart:io';

class ScreenshotProtectionService {
  static const MethodChannel _channel = MethodChannel('com.echo.protocol/screenshot');

  static Future<void> enableProtection() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      await _channel.invokeMethod('enableProtection');
    } catch (e) {
      // Platform doesn't support or already protected
    }
  }

  static Future<void> disableProtection() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      await _channel.invokeMethod('disableProtection');
    } catch (e) {
      // Platform doesn't support
    }
  }
}
