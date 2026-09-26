import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/referral_guardian_status.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/bottom_nav_bar.dart';

/// High-Fidelity PHC Dashboard Screen for RelyCare.
/// Matches the exact design specifications: Curved Blue Header,
/// Pill Online Badge, 3 Stats Cards, "+ Create Referral" Action Button,
/// Left-Accented Referral Cards, and Reusable Bottom Navigation Bar.
class PHCDashboardScreen extends StatefulWidget {
  const PHCDashboardScreen({super.key});

  @override
  State<PHCDashboardScreen> createState() => _PHCDashboardScreenState();
}

class _PHCDashboardScreenState extends State<PHCDashboardScreen> {
  final int _currentNavIndex = 0;
  bool _isOnline = true;

  final List<BottomNavItem> _navItems = const [
    BottomNavItem(icon: Icons.home_rounded, label: 'Home'),
    BottomNavItem(icon: Icons.folder_outlined, label: 'Referrals'),
    BottomNavItem(icon: Icons.sync_rounded, label: 'Sync', badgeCount: 4),
    BottomNavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ================= TOP CURVED HEADER + BADGE =================
            _buildHeader(size),

            const SizedBox(height: 28),

            // ================= 3 STATS CARDS ROW =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.description_outlined,
                      iconColor: const Color(0xFF0284C7),
                      iconBgColor: const Color(0xFFE0F2FE),
                      value: '12',
                      label: 'Total...',
                      valueColor: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.sync_rounded,
                      iconColor: const Color(0xFF2563EB),
                      iconBgColor: const Color(0xFFEFF6FF),
                      value: '4',
                      label: 'Pending Sync',
                      valueColor: const Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.check_circle_outline_rounded,
                      iconColor: const Color(0xFF16A34A),
                      iconBgColor: const Color(0xFFF0FDF4),
                      value: '7',
                      label: 'Completed',
                      valueColor: const Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ================= CREATE REFERRAL BUTTON =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    context.push('/create-referral');
                  },
                  icon: const Icon(Icons.add_rounded, size: 22, color: Colors.white),
                  label: Text(
                    'Create Referral',
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

            // ================= RECENT REFERRALS SECTION HEADER =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Referrals',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      context.push('/referrals');
                    },
                    child: Text(
                      'View all',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0284C7),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ================= RECENT REFERRALS LIST =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildReferralCard(
                    name: 'Rahul Sharma',
                    facility: 'District Hospital',
                    time: 'Today, 10:30 AM',
                    status: 'SENT',
                    statusBgColor: const Color(0xFFEEF2FF),
                    statusTextColor: const Color(0xFF4F46E5),
                    accentBorderColor: const Color(0xFF3B82F6),
                  ),
                  const SizedBox(height: 12),
                  _buildReferralCard(
                    name: 'Sunita Devi',
                    facility: 'Civil Hospital',
                    time: 'Yesterday, 4:15 PM',
                    status: 'PENDING',
                    statusBgColor: const Color(0xFFF1F5F9),
                    statusTextColor: const Color(0xFF475569),
                    accentBorderColor: null,
                  ),
                  const SizedBox(height: 12),
                  _buildReferralCard(
                    name: 'Amit Patel',
                    facility: 'General Hospital',
                    time: '24 Oct, 11:00 AM',
                    status: 'COMPLETED',
                    statusBgColor: const Color(0xFFF0FDF4),
                    statusTextColor: const Color(0xFF16A34A),
                    accentBorderColor: const Color(0xFF16A34A),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentNavIndex,
        items: _navItems,
        activeColor: AppColors.primary,
        inactiveColor: const Color(0xFF64748B),
        onTap: (index) {
          if (index == _currentNavIndex) return;
          switch (index) {
            case 0:
              context.go('/phc-dashboard');
              break;
            case 1:
              context.go('/referrals');
              break;
            case 2:
              context.go('/sync-status');
              break;
            case 3:
              context.go('/profile');
              break;
          }
        },
      ),
    );
  }

  /// Curved Blue Header with Brand, Notification Bell, Doctor Greeting, Logout, and Floating Status Pill
  Widget _buildHeader(Size size) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // Blue Header Container
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(36),
              bottomRight: Radius.circular(36),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),

                // Top Row: RelyCare Logo & Name + Notification Icon & Logout
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const _HeaderHeartbeatIcon(),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'RelyCare',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),

                    Row(
                      children: [
                        // Notification Bell with Red Dot
                        Stack(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.notifications_none_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('No new notifications.'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
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
                        const SizedBox(width: 14),

                        // Logout Button
                        IconButton(
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Logout',
                          onPressed: () {
                            context.read<AuthProvider>().logout();
                            context.go('/login');
                          },
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Greeting: Good Morning, Dr. Sharma
                Text(
                  'Good Morning, Dr. Sharma',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),

                // Location: PHC Mumbai
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'PHC Mumbai',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // Overlapping Pill Connectivity Badge
        Positioned(
          bottom: -16,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _isOnline = !_isOnline;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isOnline ? 'Switched to Online mode.' : 'Switched to Offline mode.'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isOnline ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _isOnline ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _isOnline ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Individual Stat Card Widget
  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String value,
    required String label,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: valueColor,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Individual Referral Card with optional left accent border strip
  Widget _buildReferralCard({
    required String name,
    required String facility,
    required String time,
    required String status,
    required Color statusBgColor,
    required Color statusTextColor,
    Color? accentBorderColor,
    ReferralGuardianStatus? guardianStatus,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Optional Left Colored Accent Strip
              if (accentBorderColor != null)
                Container(
                  width: 5,
                  color: accentBorderColor,
                ),

              // Content Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top Row: Patient Name + Status Badges
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (guardianStatus != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: guardianStatus.backgroundColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: guardianStatus.color.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(guardianStatus.icon, size: 12, color: guardianStatus.color),
                                      const SizedBox(width: 4),
                                      Text(
                                        guardianStatus.displayName,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: guardianStatus.color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusBgColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusTextColor,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Facility Destination + Time
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            facility,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF334155),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0),
                            child: Text(
                              '•',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                          Text(
                            time,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF64748B),
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
}

/// Header Heartbeat Wave custom painter for top-left app icon
class _HeaderHeartbeatIcon extends StatelessWidget {
  const _HeaderHeartbeatIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 14),
      painter: _HeaderHeartbeatPainter(),
    );
  }
}

class _HeaderHeartbeatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(0, h * 0.5);
    path.lineTo(w * 0.28, h * 0.5);
    path.lineTo(w * 0.42, h * 0.1);
    path.lineTo(w * 0.58, h * 0.9);
    path.lineTo(w * 0.72, h * 0.35);
    path.lineTo(w * 0.82, h * 0.5);
    path.lineTo(w, h * 0.5);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
