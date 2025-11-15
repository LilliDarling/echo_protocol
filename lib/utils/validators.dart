// Form validation utilities
class Validators {
  // Email validation with security hardening
  // Prevents injection attacks and validates proper email format
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }

    // Trim whitespace to prevent bypass attempts
    final trimmedValue = value.trim();

    // Maximum length to prevent DoS attacks
    if (trimmedValue.length > 254) {
      return 'Email address is too long';
    }

    // Comprehensive email regex (RFC 5322 compliant)
    // Prevents SQL injection, XSS, and other injection attacks
    final emailRegex = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
    );

    if (!emailRegex.hasMatch(trimmedValue)) {
      return 'Please enter a valid email';
    }

    // Check for dangerous characters that might indicate injection attempts
    if (RegExp(r'''[<>"';(){}\[\]\\]''').hasMatch(trimmedValue)) {
      return 'Email contains invalid characters';
    }

    // Prevent email addresses with multiple @ symbols
    if (trimmedValue.split('@').length != 2) {
      return 'Please enter a valid email';
    }

    // Validate domain has at least one dot
    final parts = trimmedValue.split('@');
    if (!parts[1].contains('.')) {
      return 'Please enter a valid email domain';
    }

    // Prevent consecutive dots
    if (trimmedValue.contains('..')) {
      return 'Email contains invalid character sequence';
    }

    return null;
  }

  // Password validation with strong security requirements
  // Prevents weak passwords and injection attacks
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    // Minimum length: 12 characters (industry best practice)
    if (value.length < 12) {
      return 'Password must be at least 12 characters';
    }

    // Maximum length to prevent DoS attacks
    if (value.length > 128) {
      return 'Password must be less than 128 characters';
    }

    // Check for at least one uppercase letter
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }

    // Check for at least one lowercase letter
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }

    // Check for at least one digit
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }

    // Check for at least one special character
    // Note: Using a safe set of special characters to prevent injection
    if (!RegExp(r'''[!@#$%^&*(),.?":{}|<>_+=\-\[\]\\;/~`]''').hasMatch(value)) {
      return r'Password must contain at least one special character (!@#$%^&*(),.?":{}|<>_+-=[]\;/~`)';
    }

    // Prevent common weak passwords
    final weakPasswords = [
      'password123!',
      'password1234',
      'admin123456!',
      'welcome12345',
      '123456789abc',
      'qwerty123456',
    ];

    final lowerValue = value.toLowerCase();
    for (var weak in weakPasswords) {
      if (lowerValue.contains(weak.toLowerCase())) {
        return 'Password is too common. Please choose a stronger password';
      }
    }

    // Check for sequential characters (prevents 123456, abcdef patterns)
    if (RegExp(r'(012|123|234|345|456|567|678|789|abc|bcd|cde|def|efg|fgh|ghi|hij|ijk|jkl|klm|lmn|mno|nop|opq|pqr|qrs|rst|stu|tuv|uvw|vwx|wxy|xyz)', caseSensitive: false).hasMatch(value)) {
      return 'Password contains sequential characters. Please use a more random pattern';
    }

    // Check for repeated characters (prevents aaaa, 1111 patterns)
    if (RegExp(r'(.)\1{3,}').hasMatch(value)) {
      return 'Password contains too many repeated characters';
    }

    return null;
  }

  // Required field validation
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }
}
