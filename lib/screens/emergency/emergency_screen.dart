import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

/// Public read-only screen listing emergency helplines and nearby facilities.
/// Tapping a row opens the platform dialler. No bottom navigation bar.
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===================== CURVED BLUE HEADER =====================
            _buildHeader(context),

            const SizedBox(height: 20),

            // ===================== EMERGENCY HELPLINES CARD =====================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildSectionCard(
                title: 'Emergency Helplines',
                children: [
                  _buildContactRow(
                    context,
                    icon: Icons.local_hospital_outlined,
                    name: 'Ambulance',
                    number: '108',
                    dialNumber: '108',
                  ),
                  _buildContactRow(
                    context,
                    icon: Icons.support_agent_outlined,
                    name: 'Health Helpline',
                    number: '104',
                    dialNumber: '104',
                  ),
                  _buildContactRow(
                    context,
                    icon: Icons.local_police_outlined,
                    name: 'Police',
                    number: '100',
                    dialNumber: '100',
                    showDivider: false,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ===================== NEARBY FACILITIES CARD =====================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildSectionCard(
                title: 'Nearby Facilities',
                children: [
                  _buildContactRow(
                    context,
                    icon: Icons.local_hospital_outlined,
                    name: 'PHC Palghar',
                    number: '+91 8693062871',
                    dialNumber: '+918693062871',
                  ),
                  _buildContactRow(
                    context,
                    icon: Icons.apartment_outlined,
                    name: 'District Hospital',
                    number: '+91 7666283402',
                    dialNumber: '+917666283402',
                    showDivider: false,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ===================== EMERGENCY NOTICE CARD =====================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildNoticeCard(),
            ),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),

            // Top row: back arrow
            Row(
              children: [
                GestureDetector(
                  onTap: () {
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
              ],
            ),

            const SizedBox(height: 24),

            // Center-aligned title
            Text(
              'Emergency Contacts',
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
              'Tap to call',
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
  // SECTION CARD
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
                Icons.emergency_outlined,
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

  // ---------------------------------------------------------------------------
  // CONTACT ROW
  // ---------------------------------------------------------------------------
  Widget _buildContactRow(
    BuildContext context, {
    required IconData icon,
    required String name,
    required String number,
    required String dialNumber,
    bool showDivider = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _makeCall(context, dialNumber),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 19, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        number,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.call_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 52),
            child: Divider(color: AppColors.divider, height: 1),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // NOTICE CARD
  // ---------------------------------------------------------------------------
  Widget _buildNoticeCard() {
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: AppColors.urgencyHigh,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'For life-threatening emergencies, call 108 immediately.',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.urgencyHigh,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
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
