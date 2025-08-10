import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/reward.dart';
import '../models/voucher.dart';
import 'dart:math' as Math;

class RewardService with ChangeNotifier {
  List<Reward> _rewards = [];
  List<Voucher> _vouchers = [];
  double _totalPoints = 0.0;
  bool _isLoading = false;

  static const int POINTS_PER_RINGGIT = 1;
  static const double VOUCHER_COST_POINTS = 100.0;
  static const double VOUCHER_DISCOUNT_AMOUNT = 10.0;
  static const double VOUCHER_DISCOUNT_PERCENTAGE = 10.0;

  List<Reward> get rewards => _rewards;
  List<Voucher> get vouchers => _vouchers;
  double get totalPoints => _totalPoints;
  bool get isLoading => _isLoading;

  Future<void> loadUserRewards(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Check Firebase Auth state first
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('REWARD ERROR: No Firebase Auth user found when loading rewards');
        _rewards = [];
        _vouchers = [];
        _totalPoints = 0;
        _isLoading = false;
        notifyListeners();
        return;
      }

      if (currentUser.uid != userId) {
        print(
          'REWARD ERROR: User ID mismatch when loading - Firebase Auth UID: ${currentUser.uid}, Provided userId: $userId',
        );
        _rewards = [];
        _vouchers = [];
        _totalPoints = 0;
        _isLoading = false;
        notifyListeners();
        return;
      }

      print('REWARD DEBUG: Loading rewards for authenticated user: $userId');

      // Load rewards
      final rewardsQuery =
          await FirebaseFirestore.instance
              .collection('rewards')
              .where('user_id', isEqualTo: userId)
              .orderBy('created_at', descending: true)
              .get();

      print('REWARD DEBUG: Found ${rewardsQuery.docs.length} reward documents');

      _rewards =
          rewardsQuery.docs.map((doc) {
            final map = doc.data();
            map['id'] = doc.id;
            print('REWARD DEBUG: Processing reward doc ${doc.id}: $map');
            return Reward.fromMap(map);
          }).toList();

      // Load vouchers
      final vouchersQuery =
          await FirebaseFirestore.instance
              .collection('vouchers')
              .where('user_id', isEqualTo: userId)
              .orderBy('created_at', descending: true)
              .get();

      _vouchers =
          vouchersQuery.docs.map((doc) {
            final map = doc.data();
            map['id'] = doc.id;
            return Voucher.fromMap(map);
          }).toList();

      // Calculate total points
      _calculateTotalPoints();

