import 'package:flutter/material.dart';

import '../models/user_profile_model.dart';

/// Holds the patient profile shown on the public "My Profile" screen.
///
/// Data is currently mocked for the demo build; this provider intentionally
/// performs no network, database, sync, SMS or auth work.
class UserProfileProvider extends ChangeNotifier {
  UserProfile _profile;
  bool _isEditing = false;

  UserProfileProvider({UserProfile? initialProfile})
      : _profile = initialProfile ?? demoProfile;

  /// Demo profile matching Referral ID RC-2026-000142.
  static const UserProfile demoProfile = UserProfile(
    fullName: 'Rahul Sharma',
    age: 42,
    gender: 'Male',
    bloodGroup: 'B+',
    phone: '9876543210',
    village: 'Palghar, Maharashtra',
    abhaId: '12-3456-7890-1234',
    emergencyContactName: 'Sunita Sharma (Wife)',
    emergencyContactPhone: '9876543211',
    allergies: 'None',
    chronicConditions: 'None',
    lastVisit: '15 Sept 2026',
  );

  UserProfile get profile => _profile;

  String get referralId => 'RC-2026-000142';

  String get statusLabel => 'Active';

  bool get isEditing => _isEditing;

  /// Toggles the read-only / edit-mode chrome of the profile screen.
  void toggleEditMode() {
    _isEditing = !_isEditing;
    notifyListeners();
  }

  /// Demo-only local edit. Real updates will be wired to the backend later.
  void updateProfile(UserProfile updated) {
    _profile = updated;
    notifyListeners();
  }
}
