import 'package:flutter/material.dart';

import '../models/referral_journey_model.dart';

/// Holds the referral journey timeline and which scenario is being viewed.
class ReferralJourneyProvider extends ChangeNotifier {
  /// When true the failure scenario is shown, otherwise the success scenario.
  bool showFailure = false;

  ReferralJourneyProvider();

  /// Demo journey for Referral ID RC-2026-000142.
  static const ReferralJourney demoJourney = ReferralJourney(
    referralId: 'RC-2026-000142',
    successEvents: [
      ReferralJourneyEvent(
        time: '10:05',
        label: 'Referral Created',
        state: JourneyEventState.success,
      ),
      ReferralJourneyEvent(
        time: '10:06',
        label: 'Saved Offline',
        state: JourneyEventState.success,
      ),
      ReferralJourneyEvent(
        time: '10:08',
        label: 'Internet Restored',
        state: JourneyEventState.success,
      ),
      ReferralJourneyEvent(
        time: '10:08',
        label: 'Synced with Server',
        state: JourneyEventState.success,
      ),
      ReferralJourneyEvent(
        time: '10:09',
        label: 'Hospital Received',
        state: JourneyEventState.success,
        isMilestone: true,
      ),
      ReferralJourneyEvent(
        time: '10:24',
        label: 'Patient Arrived',
        state: JourneyEventState.success,
      ),
      ReferralJourneyEvent(
        time: '10:31',
        label: 'Treatment Started',
        state: JourneyEventState.success,
      ),
      ReferralJourneyEvent(
        time: '11:45',
        label: 'Referral Completed',
        state: JourneyEventState.success,
        isMilestone: true,
        isLast: true,
      ),
    ],
    failureEvents: [
      ReferralJourneyEvent(
        time: '10:05',
        label: 'Referral Created',
        state: JourneyEventState.success,
      ),
      ReferralJourneyEvent(
        time: '10:06',
        label: 'Saved Offline',
        state: JourneyEventState.success,
      ),
      ReferralJourneyEvent(
        time: '10:20',
        label: 'Sync Unsuccessful',
        state: JourneyEventState.warning,
      ),
      ReferralJourneyEvent(
        time: '10:25',
        label: 'Hospital Not Acknowledged',
        state: JourneyEventState.warning,
      ),
      ReferralJourneyEvent(
        time: '10:30',
        label: 'Referral at Risk',
        state: JourneyEventState.danger,
        isMilestone: true,
      ),
      ReferralJourneyEvent(
        time: '10:31',
        label: 'Fallback Action Triggered',
        state: JourneyEventState.danger,
        isMilestone: true,
        isLast: true,
      ),
    ],
  );

  ReferralJourney get journey => demoJourney;

  String get referralId => demoJourney.referralId;

  /// Events matching the currently selected scenario.
  List<ReferralJourneyEvent> get activeEvents =>
      showFailure ? demoJourney.failureEvents : demoJourney.successEvents;

  void toggleScenario(bool value) {
    if (showFailure == value) return;
    showFailure = value;
    notifyListeners();
  }
}