      print(
        'Loaded ${_rewards.length} rewards and ${_vouchers.length} vouchers for user $userId',
      );
      print('Total points: $_totalPoints');
    } catch (e) {
      print('Error loading user rewards: $e');
      print('Stack trace: ${StackTrace.current}');
      _rewards = [];
      _vouchers = [];
      _totalPoints = 0;
    }

    _isLoading = false;
    notifyListeners();
  }

  void _calculateTotalPoints() {
    double earnedPoints = 0.0;
    double redeemedPoints = 0.0;

    for (final reward in _rewards) {
      if (reward.isEarned) {
        earnedPoints += reward.points;
      } else if (reward.isRedeemed) {
        redeemedPoints += reward.points;
      }
    }

    _totalPoints = earnedPoints - redeemedPoints;
  }

  Future<bool> awardPoints(
    String userId,
    double chargingFee,
    String description,
  ) async {
    try {
      // Check Firebase Auth state first
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print(
          'REWARD ERROR: No Firebase Auth user found - user not authenticated',
        );
        return false;
      }

      if (currentUser.uid != userId) {
        print(
          'REWARD ERROR: User ID mismatch - Firebase Auth UID: ${currentUser.uid}, Provided userId: $userId',
        );
        return false;
      }

      print(
        'REWARD DEBUG: Firebase Auth user verified - UID: ${currentUser.uid}',
      );

      // Calculate points based on charging fee: 1 point for every 1 ringgit of charging fee
      // Example: charging fee RM 1.30 = 1.30 points
      // Example: charging fee RM 0.22 = 0.22 points
      final pointsEarned = double.parse(chargingFee.toStringAsFixed(2));

      if (pointsEarned <= 0) {
        print(
          'No points earned for charging fee: RM${chargingFee.toStringAsFixed(2)}',
        );
        return true; // Not an error, just no points to award
      }

      final reward = Reward(
        userId: userId,
        points: pointsEarned,
        description: description,
        type: 'earned',
        createdAt: DateTime.now(),
      );

      print(
        'REWARD DEBUG: About to save reward to Firebase: ${reward.toMap()}',
      );

      final docRef = await FirebaseFirestore.instance
          .collection('rewards')
          .add(reward.toMap());

      print(
        'REWARD DEBUG: Successfully saved reward to Firebase with ID: ${docRef.id}',
      );

      // Update local state
      _rewards.insert(0, reward);
      _totalPoints += pointsEarned;
      notifyListeners();

      print(
        'REWARD DEBUG: Awarded $pointsEarned points for RM${chargingFee.toStringAsFixed(2)} charging fee (1 point per RM 1). Total points now: $_totalPoints',
      );
      return true;
    } catch (e) {
      print('Error awarding points: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  Future<bool> redeemVoucher(String userId) async {
    try {
      if (_totalPoints < VOUCHER_COST_POINTS) {
        print(
          'Insufficient points for voucher redemption. Required: $VOUCHER_COST_POINTS, Available: $_totalPoints',
        );
        return false;
      }

      // Generate unique voucher code
      final voucherCode = _generateVoucherCode();

      // Create voucher
      final voucher = Voucher(
        userId: userId,
        code: voucherCode,
        discountAmount: VOUCHER_DISCOUNT_AMOUNT,
        discountPercentage: VOUCHER_DISCOUNT_PERCENTAGE,
        status: 'active',
        createdAt: DateTime.now(),
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );

      // Create redemption reward record
      final redemptionReward = Reward(
        userId: userId,
        points: VOUCHER_COST_POINTS.toDouble(),
        description:
            'Redeemed ${VOUCHER_DISCOUNT_PERCENTAGE.toInt()}% discount voucher ($voucherCode)',
        type: 'redeemed',
        createdAt: DateTime.now(),
      );

      // Use batch to ensure both operations succeed
      final batch = FirebaseFirestore.instance.batch();

      final voucherRef =
          FirebaseFirestore.instance.collection('vouchers').doc();
      batch.set(voucherRef, voucher.toMap());

      final rewardRef = FirebaseFirestore.instance.collection('rewards').doc();
      batch.set(rewardRef, redemptionReward.toMap());

      await batch.commit();

      // Update local state
      _vouchers.insert(0, voucher);
      _rewards.insert(0, redemptionReward);
      _totalPoints -= VOUCHER_COST_POINTS;
      notifyListeners();

      print('Successfully redeemed voucher: $voucherCode');
      return true;
    } catch (e) {
      print('Error redeeming voucher: $e');
      return false;
    }
  }

  String _generateVoucherCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Math.Random();
    return 'EV${List.generate(6, (index) => chars[random.nextInt(chars.length)]).join()}';
  }

  Future<Voucher?> getVoucherByCode(String code) async {
    try {
      final query =
          await FirebaseFirestore.instance
              .collection('vouchers')
              .where('code', isEqualTo: code)
              .where('status', isEqualTo: 'active')
              .limit(1)
              .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final map = doc.data();
        map['id'] = doc.id;
        return Voucher.fromMap(map);
      }
      return null;
    } catch (e) {
      print('Error getting voucher by code: $e');
      return null;
    }
  }

  Future<bool> useVoucher(String voucherId) async {
    try {
      await FirebaseFirestore.instance
          .collection('vouchers')
          .doc(voucherId)
          .update({
            'status': 'used',
            'used_at': DateTime.now().toIso8601String(),
          });

      // Update local state
      final voucherIndex = _vouchers.indexWhere((v) => v.id == voucherId);
      if (voucherIndex != -1) {
        final updatedVoucher = Voucher(
          id: _vouchers[voucherIndex].id,
          userId: _vouchers[voucherIndex].userId,
          code: _vouchers[voucherIndex].code,
          discountAmount: _vouchers[voucherIndex].discountAmount,
          status: 'used',
          createdAt: _vouchers[voucherIndex].createdAt,
          usedAt: DateTime.now(),
          expiryDate: _vouchers[voucherIndex].expiryDate,
        );
        _vouchers[voucherIndex] = updatedVoucher;
        notifyListeners();
      }

      print('Voucher $voucherId marked as used');
      return true;
    } catch (e) {
      print('Error using voucher: $e');
      return false;
    }
  }

  Future<bool> markVoucherAsUsed(String voucherId) async {
    try {
      await FirebaseFirestore.instance
          .collection('vouchers')
          .doc(voucherId)
          .update({'status': 'used', 'used_at': Timestamp.now()});

      // Update local state
      final voucherIndex = _vouchers.indexWhere((v) => v.id == voucherId);
      if (voucherIndex != -1) {
        _vouchers[voucherIndex] = _vouchers[voucherIndex].copyWith(
          status: 'used',
          usedAt: DateTime.now(),
        );
        notifyListeners();
      }

      print('Voucher $voucherId marked as used');
      return true;
    } catch (e) {
      print('Error marking voucher as used: $e');
      return false;
    }
  }

  List<Voucher> getActiveVouchers() {
    return _vouchers.where((voucher) => voucher.isActive).toList();
  }

  List<Voucher> getUsedVouchers() {
    return _vouchers.where((voucher) => voucher.isUsed).toList();
  }

  Future<void> refreshRewards(String userId) async {
    await loadUserRewards(userId);
  }

  /// Initialize the rewards collection in Firestore by creating a sample document
  /// This ensures the collection exists in Firebase Console
  Future<void> initializeRewardsCollection() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('REWARD INIT: No authenticated user found');
        return;
      }

      print('REWARD INIT: Initializing rewards collection...');

      // Check if rewards collection already has documents
      final rewardsSnapshot =
          await FirebaseFirestore.instance.collection('rewards').limit(1).get();

      if (rewardsSnapshot.docs.isEmpty) {
        // Create a sample reward document to initialize the collection
        await FirebaseFirestore.instance.collection('rewards').add({
          'user_id': currentUser.uid,
          'points': 5.0,
          'description': 'Welcome bonus - Collection initialization',
          'type': 'earned',
          'created_at': FieldValue.serverTimestamp(),
        });
        print('REWARD INIT: ✅ Rewards collection created with sample document');
      } else {
        print('REWARD INIT: Rewards collection already exists');
      }

      // Check if vouchers collection already has documents
      final vouchersSnapshot =
          await FirebaseFirestore.instance
              .collection('vouchers')
              .limit(1)
              .get();

      if (vouchersSnapshot.docs.isEmpty) {
        // Create a sample voucher document to initialize the collection
        await FirebaseFirestore.instance.collection('vouchers').add({
          'user_id': currentUser.uid,
          'code': 'WELCOME10',
          'discount_amount': 10.0,
          'discount_percentage': 10.0,
          'status': 'active',
          'created_at': FieldValue.serverTimestamp(),
          'expiry_date': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30)),
          ),
        });
        print(
          'REWARD INIT: ✅ Vouchers collection created with sample document',
        );
      } else {
        print('REWARD INIT: Vouchers collection already exists');
      }

      print('REWARD INIT: 🎉 Collections initialization completed!');
    } catch (error) {
      print('REWARD INIT ERROR: Failed to initialize collections - $error');
    }
  }
}
