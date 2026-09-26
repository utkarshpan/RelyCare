/// Read-only patient profile surfaced on the public User Dashboard.
///
/// Mirrors the demographic + emergency + summary data that a patient (or
/// family member) is allowed to see about their own referral. No clinical
/// records are stored here.
class UserProfile {
  final String fullName;
  final int age;
  final String gender;
  final String bloodGroup;
  final String phone;
  final String village;
  final String abhaId;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String allergies;
  final String chronicConditions;
  final String lastVisit;

  const UserProfile({
    required this.fullName,
    required this.age,
    required this.gender,
    required this.bloodGroup,
    required this.phone,
    required this.village,
    required this.abhaId,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.allergies,
    required this.chronicConditions,
    required this.lastVisit,
  });

  /// Two-letter initials used by the avatar placeholder (e.g. "RS").
  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

    final first = parts.first.substring(0, 1);
    final last = parts.last.substring(0, 1);
    return '$first$last'.toUpperCase();
  }
}
