/// Visual state of a single event on the referral journey timeline.
enum JourneyEventState {
  /// Completed normally.
  success,

  /// Completed, but something needs attention.
  warning,

  /// Referral is in danger.
  danger,
}

/// A single point-in-time event in a referral's journey.
class ReferralJourneyEvent {
  final String time;
  final String label;
  final JourneyEventState state;
  final bool isMilestone;
  final bool isLast;

  const ReferralJourneyEvent({
    required this.time,
    required this.label,
    this.state = JourneyEventState.success,
    this.isMilestone = false,
    this.isLast = false,
  });
}

/// Full ordered journey of a referral, in both the happy-path and the
/// failure-path variants shown by the Success / Failure toggle.
class ReferralJourney {
  final String referralId;
  final List<ReferralJourneyEvent> successEvents;
  final List<ReferralJourneyEvent> failureEvents;

  const ReferralJourney({
    required this.referralId,
    required this.successEvents,
    required this.failureEvents,
  });
}
