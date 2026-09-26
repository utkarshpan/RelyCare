import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../models/referral_journey_model.dart';
import '../providers/referral_journey_provider.dart';

/// Vertical timeline of referral events inside a white card, with a
/// Success / Failure segmented toggle in the card header.
class ReferralJourneyTimeline extends StatelessWidget {
  final List<ReferralJourneyEvent> events;
  final String referralId;

  const ReferralJourneyTimeline({
    super.key,
    required this.events,
    required this.referralId,
  });

  static const double _timeColumnWidth = 48;
  static const double _railColumnWidth = 24;

  Color _stateColor(JourneyEventState state) {
    switch (state) {
      case JourneyEventState.success:
        return AppColors.onlineGreen;
      case JourneyEventState.warning:
        return AppColors.urgencyMedium;
      case JourneyEventState.danger:
        return AppColors.urgencyHigh;
    }
  }

  IconData _stateIcon(JourneyEventState state) {
    switch (state) {
      case JourneyEventState.success:
        return Icons.check_rounded;
      case JourneyEventState.warning:
        return Icons.priority_high_rounded;
      case JourneyEventState.danger:
        return Icons.priority_high_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReferralJourneyProvider>();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(provider),
          const SizedBox(height: 20),
          ..._buildRows(),
        ],
      ),
    );
  }

  Widget _buildHeader(ReferralJourneyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Referral Journey',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'ID: $referralId',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _buildToggle(provider),
          ],
        ),
      ],
    );
  }

  Widget _buildToggle(ReferralJourneyProvider provider) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleOption(
            label: 'Success',
            selected: !provider.showFailure,
            onTap: () => provider.toggleScenario(false),
          ),
          _buildToggleOption(
            label: 'Failure',
            selected: provider.showFailure,
            onTap: () => provider.toggleScenario(true),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRows() {
    final rows = <Widget>[];

    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      final isLastRow = i == events.length - 1;
      final hasLine = !event.isLast && !isLastRow;
      // The connecting line always takes the colour of the NEXT dot.
      final nextColor = hasLine ? _stateColor(events[i + 1].state) : null;

      rows.add(_buildRow(event, hasLine, nextColor));
    }

    return rows;
  }

  Widget _buildRow(
    ReferralJourneyEvent event,
    bool hasLine,
    Color? lineColor,
  ) {
    final dotColor = _stateColor(event.state);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: time label
          SizedBox(
            width: _timeColumnWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                event.time,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),

          // Middle: dot + connecting line
          SizedBox(
            width: _railColumnWidth,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _stateIcon(event.state),
                    size: 13,
                    color: Colors.white,
                  ),
                ),
                if (hasLine)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: lineColor ?? dotColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Right: label
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20.0, top: 2),
              child: Text(
                event.label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight:
                      event.isMilestone ? FontWeight.w600 : FontWeight.w400,
                  color: event.isMilestone
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
