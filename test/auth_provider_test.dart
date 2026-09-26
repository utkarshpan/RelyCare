import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:relycare/services/api/api_service.dart';
import 'package:relycare/services/security/auth_storage_service.dart';
import 'package:relycare/providers/auth_provider.dart';
import 'package:relycare/models/user_model.dart';
import 'package:relycare/models/referral.dart';
import 'package:relycare/models/patient.dart';
import 'package:relycare/models/identity_match.dart';
import 'package:relycare/core/errors/app_exceptions.dart';

class MockTestApiService implements ApiService {
  String? authToken;
  bool shouldFailLogin = false;

  @override
  void setAuthToken(String? token) {
    authToken = token;
  }

  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    if (shouldFailLogin) {
      throw const UnauthenticatedException('Invalid username or password');
    }
    return {
      'access_token': 'mock_jwt_access_token',
      'token_type': 'bearer',
      'user': {
        'id': 1,
        'username': username,
        'email': 'user@test.org',
        'phone': '+919999999999',
        'role': 'PHC_STAFF',
        'facility_id': 'PHC_TEST',
        'is_active': true,
      },
    };
  }

  @override
  Future<UserModel> getMe() async {
    if (authToken == null || authToken!.isEmpty) {
      throw const UnauthenticatedException('Missing token');
    }
    return const UserModel(
      id: 1,
      username: 'mock_user',
      email: 'user@test.org',
      role: 'PHC_STAFF',
      facilityId: 'PHC_TEST',
      isActive: true,
    );
  }

  @override
  Future<List<Referral>> fetchReferrals({int skip = 0, int limit = 100, String? status}) async => [];

  @override
  Future<Referral> getReferral(String referralId) async => throw UnimplementedError();

  @override
  Future<Referral> createReferral(Referral referral) async => referral;

  @override
  Future<void> updateReferralStatus(String referralId, String status) async {}

  @override
  Future<List<Referral>> syncBatch(List<Referral> queuedReferrals) async => [];

  @override
  Future<List<IdentityMatch>> requestIdentityMatches(Patient incomingPatient) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthProvider Unit Tests', () {
    late MockTestApiService mockApi;
    late AuthStorageService mockStorage;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      mockApi = MockTestApiService();
      mockStorage = AuthStorageServiceImpl(storage: const FlutterSecureStorage());
    });

    test('Successful login sets authenticated state and stores JWT', () async {
      final provider = AuthProvider(apiService: mockApi, authStorage: mockStorage);
      final result = await provider.login(emailOrPhone: 'user@test.org', password: 'password123');

      assert(result == true);
      assert(provider.isAuthenticated == true);
      assert(provider.currentUser?.username == 'user@test.org');
      assert(provider.currentRole == UserRole.phcStaff);

      final token = await mockStorage.getToken();
      assert(token == 'mock_jwt_access_token');
    });

    test('Failed login sets error message and unauthenticated state', () async {
      mockApi.shouldFailLogin = true;
      final provider = AuthProvider(apiService: mockApi, authStorage: mockStorage);
      final result = await provider.login(emailOrPhone: 'user@test.org', password: 'wrongpass');

      assert(result == false);
      assert(provider.isAuthenticated == false);
      assert(provider.errorMessage == 'Invalid username or password');
    });

    test('Session restoration succeeds with stored valid token', () async {
      await mockStorage.saveToken('valid_stored_token');
      final provider = AuthProvider(apiService: mockApi, authStorage: mockStorage);
      await provider.restoreSession();

      assert(provider.isAuthenticated == true);
      assert(provider.currentUser?.username == 'mock_user');
    });

    test('Logout clears session token and user profile', () async {
      final provider = AuthProvider(apiService: mockApi, authStorage: mockStorage);
      await provider.login(emailOrPhone: 'user@test.org', password: 'password123');
      await provider.logout();

      assert(provider.isAuthenticated == false);
      assert(provider.currentUser == null);
      final token = await mockStorage.getToken();
      assert(token == null);
    });

    test('UserRole parsing correctly maps PHC_STAFF, HOSPITAL_STAFF, and PATIENT', () {
      expect(UserRole.fromString('PHC_STAFF'), UserRole.phcStaff);
      expect(UserRole.fromString('HOSPITAL_STAFF'), UserRole.hospitalStaff);
      expect(UserRole.fromString('PATIENT'), UserRole.patient);
      expect(UserRole.fromString('PHC Staff'), UserRole.phcStaff);
      expect(UserRole.fromString('Hospital Staff'), UserRole.hospitalStaff);
      expect(UserRole.fromString('Patient'), UserRole.patient);
    });
  });
}
