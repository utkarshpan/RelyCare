// ignore_for_file: prefer_initializing_formals
import 'package:flutter/material.dart';
import '../services/api/api_service.dart';

import '../services/security/auth_storage_service.dart';
import '../models/user_model.dart';
import '../core/errors/app_exceptions.dart';
import '../core/utils/logger.dart';

/// Supported User Roles in RelyCare.
enum UserRole {
  phcStaff('PHC Staff', 'PHC_STAFF'),
  hospitalStaff('Hospital Staff', 'HOSPITAL_STAFF'),
  patient('Patient', 'PATIENT');

  final String label;
  final String code;
  const UserRole(this.label, this.code);

  static UserRole fromString(String role) {
    final clean = role.replaceAll('_', ' ').toLowerCase();
    return UserRole.values.firstWhere(
      (e) => e.label.toLowerCase() == clean || e.code.toLowerCase() == role.toLowerCase(),
      orElse: () => UserRole.phcStaff,
    );
  }
}

/// Provider managing authentication state, JWT session storage, and backend user profile.
class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final AuthStorageService _authStorage;

  UserModel? _currentUser;
  String _emailOrPhone = '';
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _isAuthenticated = false;
  String? _errorMessage;

  AuthProvider({
    required ApiService apiService,
    required AuthStorageService authStorage,
  })  : _apiService = apiService,
        _authStorage = authStorage {
    restoreSession();
  }




  // Getters
  UserModel? get currentUser => _currentUser;
  String get selectedRole => _currentUser?.role ?? 'PHC_STAFF';
  UserRole get currentRole => UserRole.fromString(selectedRole);
  String get emailOrPhone => _emailOrPhone;
  bool get rememberMe => _rememberMe;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;

  List<String> get availableRoles => [
        'PHC Staff',
        'Hospital Staff',
        'Patient',
      ];

  void setRememberMe(bool value) {
    _rememberMe = value;
    if (!value) {
      _emailOrPhone = '';
      _authStorage.clearRememberedUser();
    }
    notifyListeners();
  }

  /// Restores persistent JWT authentication session upon application startup.
  Future<void> restoreSession() async {
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rememberedUser = await _authStorage.getRememberedUser();
      if (rememberedUser != null && rememberedUser.isNotEmpty) {
        _emailOrPhone = rememberedUser;
        _rememberMe = true;
      }

      final savedToken = await _authStorage.getToken();
      if (savedToken != null && savedToken.isNotEmpty) {
        _apiService.setAuthToken(savedToken);
        try {
          final user = await _apiService.getMe();
          _currentUser = user;
          _isAuthenticated = true;
          AppLogger.info('Successfully restored session for ${user.username} (${user.role})', 'AuthProvider');
        } on UnauthenticatedException catch (e) {
          AppLogger.warning('Stored JWT token invalid or expired: ${e.message}', 'AuthProvider');
          await _authStorage.deleteToken();
          await _authStorage.clearCachedUser();
          _apiService.setAuthToken(null);
          _isAuthenticated = false;
          _currentUser = null;
          _errorMessage = 'Session expired. Please log in again.';
        } on NetworkException catch (e) {
          AppLogger.warning('Network unavailable during session restoration: ${e.message}', 'AuthProvider');
          final cachedUser = await _authStorage.getCachedUser();
          if (cachedUser != null) {
            _currentUser = cachedUser;
            _isAuthenticated = true;
            AppLogger.info('Offline session restored for ${cachedUser.username} (${cachedUser.role})', 'AuthProvider');
          }
        }
      }
    } catch (e, stack) {
      AppLogger.error('Failed restoring auth session', e, stack, 'AuthProvider');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Performs real login against FastAPI backend and securely stores JWT token.
  Future<bool> login({required String emailOrPhone, required String password}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _apiService.login(emailOrPhone, password);
      final token = data['access_token'] as String;
      final userMap = data['user'] as Map<String, dynamic>;

      await _authStorage.saveToken(token);
      _apiService.setAuthToken(token);

      if (_rememberMe) {
        _emailOrPhone = emailOrPhone;
        await _authStorage.saveRememberedUser(emailOrPhone);
      } else {
        _emailOrPhone = '';
        await _authStorage.clearRememberedUser();
      }

      _currentUser = UserModel.fromJson(userMap);
      await _authStorage.saveCachedUser(_currentUser!);
      _isAuthenticated = true;
      _isLoading = false;

      AppLogger.info('Login successful for ${_currentUser?.username} (Role: ${_currentUser?.role})', 'AuthProvider');
      notifyListeners();
      return true;
    } on UnauthenticatedException catch (e) {
      _errorMessage = e.message;
    } on UnauthorizedException catch (e) {
      _errorMessage = e.message;
    } on NetworkException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Login failed: ${e.toString()}';
    }

    _isAuthenticated = false;
    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Logs out active user, clears JWT from secure storage, and resets in-memory state.
  /// Always reconciles in-memory authentication state even if a secure storage cleanup operation throws.
  /// Does NOT delete local SQLite referral data or pending queue records.
  Future<void> logout() async {
    Object? storageError;
    try {
      await _authStorage.deleteToken();
    } catch (e, stack) {
      storageError = e;
      AppLogger.error('Failed to delete auth token during logout', e, stack, 'AuthProvider');
    }

    try {
      await _authStorage.clearCachedUser();
    } catch (e) {
      storageError ??= e;
      AppLogger.warning('Failed to clear cached user during logout: $e', 'AuthProvider');
    }

    // Always clear in-memory state so the session is never left in an inconsistent authenticated state
    _apiService.setAuthToken(null);
    _isAuthenticated = false;
    _currentUser = null;
    if (!_rememberMe) {
      _emailOrPhone = '';
    }

    if (storageError != null) {
      _errorMessage = 'Logout completed with storage warning: $storageError';
    }

    AppLogger.info('User logged out and in-memory session reset', 'AuthProvider');
    notifyListeners();
  }
}
