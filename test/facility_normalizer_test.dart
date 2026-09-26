import 'package:flutter_test/flutter_test.dart';
import 'package:relycare/core/utils/facility_normalizer.dart';

void main() {
  group('FacilityNormalizer Tests', () {
    test('Normalizes PHC-001 to PHC-TEST while preserving valid facilities', () {
      expect(FacilityNormalizer.normalizeSourceFacility('PHC-001'), equals('PHC-TEST'));
      expect(FacilityNormalizer.normalizeSourceFacility('  PHC-001  '), equals('PHC-TEST'));
      expect(FacilityNormalizer.normalizeSourceFacility('PHC-TEST'), equals('PHC-TEST'));
      expect(FacilityNormalizer.normalizeSourceFacility('PHC-MUMBAI'), equals('PHC-MUMBAI'));
    });

    test('Preserves empty source facility string for model validation', () {
      expect(FacilityNormalizer.normalizeSourceFacility(''), equals(''));
      expect(FacilityNormalizer.normalizeSourceFacility('   '), equals('   '));
    });

    test('Normalizes District Hospital and UNKNOWN to DH-TEST while preserving valid hospital IDs', () {
      expect(FacilityNormalizer.normalizeDestinationFacility('District Hospital'), equals('DH-TEST'));
      expect(FacilityNormalizer.normalizeDestinationFacility('  District Hospital  '), equals('DH-TEST'));
      expect(FacilityNormalizer.normalizeDestinationFacility('UNKNOWN'), equals('DH-TEST'));
      expect(FacilityNormalizer.normalizeDestinationFacility('DH-TEST'), equals('DH-TEST'));
      expect(FacilityNormalizer.normalizeDestinationFacility('City General'), equals('City General'));
    });

    test('Preserves empty destination facility string for model validation', () {
      expect(FacilityNormalizer.normalizeDestinationFacility(''), equals(''));
      expect(FacilityNormalizer.normalizeDestinationFacility('   '), equals('   '));
    });
  });
}
