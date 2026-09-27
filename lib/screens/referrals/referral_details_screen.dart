import 'package:flutter/material.dart';
import '../../models/referral.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/date_utils.dart';
import '../../widgets/referral_status_chip.dart';
import '../../widgets/patient_info_card.dart';
import '../../widgets/primary_button.dart';
import '../../app/app_dependencies.dart';
import '../../services/local_storage/app_database.dart';

/// Screen displaying the complete journey, medical notes, and status transitions of a referral.
class ReferralDetailsScreen extends StatelessWidget {
  final Referral? referral;

  const ReferralDetailsScreen({super.key, this.referral});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final navReferral = args is Referral ? args : null;
    final currentReferral = referral ?? navReferral;

    if (currentReferral == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Referral Details')),
        body: const Center(child: Text('Referral details not found')),
      );
    }

    final provider = context.referralProvider;

    return Scaffold(
      appBar: AppBar(
        title: Text('Referral: ${currentReferral.referralToken}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status & Token Header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Referral Token', style: AppTextStyles.bodySmall),
                            const SizedBox(height: 2),
                            Text(
                              currentReferral.referralToken,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        ReferralStatusChip(status: currentReferral.status),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.sync_rounded, size: 16, color: AppColors.offlineOrange),
                            const SizedBox(width: 4),
                            Text(
                              'Sync: ${currentReferral.syncState.name.toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.offlineOrange,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Created: ${AppDateUtils.formatDateTime(currentReferral.createdAt)}',
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Patient Demographic Card
            if (currentReferral.patient != null) ...[
              Text('Patient Information', style: AppTextStyles.heading2),
              const SizedBox(height: 8),
              PatientInfoCard(patient: currentReferral.patient!),
              const SizedBox(height: 16),
            ],

            // Facility Routing Info
            Text('Facility Routing', style: AppTextStyles.heading2),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.outbox_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Source Facility', style: AppTextStyles.bodySmall),
                              Text(currentReferral.sourceFacilityId, style: AppTextStyles.heading3),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.move_to_inbox_rounded, color: AppColors.secondary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Destination Facility', style: AppTextStyles.bodySmall),
                              Text(currentReferral.destinationFacilityId, style: AppTextStyles.heading3),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Clinical Summary & Reason
            Text('Clinical Summary', style: AppTextStyles.heading2),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Chief Complaint / Reason for Referral', style: AppTextStyles.bodySmall),
                    const SizedBox(height: 4),
                    Text(currentReferral.referralReason, style: AppTextStyles.bodyLarge),
                    if (currentReferral.clinicalNotesSummary != null &&
                        currentReferral.clinicalNotesSummary!.isNotEmpty) ...[
                      const Divider(height: 20),
                      Text('Clinical Notes', style: AppTextStyles.bodySmall),
                      const SizedBox(height: 4),
                      Text(currentReferral.clinicalNotesSummary!, style: AppTextStyles.bodyMedium),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Referral Timeline / Event History (from SQLite)
            Text('Referral Timeline & Events', style: AppTextStyles.heading2),
            const SizedBox(height: 8),
            FutureBuilder<List<ReferralEventData>>(
              future: provider.getReferralEvents(currentReferral.referralToken),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final events = snapshot.data ?? [];
                if (events.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('No timeline events recorded yet.', style: AppTextStyles.bodyMedium),
                    ),
                  );
                }

                return Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          child: const Icon(Icons.event_note, size: 18, color: AppColors.primary),
                        ),
                        title: Text(event.eventType, style: AppTextStyles.heading3),
                        subtitle: Text(
                          '${event.facility ?? ''} • ${event.performedBy ?? ''}',
                          style: AppTextStyles.bodySmall,
                        ),
                        trailing: Text(
                          AppDateUtils.formatDateTime(event.timestamp),
                          style: AppTextStyles.caption,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Status Update Actions
            Text('Update Referral Journey', style: AppTextStyles.heading2),

            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Mark Patient Arrived',
              icon: Icons.how_to_reg_rounded,
              backgroundColor: AppColors.secondary,
              onPressed: () {
                // Future transition in hospital flow
              },
            ),
          ],
        ),
      ),
    );
  }
}
