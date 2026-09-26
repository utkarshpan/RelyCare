import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/referral_provider.dart';
import '../../models/referral.dart';
import '../../models/patient.dart';
import '../../models/referral_status.dart';

class CreateReferralStep2Screen extends StatefulWidget {
  final Map<String, dynamic> patientData;

  const CreateReferralStep2Screen({
    super.key,
    required this.patientData,
  });

  @override
  State<CreateReferralStep2Screen> createState() => _CreateReferralStep2ScreenState();
}

class _CreateReferralStep2ScreenState extends State<CreateReferralStep2Screen> {
  final _formKey = GlobalKey<FormState>();

  final _reasonController = TextEditingController();
  final _clinicalNotesController = TextEditingController();

  String? _selectedDestination;
  final List<String> _destinationOptions = ['District Hospital', 'City General', 'Specialty Clinic'];

  String? _selectedUrgency;
  final List<String> _urgencyOptions = ['Normal', 'Urgent', 'Emergency'];

  int _currentNavIndex = 0;

  @override
  void dispose() {
    _reasonController.dispose();
    _clinicalNotesController.dispose();
    super.dispose();
  }

  void _handleNext() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final referralProvider = Provider.of<ReferralProvider>(context, listen: false);

    final currentUser = authProvider.currentUser;
    final userFacility = (currentUser != null && currentUser.facilityId.isNotEmpty)
        ? currentUser.facilityId
        : 'PHC-TEST';

    final destinationFacility = (_selectedDestination == null ||
            _selectedDestination == 'District Hospital' ||
            _selectedDestination == 'UNKNOWN')
        ? 'DH-TEST'
        : _selectedDestination!;

    // Create Patient and Referral model instances
    final patient = Patient(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fullName: widget.patientData['name'],
      age: int.tryParse(widget.patientData['age'].toString()) ?? 0,
      gender: widget.patientData['gender'],
      contactNumber: widget.patientData['phone'],
      villageOrLocation: widget.patientData['location'],
      createdAt: DateTime.now(),
    );

    final urgency = _selectedUrgency == 'Emergency' 
        ? ReferralUrgency.emergency 
        : (_selectedUrgency == 'Urgent' ? ReferralUrgency.urgent : ReferralUrgency.routine);

    final referral = Referral(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      referralToken: 'RC-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      patientId: patient.id,
      patient: patient,
      sourceFacilityId: userFacility,
      destinationFacilityId: destinationFacility,
      referralReason: _reasonController.text.trim(),
      clinicalNotesSummary: _clinicalNotesController.text.trim(),
      urgency: urgency,
      status: ReferralStatus.created,
      syncState: SyncState.pendingSync,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Save referral locally
    final createdReferral = await referralProvider.createReferral(
      patientName: patient.fullName,
      patientAge: patient.age,
      patientGender: patient.gender,
      patientPhone: patient.contactNumber,
      patientLocation: patient.villageOrLocation,
      sourceFacility: referral.sourceFacilityId,
      destinationFacility: referral.destinationFacilityId,
      reason: referral.referralReason,
      clinicalNotes: referral.clinicalNotesSummary,
      urgency: urgency,
    );

    if (createdReferral != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Referral saved locally. It will sync when online.'),
          duration: Duration(seconds: 3),
        ),
      );
      context.go('/phc-dashboard');
    }
  }

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
            // ================= TOP CURVED HEADER =================
            _buildHeader(size),

            // ================= OVERLAPPING WHITE FORM CARD =================
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 22.0,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Step Indicator Dots
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE2E8F0),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 36,
                              height: 5,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE2E8F0),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 1. Reason for Referral *
                      _buildFieldLabel('Reason for Referral', isRequired: true),
                      const SizedBox(height: 8),
                      _buildInputField(
                        controller: _reasonController,
                        hintText: 'e.g. Severe Anemia',
                        prefixIcon: Icons.medical_information_outlined,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Reason for referral is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      
                      // 2. Clinical Notes
                      _buildFieldLabel('Clinical Notes', isRequired: false),
                      const SizedBox(height: 8),
                      _buildInputField(
                        controller: _clinicalNotesController,
                        hintText: 'Any extra details...',
                        prefixIcon: Icons.note_alt_outlined,
                      ),
                      const SizedBox(height: 18),
                      
                      // 3. Destination Hospital
                      _buildFieldLabel('Destination Hospital', isRequired: true),
                      const SizedBox(height: 8),
                      _buildDropdownField(
                        value: _selectedDestination,
                        options: _destinationOptions,
                        hintText: 'Select Hospital',
                        icon: Icons.local_hospital_outlined,
                        onChanged: (val) {
                          setState(() {
                            _selectedDestination = val;
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      
                      // 4. Urgency
                      _buildFieldLabel('Urgency', isRequired: true),
                      const SizedBox(height: 8),
                      _buildDropdownField(
                        value: _selectedUrgency,
                        options: _urgencyOptions,
                        hintText: 'Select Urgency',
                        icon: Icons.warning_amber_rounded,
                        onChanged: (val) {
                          setState(() {
                            _selectedUrgency = val;
                          });
                        },
                      ),
                      
                      const SizedBox(height: 32),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _handleNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Next',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  /// Header widget with Back button
  Widget _buildHeader(Size size) {
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
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/create-referral');
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
                const SizedBox(width: 16),
                Text(
                  'Create Referral',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Step 2 of 3: Referral Details',
              style: GoogleFonts.inter(
                fontSize: 14,
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

  /// Field Label with optional Red Asterisk
  Widget _buildFieldLabel(String label, {required bool isRequired}) {
    return RichText(
      text: TextSpan(
        text: label,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1E293B),
        ),
        children: [
          if (isRequired)
            const TextSpan(
              text: ' *',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  /// Standard Styled Form Input Field
  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextFormField(
        controller: controller,
        validator: validator,
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: const Color(0xFF1E293B),
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF94A3B8),
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: const Color(0xFF94A3B8),
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
    );
  }

  /// Dropdown Field Component
  Widget _buildDropdownField({
    required String? value,
    required List<String> options,
    required String hintText,
    required IconData icon,
    required void Function(String?) onChanged,
  }) {
    return FormField<String>(
      initialValue: value,
      validator: (val) {
        final current = val ?? value;
        if (current == null || current.isEmpty) {
          return 'This field is required';
        }
        return null;
      },
      builder: (FormFieldState<String> state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.inputBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: const Color(0xFF94A3B8),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: state.value ?? value,
                        hint: Text(
                          hintText,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        isExpanded: true,
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1E293B),
                        ),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        items: options.map((String opt) {
                          return DropdownMenuItem<String>(
                            value: opt,
                            child: Text(opt),
                          );
                        }).toList(),
                        onChanged: (val) {
                          onChanged(val);
                          state.didChange(val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12.0, top: 4.0),
                child: Text(
                  state.errorText!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFDC2626),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Custom Bottom Navigation Bar
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.home_rounded,
                label: 'Home',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.assignment_outlined,
                label: 'Referrals',
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.sync_rounded,
                label: 'Sync',
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.person_outline_rounded,
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentNavIndex == index;
    final activeColor = AppColors.primary;
    final inactiveColor = const Color(0xFF64748B);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _currentNavIndex = index;
        });
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
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
