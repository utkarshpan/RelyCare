import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/referral_card.dart';
import '../../app/app_dependencies.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Screen displaying the list of all local and synchronized referrals.
class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.referralProvider;
        if (provider.referrals.isEmpty && !provider.isLoading) {
          provider.loadReferrals();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.referralProvider;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Referrals'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/phc-dashboard');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload from Local Storage',
            onPressed: () => provider.loadReferrals(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: provider,
        builder: (context, _) {
          if (provider.isLoading && provider.referrals.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null && provider.referrals.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.urgencyHigh, size: 48),
                    const SizedBox(height: 12),
                    Text(provider.errorMessage!, style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.loadReferrals(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final referrals = provider.referrals;

          if (referrals.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text('No Referrals Found', style: AppTextStyles.heading2),
                    const SizedBox(height: 8),
                    Text(
                      'No local referrals saved yet. Tap the button below to create your first offline referral.',
                      style: AppTextStyles.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Create New Referral'),
                      onPressed: () async {
                        await context.push('/create-referral');
                        if (context.mounted) {
                          context.referralProvider.loadReferrals();
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadReferrals(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: referrals.length,
              itemBuilder: (context, index) {
                final referral = referrals[index];
                return ReferralCard(
                  referral: referral,
                  onTap: () {
                    provider.selectReferral(referral);
                    context.push('/referral-details', extra: referral);
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Referral'),
        onPressed: () async {
          await context.push('/create-referral');
          if (context.mounted) {
            context.referralProvider.loadReferrals();
          }
        },
      ),
    );
  }
}
