class StudentDirectoryPolicy {
  const StudentDirectoryPolicy._();

  static bool isSearchableStudent(Map<String, dynamic> data) {
    final role = _safe(data['role']).toLowerCase();
    if (role != 'student') return false;

    final accountStatus = normalizedAccountStatus(data);
    if (accountStatus != 'active') return false;

    final verification = normalizedStudentVerificationStatus(data);
    if (verification == 'verified') return true;

    final importedByAdmin = data['importedByAdmin'] == true;
    final directoryVisible = data['directoryVisible'] == true;
    return importedByAdmin || directoryVisible;
  }

  static String normalizedAccountStatus(Map<String, dynamic> data) {
    final accountField = _safe(data['accountStatus']).toLowerCase();
    if (accountField.isNotEmpty) return accountField;

    final legacy = _safe(data['status']).toLowerCase();
    return legacy == 'inactive' ? 'inactive' : 'active';
  }

  static String normalizedStudentVerificationStatus(Map<String, dynamic> data) {
    String normalize(String raw) {
      switch (raw) {
        case 'pending_email_verification':
        case 'pending_profile':
        case 'pending_approval':
        case 'verified':
        case 'rejected':
          return raw;
        case 'pending_verification':
          return 'pending_approval';
        default:
          return '';
      }
    }

    final field = normalize(
      _safe(data['studentVerificationStatus']).toLowerCase(),
    );
    if (field.isNotEmpty) return field;

    final legacy = normalize(_safe(data['status']).toLowerCase());
    if (legacy.isNotEmpty) return legacy;

    final legacyStatus = _safe(data['status']).toLowerCase();
    return legacyStatus == 'active' ? 'verified' : 'pending_profile';
  }

  static String _safe(dynamic value) => (value ?? '').toString().trim();
}
