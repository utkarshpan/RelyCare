import 'package:flutter/material.dart';

/// Operational status enum for RelyCare Referral Guardian monitoring.
/// Guardian tracks operational workflow continuity and facility routing status,
/// NOT medical risk or clinical diagnosis.
enum ReferralGuardianStatus {
  normal,
  atRisk,
  actionRequired,
}

extension ReferralGuardianStatusExtension on ReferralGuardianStatus {
  String get displayName {
    switch (this) {
      case ReferralGuardianStatus.normal:
        return 'Normal';
      case ReferralGuardianStatus.atRisk:
        return 'At Risk';
      case ReferralGuardianStatus.actionRequired:
        return 'Action Required';
    }
  }

  String get label => displayName;

  String get emoji {
    switch (this) {
      case ReferralGuardianStatus.normal:
        return '🟢';
      case ReferralGuardianStatus.atRisk:
        return '🟠';
      case ReferralGuardianStatus.actionRequired:
        return '🔴';
    }
  }

  String get operationalDescription {
    switch (this) {
      case ReferralGuardianStatus.normal:
        return 'Referral progressing normally';
      case ReferralGuardianStatus.atRisk:
        return 'Referral awaiting hospital acknowledgement';
      case ReferralGuardianStatus.actionRequired:
        return 'Referral requires facility follow-up';
    }
  }

  String get code {
    switch (this) {
      case ReferralGuardianStatus.normal:
        return 'NORMAL';
      case ReferralGuardianStatus.atRisk:
        return 'AT_RISK';
      case ReferralGuardianStatus.actionRequired:
        return 'ACTION_REQUIRED';
    }
  }

  Color get color {
    switch (this) {
      case ReferralGuardianStatus.normal:
        return const Color(0xFF10B981); // Emerald Green
      case ReferralGuardianStatus.atRisk:
        return const Color(0xFFF59E0B); // Amber Orange
      case ReferralGuardianStatus.actionRequired:
        return const Color(0xFFEF4444); // Crimson Red
    }
  }

  Color get backgroundColor {
    switch (this) {
      case ReferralGuardianStatus.normal:
        return const Color(0xFFECFDF5);
      case ReferralGuardianStatus.atRisk:
        return const Color(0xFFFFFBEB);
      case ReferralGuardianStatus.actionRequired:
        return const Color(0xFFFEF2F2);
    }
  }

  IconData get icon {
    switch (this) {
      case ReferralGuardianStatus.normal:
        return Icons.check_circle_rounded;
      case ReferralGuardianStatus.atRisk:
        return Icons.warning_amber_rounded;
      case ReferralGuardianStatus.actionRequired:
        return Icons.error_rounded;
    }
  }
}

/// Evaluation result returned by [ReferralGuardianService].
class ReferralGuardianEvaluation {
  final ReferralGuardianStatus status;
  final String operationalSummary;

  const ReferralGuardianEvaluation({
    required this.status,
    required this.operationalSummary,
  });

  @override
  String toString() => 'ReferralGuardianEvaluation(status: ${status.code}, summary: $operationalSummary)';
}
