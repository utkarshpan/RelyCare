import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';

/// Screen displaying logged-in facility / staff profile and app configurations.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final role = authProvider.currentRole;

    final String title;
    final String name;
    final String designation;
    final List<Widget> details;

    switch (role) {
      case UserRole.hospitalStaff:
        title = 'Hospital Staff Profile';
        name = 'Dr. Rajesh Varma';
        designation = 'Chief Medical Officer • District Hospital';
        details = [
          const ListTile(
            leading: Icon(Icons.local_hospital, color: AppColors.primary),
            title: Text('Facility / Hospital'),
            subtitle: Text('District Hospital (DH-201)'),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.location_on, color: AppColors.primary),
            title: Text('District / Zone'),
            subtitle: Text('Central District, Metro Zone'),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.phone_android, color: AppColors.primary),
            title: Text('Referral Desk Helpline'),
            subtitle: Text('+91 9876501234'),
          ),
        ];
        break;
      case UserRole.patient:
        title = 'Patient Profile';
        name = 'Ramesh Kumar';
        designation = 'Registered Patient';
        details = [
          ListTile(
            leading: const Icon(Icons.phone_android, color: AppColors.primary),
            title: const Text('Registered Email / Phone'),
            subtitle: Text(
              authProvider.emailOrPhone.isNotEmpty
                  ? authProvider.emailOrPhone
                  : '+91 9876543210',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.location_on, color: AppColors.primary),
            title: const Text('Registered Location'),
            subtitle: const Text('Village Rampur, Block B'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.local_hospital, color: AppColors.primary),
            title: const Text('Primary Health Center'),
            subtitle: const Text('Rampur PHC (PHC-104)'),
          ),
        ];
        break;
      case UserRole.phcStaff:
        title = 'Facility & Staff Profile';
        name = 'Dr. Ananya Sharma';
        designation = 'Medical Officer • Rampur PHC';
        details = [
          const ListTile(
            leading: Icon(Icons.apartment, color: AppColors.primary),
            title: Text('Facility Code'),
            subtitle: Text('PHC-104'),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.location_on, color: AppColors.primary),
            title: Text('District / Zone'),
            subtitle: Text('East District, Block B'),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.phone_android, color: AppColors.primary),
            title: Text('SMS Fallback Number'),
            subtitle: Text('+91 9876543210'),
          ),
        ];
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              if (role == UserRole.hospitalStaff) {
                context.go('/hospital-dashboard');
              } else if (role == UserRole.patient) {
                context.go('/user-tracking');
              } else {
                context.go('/phc-dashboard');
              }
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.person, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(name, style: AppTextStyles.heading2),
            Text(designation, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 24),

            Card(
              child: Column(
                children: details,
              ),
            ),
            const SizedBox(height: 24),

            ListTile(
              tileColor: Colors.red.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                role == UserRole.patient ? 'Log Out' : 'Switch Facility / Log Out',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              onTap: () async {
                await context.read<AuthProvider>().logout();
                if (context.mounted) {
                  context.go('/login');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
