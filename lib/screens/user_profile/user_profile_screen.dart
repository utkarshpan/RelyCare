import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../models/user_profile_model.dart';
import '../../providers/user_profile_provider.dart';

/// Public read-only screen showing the patient's own profile.
/// No authentication required and no bottom navigation bar.
class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserProfileProvider>();
    final profile = provider.profile;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===================== CURVED BLUE HEADER =====================
            _buildHeader(context, provider),

            // ===================== PROFILE CARD (overlaps header) =====================
            Transform.translate(
              offset: const Offset(0, -34),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildProfileCard(profile, provider.statusLabel),
              ),
            ),

            // ===================== DETAIL CARDS =====================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -18),
                    child: _buildPersonalInfoCard(profile),
                  ),
                  _buildEmergencyContactCard(context, profile),
                  const SizedBox(height: 14),
                  _buildHealthSummaryCard(profile),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context, UserProfileProvider provider) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 52),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),

            // Top row: back arrow (left), edit pencil (right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    // Pops back to Referral Status, which pushed this screen.
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/referral-status');
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
                GestureDetector(
                  onTap: provider.toggleEditMode,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      provider.isEditing
                          ? Icons.close_rounded
                          : Icons.edit_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Center-aligned title
            Text(
              'My Profile',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),

            Text(
              'Referral ID: ${provider.referralId}',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.88),
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PROFILE CARD
  // ---------------------------------------------------------------------------
  Widget _buildProfileCard(UserProfile profile, String statusLabel) {
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular avatar placeholder with initials
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              profile.initials,
              style: GoogleFonts.inter(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Full name
          Text(
            profile.fullName,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),

          // Age • Gender
          Text(
            'Age: ${profile.age} • ${profile.gender}',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          // Green Active pill badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.onlineGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onlineGreen,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PERSONAL INFORMATION CARD
  // ---------------------------------------------------------------------------
  Widget _buildPersonalInfoCard(UserProfile profile) {
    return _buildSectionCard(
      title: 'Personal Information',
      children: [
        _buildInfoRow(
          icon: Icons.person_outline_rounded,
          label: 'Full Name',
          value: profile.fullName,
        ),
        _buildInfoRow(
          icon: Icons.cake_outlined,
          label: 'Age',
          value: '${profile.age}',
        ),
        _buildInfoRow(
          icon: Icons.wc_rounded,
          label: 'Gender',
          value: profile.gender,
        ),
        _buildInfoRow(
          icon: Icons.bloodtype_outlined,
          label: 'Blood Group',
          value: profile.bloodGroup,
        ),
        _buildInfoRow(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: profile.phone,
        ),
        _buildInfoRow(
          icon: Icons.location_on_outlined,
          label: 'Village',
          value: profile.village,
        ),
        _buildInfoRow(
          icon: Icons.badge_outlined,
          label: 'ABHA ID',
          value: profile.abhaId,
          showDivider: false,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // EMERGENCY CONTACT CARD
  // ---------------------------------------------------------------------------
  Widget _buildEmergencyContactCard(
    BuildContext context,
    UserProfile profile,
  ) {
    return _buildSectionCard(
      title: 'Emergency Contact',
      children: [
        _buildInfoRow(
          icon: Icons.groups_outlined,
          label: 'Name',
          value: profile.emergencyContactName,
        ),
        _buildInfoRow(
          icon: Icons.phone_in_talk_outlined,
          label: 'Phone',
          value: profile.emergencyContactPhone,
          valueColor: AppColors.primary,
          showDivider: false,
          onTap: () => _makeCall(context, profile.emergencyContactPhone),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // HEALTH SUMMARY CARD
  // ---------------------------------------------------------------------------
  Widget _buildHealthSummaryCard(UserProfile profile) {
    return _buildSectionCard(
      title: 'Health Summary',
      children: [
        _buildInfoRow(
          icon: Icons.warning_amber_rounded,
          label: 'Allergies',
          value: profile.allergies,
        ),
        _buildInfoRow(
          icon: Icons.monitor_heart_outlined,
          label: 'Chronic Conditions',
          value: profile.chronicConditions,
        ),
        _buildInfoRow(
          icon: Icons.event_outlined,
          label: 'Last Visit',
          value: profile.lastVisit,
          showDivider: false,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED BUILDERS
  // ---------------------------------------------------------------------------
  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
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
          Row(
            children: [
              const Icon(
                Icons.badge_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool showDivider = true,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.call_rounded,
              size: 18,
              color: AppColors.primary,
            ),
        ],
      ),
    );

    final divider = showDivider
        ? const Padding(
            padding: EdgeInsets.only(left: 27),
            child: Divider(color: AppColors.divider, height: 1),
          )
        : const SizedBox.shrink();

    if (onTap == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [row, divider],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: row,
        ),
        divider,
      ],
    );
  }

  Future<void> _makeCall(BuildContext context, String phoneNumber) async {
    try {
      final uri = Uri.parse('tel:$phoneNumber');
      final launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calling not supported on this device.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calling not supported on this device.'),
          ),
        );
      }
    }
  }
}
