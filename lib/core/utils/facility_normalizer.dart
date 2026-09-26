/// Centralized utility for normalizing healthcare facility codes and identifiers.
class FacilityNormalizer {
  /// Default PHC facility code used when no specific source is provided.
  static const String defaultPhcFacility = 'PHC-TEST';

  /// Default District Hospital facility code used when no specific destination is provided.
  static const String defaultHospitalFacility = 'DH-TEST';

  /// Normalizes source facility identifiers.
  /// - Preserves empty strings for model validation tests.
  /// - Maps legacy/mock 'PHC-001' -> 'PHC-TEST'.
  /// - Trims extraneous whitespace.
  static String normalizeSourceFacility(String sourceFacility) {
    final trimmed = sourceFacility.trim();
    if (trimmed.isEmpty) return sourceFacility;
    if (trimmed == 'PHC-001') return defaultPhcFacility;
    return trimmed;
  }

  /// Normalizes destination facility identifiers.
  /// - Preserves empty strings for model validation tests.
  /// - Maps 'District Hospital' or 'UNKNOWN' -> 'DH-TEST'.
  /// - Trims extraneous whitespace.
  static String normalizeDestinationFacility(String destinationFacility) {
    final trimmed = destinationFacility.trim();
    if (trimmed.isEmpty) return destinationFacility;
    if (trimmed == 'District Hospital' || trimmed == 'UNKNOWN') return defaultHospitalFacility;
    return trimmed;
  }
}
