import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../widgets/primary_button.dart';

/// Screen displaying offline queue status, network status, and sync triggers.
class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SyncProvider>().refreshCounts();
    });
  }

  void _triggerSync() async {
    final syncProvider = context.read<SyncProvider>();
    final connectivity = context.read<ConnectivityProvider>();

    final count = await syncProvider.syncPending(resetFailed: true);
    if (mounted) {
      final String message;
      final Color backgroundColor;

      if (syncProvider.syncError != null) {
        message = syncProvider.syncError!;
        backgroundColor = AppColors.urgencyHigh;
      } else if (!connectivity.isOnline) {
        message = 'Device is offline. Items remain safely queued.';
        backgroundColor = AppColors.offlineOrange;
      } else {
        message = 'Sync completed! $count referrals processed.';
        backgroundColor = AppColors.onlineGreen;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final connectivity = context.watch<ConnectivityProvider>();
    final isOnline = connectivity.isOnline;
    final isSyncing = syncProvider.isSyncing;
    final pendingCount = syncProvider.pendingCount;
    final failedCount = syncProvider.failedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync & Connectivity'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              final role = context.read<AuthProvider>().currentRole;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          isOnline ? Icons.wifi : Icons.wifi_off_rounded,
                          size: 32,
                          color: isOnline ? AppColors.onlineGreen : AppColors.offlineOrange,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOnline ? 'Network Online' : 'Operating in Offline Mode',
                                style: AppTextStyles.heading3,
                              ),
                              Text(
                                isOnline
                                    ? 'Connected to FastAPI backend'
                                    : 'Local database active. SMS fallback enabled.',
                                style: AppTextStyles.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Simulate Online / Offline'),
                      subtitle: const Text('Toggle connectivity state'),
                      value: isOnline,
                      onChanged: (v) {
                        connectivity.toggleSimulation();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Pending Queue Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Offline Queue', style: AppTextStyles.heading3),
                    const SizedBox(height: 8),
                    Text(
                      '$pendingCount referrals waiting for upload',
                      style: AppTextStyles.bodyMedium,
                    ),
                    if (failedCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$failedCount failed items pending retry',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.urgencyHigh),
                      ),
                    ],
                    if (syncProvider.lastSyncTime != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last Sync: ${syncProvider.lastSyncTime}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: 'Sync Now',
                      icon: Icons.sync,
                      isLoading: isSyncing,
                      onPressed: _triggerSync,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
