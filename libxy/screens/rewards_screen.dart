import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/reward_service.dart';
import '../models/reward.dart';
import '../models/voucher.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  bool _isLoading = true;
  List<Reward> _rewards = [];
  List<Voucher> _vouchers = [];
  double _totalPoints = 0.0;

  @override
  void initState() {
    super.initState();
    _loadRewardsData();
  }

  Future<void> _loadRewardsData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final rewardService = Provider.of<RewardService>(context, listen: false);

      print('REWARDS SCREEN DEBUG: Loading rewards data');
      print('REWARDS SCREEN DEBUG: Current user: ${authService.currentUser}');
      print('REWARDS SCREEN DEBUG: User ID: ${authService.currentUser?.id}');
      print('REWARDS SCREEN DEBUG: Is logged in: ${authService.isLoggedIn}');

      if (authService.currentUser != null) {
        print(
          'REWARDS SCREEN DEBUG: Calling loadUserRewards with user ID: ${authService.currentUser!.id!}',
        );
        await rewardService.loadUserRewards(authService.currentUser!.id!);
        setState(() {
          _rewards = rewardService.rewards;
          _vouchers = rewardService.vouchers;
          _totalPoints = rewardService.totalPoints;
          _isLoading = false;
        });
        print(
          'REWARDS SCREEN DEBUG: Loaded ${_rewards.length} rewards, ${_vouchers.length} vouchers, ${_totalPoints} total points',
        );
      } else {
        print('REWARDS SCREEN DEBUG: No current user found!');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading rewards data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _redeemVoucher() async {
    if (_totalPoints < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need at least 100 points to redeem a voucher'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final rewardService = Provider.of<RewardService>(context, listen: false);

      if (authService.currentUser != null) {
        await rewardService.redeemVoucher(authService.currentUser!.id!);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voucher redeemed successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Reload data to reflect changes
        _loadRewardsData();
      }
    } catch (e) {
      print('Error redeeming voucher: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error redeeming voucher: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rewards'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadRewardsData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Points Summary Card
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.stars,
                                    color: Colors.amber,
                                    size: 32,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${_totalPoints.toStringAsFixed(2)} Points',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Earn 1 point for every RM1 spent on charging',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Redeem Section
                      const Text(
                        'Redeem Rewards',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Voucher Redemption Card
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.local_offer,
                                  color: Colors.green,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'RM10 Discount Voucher',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      '100 points required',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed:
                                    _totalPoints >= 100 ? _redeemVoucher : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Redeem'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // My Vouchers Section
                      const Text(
                        'My Vouchers',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_vouchers.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Center(
                              child: Text(
                                'No vouchers available',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        ..._vouchers.map(
                          (voucher) => Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color:
                                          voucher.isActive
                                              ? Colors.green.shade100
                                              : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.confirmation_number,
                                      color:
                                          voucher.isActive
                                              ? Colors.green
                                              : Colors.grey,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'RM${voucher.discountAmount.toStringAsFixed(0)} Discount',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Code: ${voucher.code}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          voucher.isActive
                                              ? 'Expires: ${voucher.expiryDate.day}/${voucher.expiryDate.month}/${voucher.expiryDate.year}'
                                              : 'Status: ${voucher.status.toUpperCase()}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                voucher.isActive
                                                    ? Colors.grey.shade600
                                                    : Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (voucher.isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Points History Section
                      const Text(
                        'Points History',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_rewards.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Center(
                              child: Text(
                                'No points history available',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        ..._rewards.map(
                          (reward) => Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                reward.type == 'earned'
                                    ? Icons.add_circle
                                    : Icons.remove_circle,
                                color:
                                    reward.type == 'earned'
                                        ? Colors.green
                                        : Colors.red,
                              ),
                              title: Text(
                                '${reward.type == 'earned' ? '+' : '-'}${reward.points} points',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      reward.type == 'earned'
                                          ? Colors.green
                                          : Colors.red,
                                ),
                              ),
                              subtitle: Text(reward.description),
                              trailing: Text(
                                '${reward.createdAt.day}/${reward.createdAt.month}/${reward.createdAt.year}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
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
