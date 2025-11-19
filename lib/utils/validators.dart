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
      return 'Email contains invalid characters - please enter a valid email';
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
      'password',
      'admin',
      'welcome',
      'qwerty',
      '123456',
    ];

    final lowerValue = value.toLowerCase();
    for (var weak in weakPasswords) {
      if (lowerValue.contains(weak)) {
        return 'Password is too common. Please choose a stronger password';
      }
    }

    // Check for sequential characters (prevents 1234, abcd patterns - 4+ consecutive)
    if (RegExp(r'(0123|1234|2345|3456|4567|5678|6789|abcd|bcde|cdef|defg|efgh|fghi|ghij|hijk|ijkl|jklm|klmn|lmno|mnop|nopq|opqr|pqrs|qrst|rstu|stuv|tuvw|uvwx|vwxy|wxyz)', caseSensitive: false).hasMatch(value)) {
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

  // Display name validation with security hardening
  static String? validateDisplayName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Name is required';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.length < 2) {
      return 'Name must be at least 2 characters';
    }

    if (trimmedValue.length > 50) {
      return 'Name must be less than 50 characters';
    }

    // Block dangerous characters that could be used for XSS or injection
    if (RegExp(r'[<>"\\;{}()\[\]]').hasMatch(trimmedValue)) {
      return 'Name contains invalid characters';
    }

    // Block control characters and zero-width characters
    if (RegExp(r'[\x00-\x1F\x7F\u200B-\u200D\uFEFF]').hasMatch(trimmedValue)) {
      return 'Name contains invalid characters';
    }

    // Block standalone special characters
    if (RegExp(r'^[^a-zA-Z0-9]+$').hasMatch(trimmedValue)) {
      return 'Name must contain at least one letter or number';
    }

    return null;
  }
}
