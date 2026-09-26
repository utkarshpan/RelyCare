import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../models/referral.dart';
import '../../models/referral_status.dart';
import '../../providers/referral_provider.dart';
import '../../services/sms/sms_service.dart';
import '../../widgets/bottom_nav_bar.dart';

/// High-Fidelity Referral Details & Tracking Timeline Screen.
/// Displays referral triage status, patient details with urgency banner,
/// interactive vertical lifecycle timeline with GSM sync indicators, and status update actions.
class ReferralDetailsScreen extends StatefulWidget {
  final Referral? referral;

  const ReferralDetailsScreen({super.key, this.referral});

  @override
  State<ReferralDetailsScreen> createState() => _ReferralDetailsScreenState();
}

class _ReferralDetailsScreenState extends State<ReferralDetailsScreen> {
  final int _currentNavIndex = 1; // Highlight 'Incoming'

  void _handleUpdateStatus() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Status update dialog opening: Select next milestone (e.g. Patient Arrived)...',
        ),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final referralProvider = context.watch<ReferralProvider>();
    final activeReferral = widget.referral ?? referralProvider.selectedReferral;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ================= TOP CURVED HEADER =================
            _buildHeader(size, activeReferral),

            const SizedBox(height: 16),

            // ================= 1. CURRENT STATUS CARD =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildCurrentStatusCard(activeReferral),
            ),

            const SizedBox(height: 14),

            // ================= 2. PATIENT INFORMATION CARD =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildPatientInfoCard(activeReferral),
            ),

            const SizedBox(height: 14),

            // ================= 3. REFERRAL TIMELINE CARD =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildTimelineCard(activeReferral),
            ),

            const SizedBox(height: 20),

            // ================= 4. UPDATE STATUS BUTTON =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _handleUpdateStatus,
                  icon: const Icon(
                    Icons.edit_note_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                  label: Text(
                    'Update Status',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  /// Top Curved Blue Header with Title and Referral ID
  Widget _buildHeader(Size size, Referral? referral) {
    final referralIdText = referral != null
        ? 'ID: ${referral.referralToken}'
        : 'ID: RC-2026-000142';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 26),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),

            // Top Action Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Back Button
                GestureDetector(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/hospital-dashboard');
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),

                // Center RelyCare Pill Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_box_outlined,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'RelyCare',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),

                // Notification Bell with Badge
                Stack(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 22),

            // Title: Referral Details
            Text(
              'Referral Details',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),

            // Subtitle: ID
            Text(
              referralIdText,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.9),
                letterSpacing: 0.1,
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 1. Current Status Card with Red Left Accent Strip
  Widget _buildCurrentStatusCard(Referral? referral) {
    final urgencyText = referral != null
        ? (referral.urgency == ReferralUrgency.emergency
            ? 'Emergency'
            : (referral.urgency == ReferralUrgency.urgent
                ? 'High Priority'
                : 'Routine'))
        : 'High Priority';

    final isEmergency = referral?.urgency == ReferralUrgency.emergency;
    final isUrgent = referral?.urgency == ReferralUrgency.urgent;

    final Color urgencyColor = isEmergency
        ? const Color(0xFFDC2626)
        : (isUrgent ? const Color(0xFFEA580C) : const Color(0xFF16A34A));
    final Color urgencyBgColor = isEmergency
        ? const Color(0xFFFEE2E2)
        : (isUrgent ? const Color(0xFFFFEDD5) : const Color(0xFFDCFCE7));

    final String statusText = referral?.status.code ?? 'RECEIVED';
    final Color statusBgColor = referral?.status == ReferralStatus.received
        ? const Color(0xFF047857)
        : (referral?.status == ReferralStatus.completed
            ? const Color(0xFF16A34A)
            : (referral?.status == ReferralStatus.sent
                ? const Color(0xFF4F46E5)
                : const Color(0xFF2563EB)));

    final String destination = referral?.destinationFacility?.name ??
        (referral != null && referral.destinationFacilityId.isNotEmpty
            ? referral.destinationFacilityId
            : 'District Hospital');

    final String assignedUnit = referral?.clinicalNotesSummary != null &&
            referral!.clinicalNotesSummary!.isNotEmpty
        ? referral.clinicalNotesSummary!
        : (referral != null && referral.referralReason.isNotEmpty
            ? referral.referralReason
            : 'Emergency Triage / Cardiology');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Red Left Accent Border Strip
              Container(width: 5, color: urgencyColor),

              // Content Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Row: CURRENT STATUS + High Priority Pill
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'CURRENT STATUS',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: urgencyBgColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: urgencyColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  urgencyText,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: urgencyColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Large Colored RECEIVED Pill Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: statusBgColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Destination Row (with Expanded & overflow handling)
                      Row(
                        children: [
                          const Icon(
                            Icons.apartment_outlined,
                            size: 17,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF475569),
                                ),
                                children: [
                                  const TextSpan(text: 'Destination: '),
                                  TextSpan(
                                    text: destination,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Assigned Unit Row (with Expanded & overflow handling)
                      Row(
                        children: [
                          const Icon(
                            Icons.medical_services_outlined,
                            size: 17,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF475569),
                                ),
                                children: [
                                  const TextSpan(text: 'Assigned Unit: '),
                                  TextSpan(
                                    text: assignedUnit,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 2. Patient Information Card with Reason for Referral Banner
  Widget _buildPatientInfoCard(Referral? referral) {
    final patientName = referral?.patient?.fullName ??
        (referral != null ? 'Patient (${referral.patientId})' : 'Rahul Sharma');
    final age = referral?.patient != null ? '${referral!.patient!.age}' : '42';
    final gender = referral?.patient?.gender ?? 'Male';
    final uhid = referral?.patient?.id ??
        (referral != null ? referral.patientId : 'DH-884920');
    final reason = referral?.referralReason ?? 'Chest pain + breathlessness';
    final sourceFacilityName = referral?.sourceFacility?.name ??
        (referral != null && referral.sourceFacilityId.isNotEmpty
            ? referral.sourceFacilityId
            : 'PHC Palghar');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: PATIENT INFORMATION + ID Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PATIENT INFORMATION',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const Icon(
                Icons.assignment_ind_outlined,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Patient Name
          Text(
            patientName,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),

          // Demographics Row
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF475569),
              ),
              children: [
                const TextSpan(text: 'Age: '),
                TextSpan(
                  text: age,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const TextSpan(text: ' • Gender: '),
                TextSpan(
                  text: gender,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const TextSpan(text: ' • UHID: '),
                TextSpan(
                  text: uhid,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Reason for Referral Label
          Text(
            'Reason for Referral',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),

          // Soft Red Reason Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECDD3), width: 1),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Color(0xFFDC2626),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reason,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Referred by Doctor Note
          Row(
            children: [
              const Icon(
                Icons.medical_information_outlined,
                size: 16,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFF64748B),
                    ),
                    children: [
                      const TextSpan(text: 'Referred by: '),
                      const TextSpan(
                        text: 'PHC Medical Officer',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      TextSpan(text: ' ($sourceFacilityName)'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 3. Referral Timeline Card with Vertical Connected Progress Dots
  Widget _buildTimelineCard(Referral? referral) {
    return FutureBuilder<SmsDeliveryStatus>(
      future: referral != null
          ? context.read<ReferralProvider>().getSmsDeliveryStatus(referral.referralToken)
          : Future.value(SmsDeliveryStatus.notSent),
      builder: (context, snapshot) {
        final smsStatus = snapshot.data ?? SmsDeliveryStatus.notSent;
        final wasSmsSent = smsStatus == SmsDeliveryStatus.sent;

        final isCreatedDone = true;
        final isOfflineDone = true;

        final isSyncedToServer = referral != null
            ? (referral.syncState == SyncState.synced ||
                referral.status.index >= ReferralStatus.received.index)
            : true;

        final bool isNode3Done = wasSmsSent || isSyncedToServer;
        final String node3Title = wasSmsSent ? 'SMS Fallback Sent' : 'Synced to Server';
        final String node3Subtitle = wasSmsSent
            ? 'Encrypted data packet dispatched via GSM'
            : (isSyncedToServer
                ? 'Payload uploaded to central registry'
                : 'Waiting for network connection to sync');

        final isReceivedDone = referral != null
            ? referral.status.index >= ReferralStatus.received.index
            : true;
        final isArrivedDone = referral != null
            ? referral.status.index >= ReferralStatus.patientArrived.index
            : false;
        final isTreatmentDone = referral != null
            ? referral.status.index >= ReferralStatus.underTreatment.index
            : false;
        final isCompletedDone =
            referral != null ? referral.status == ReferralStatus.completed : false;

        final createdTime = referral != null
            ? AppDateUtils.formatDateTime(referral.createdAt)
            : '10:30 AM';
        final facilityInitiated = referral != null
            ? (referral.sourceFacility?.name ?? referral.sourceFacilityId)
            : 'PHC Palghar';

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row: REFERRAL TIMELINE + Live GSM Sync Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'REFERRAL TIMELINE',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Live GSM Sync',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF15803D),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Timeline Node 1: Created
              _buildTimelineNode(
                title: 'Created',
                time: createdTime,
                subtitle: 'Referral initiated by $facilityInitiated',
                isCompleted: isCreatedDone,
                isLatest: false,
                lineColor: const Color(0xFF10B981),
                showBottomLine: true,
              ),

              // Timeline Node 2: Saved Offline
              _buildTimelineNode(
                title: 'Saved Offline',
                time: createdTime,
                subtitle: 'Cached in local SQLite store',
                isCompleted: isOfflineDone,
                isLatest: isOfflineDone && !isNode3Done,
                lineColor: isNode3Done
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE2E8F0),
                showBottomLine: true,
              ),

              // Timeline Node 3: Synced to Server or SMS Fallback Sent
              _buildTimelineNode(
                title: node3Title,
                time: isNode3Done ? createdTime : null,
                pendingText: isNode3Done ? null : '(Pending)',
                subtitle: node3Subtitle,
                isCompleted: isNode3Done,
                isLatest: isNode3Done && !isReceivedDone,
                lineColor: isReceivedDone
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE2E8F0),
                showBottomLine: true,
              ),

              // Timeline Node 4: Hospital Received
              _buildTimelineNode(
                title: 'Hospital Received',
                time: isReceivedDone ? 'Triage Confirmed' : null,
                pendingText: isReceivedDone ? null : '(Pending)',
                subtitle: 'District Hospital triage workstation confirmed',
                isCompleted: isReceivedDone,
                isLatest: isReceivedDone && !isArrivedDone,
                lineColor: isArrivedDone
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE2E8F0),
                showBottomLine: true,
              ),

              // Timeline Node 5: Patient Arrived
              _buildTimelineNode(
                title: 'Patient Arrived',
                pendingText: isArrivedDone ? null : '(Pending)',
                subtitle: 'Awaiting physical arrival at check-in',
                isCompleted: isArrivedDone,
                isLatest: isArrivedDone && !isTreatmentDone,
                lineColor: isTreatmentDone
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE2E8F0),
                showBottomLine: true,
              ),

              // Timeline Node 6: Under Treatment
              _buildTimelineNode(
                title: 'Under Treatment',
                pendingText: isTreatmentDone ? null : '(Pending)',
                subtitle: 'Assigned to medical specialist',
                isCompleted: isTreatmentDone,
                isLatest: isTreatmentDone && !isCompletedDone,
                lineColor: isCompletedDone
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE2E8F0),
                showBottomLine: true,
              ),

              // Timeline Node 7: Completed
              _buildTimelineNode(
                title: 'Completed',
                pendingText: isCompletedDone ? null : '(Pending)',
                subtitle: 'Outcome report and PHC counter-referral',
                isCompleted: isCompletedDone,
                isLatest: isCompletedDone,
                lineColor: Colors.transparent,
                showBottomLine: false,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Individual Vertical Timeline Item with Connected Indicator Lines
  Widget _buildTimelineNode({
    required String title,
    String? time,
    String? pendingText,
    required String subtitle,
    required bool isCompleted,
    required bool isLatest,
    required Color lineColor,
    required bool showBottomLine,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Dot & Vertical Line
          Column(
            children: [
              // Dot Indicator
              if (isCompleted)
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                )
              else
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF94A3B8),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

              // Connecting Line
              if (showBottomLine)
                Expanded(child: Container(width: 2, color: lineColor)),
            ],
          ),

          const SizedBox(width: 12),

          // Right Column: Content Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: isCompleted
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isCompleted
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                            if (pendingText != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                pendingText,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                            if (isLatest) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'LATEST',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF15803D),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (time != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: isLatest
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isLatest
                                ? const Color(0xFF15803D)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),

                  // Subtitle
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Custom Bottom Navigation Bar matching Hospital Dashboard (Highlight 'Incoming')
  Widget _buildBottomNavigationBar() {
    return BottomNavBar(
      currentIndex: _currentNavIndex,
      items: const [
        BottomNavItem(icon: Icons.home_rounded, label: 'Home'),
        BottomNavItem(icon: Icons.move_to_inbox_outlined, label: 'Incoming'),
        BottomNavItem(icon: Icons.sync_rounded, label: 'Sync', badgeCount: 4),
        BottomNavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
      ],
      activeColor: AppColors.primary,
      inactiveColor: Color(0xFF64748B),
      onTap: (index) {
        if (index == _currentNavIndex) return;
        switch (index) {
          case 0:
            context.go('/hospital-dashboard');
            break;
          case 1:
            context.go('/identity-matching');
            break;
          case 2:
            context.go('/sync-status');
            break;
          case 3:
            context.go('/profile');
            break;
        }
      },
    );
  }
}
