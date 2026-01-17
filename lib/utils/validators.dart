class Validators {
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.length > 254) {
      return 'Email address is too long';
    }

    final emailRegex = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
    );

    if (!emailRegex.hasMatch(trimmedValue)) {
      return 'Please enter a valid email';
    }

    if (RegExp(r'''[<>"';(){}\[\]\\]''').hasMatch(trimmedValue)) {
      return 'Email contains invalid characters - please enter a valid email';
    }

    if (trimmedValue.split('@').length != 2) {
      return 'Please enter a valid email';
    }

    final parts = trimmedValue.split('@');
    if (!parts[1].contains('.')) {
      return 'Please enter a valid email domain';
    }

    if (trimmedValue.contains('..')) {
      return 'Email contains invalid character sequence';
    }

    return null;
  }

  static String? validateOptionalEmail(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return validateEmail(value);
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 12) {
      return 'Password must be at least 12 characters';
    }

    if (value.length > 128) {
      return 'Password must be less than 128 characters';
    }

    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }

    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }

    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }

    if (!RegExp(r'''[!@#$%^&*(),.?":{}|<>_+=\-\[\]\\;/~`]''').hasMatch(value)) {
      return r'Password must contain at least one special character (!@#$%^&*(),.?":{}|<>_+-=[]\;/~`)';
    }

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

    if (RegExp(r'(0123|1234|2345|3456|4567|5678|6789|abcd|bcde|cdef|defg|efgh|fghi|ghij|hijk|ijkl|jklm|klmn|lmno|mnop|nopq|opqr|pqrs|qrst|rstu|stuv|tuvw|uvwx|vwxy|wxyz)', caseSensitive: false).hasMatch(value)) {
      return 'Password contains sequential characters. Please use a more random pattern';
    }

    if (RegExp(r'(.)\1{3,}').hasMatch(value)) {
      return 'Password contains too many repeated characters';
    }

    return null;
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

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

    if (RegExp(r'[<>"\\;{}()\[\]]').hasMatch(trimmedValue)) {
      return 'Name contains invalid characters';
    }

    if (RegExp(r'[\x00-\x1F\x7F\u200B-\u200D\uFEFF]').hasMatch(trimmedValue)) {
      return 'Name contains invalid characters';
    }

    if (RegExp(r'^[^a-zA-Z0-9]+$').hasMatch(trimmedValue)) {
      return 'Name must contain at least one letter or number';
    }

    return null;
  }

  static String? validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Username is required';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.length < 3) {
      return 'Username must be at least 3 characters';
    }

    if (trimmedValue.length > 30) {
      return 'Username must be less than 30 characters';
    }

    if (trimmedValue.contains(' ')) {
      return 'Username cannot contain spaces';
    }

    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(trimmedValue)) {
      return 'Username can only contain letters, numbers, dots, underscores, and hyphens';
    }

    if (trimmedValue.startsWith('.') || trimmedValue.endsWith('.')) {
      return 'Username cannot start or end with a dot';
    }

    if (trimmedValue.contains('..')) {
      return 'Username cannot contain consecutive dots';
    }

    if (trimmedValue.startsWith('-') || trimmedValue.endsWith('-')) {
      return 'Username cannot start or end with a hyphen';
    }

    return null;
  }
}
