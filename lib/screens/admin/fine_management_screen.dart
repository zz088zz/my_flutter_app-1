import 'package:flutter/material.dart';
import '../../services/fine_service.dart';
import '../../models/charging_session.dart';

class FineManagementScreen extends StatefulWidget {
  const FineManagementScreen({Key? key}) : super(key: key);

  @override
  State<FineManagementScreen> createState() => _FineManagementScreenState();
}

class _FineManagementScreenState extends State<FineManagementScreen> {
  final FineService _fineService = FineService();
  Map<String, dynamic>? _fineStatistics;
  List<ChargingSession> _recentFinedSessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFineData();
  }

  Future<void> _loadFineData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final statistics = await _fineService.getFineStatistics();

      setState(() {
        _fineStatistics = statistics;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading fine data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fine Management'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFineData),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('About Fine Statistics'),
                  content: const Text(
                    'The "Sessions with Fines" count shows all charging sessions that incurred a fine. '
                    'This number may differ from the number of fine transactions shown in the Transactions screen, '
                    'as some sessions may not have generated a transaction record yet.'
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'About Fine Statistics',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadFineData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatisticsCard(),
                      const SizedBox(height: 20),
                      _buildFineSettingsCard(),
                      const SizedBox(height: 20),
                      _buildRecentFinesCard(),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildStatisticsCard() {
    if (_fineStatistics == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No fine statistics available'),
        ),
      );
    }

    final totalFines = _fineStatistics!['total_fines'] ?? 0.0;
    final totalSessions = _fineStatistics!['total_sessions_with_fines'] ?? 0;
    final averageFine = _fineStatistics!['average_fine'] ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Fine Statistics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Total Fines',
                    'RM ${totalFines.toStringAsFixed(2)}',
                    Colors.red,
                    Icons.money_off,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Sessions with Fines',
                    totalSessions.toString(),
                    Colors.orange,
                    Icons.warning,
                    tooltip: 'Total charging sessions with fines (may differ from transaction count)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Average Fine',
                    'RM ${averageFine.toStringAsFixed(2)}',
                    Colors.blue,
                    Icons.calculate,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Fine Rate',
                    'RM 1.00/min',
                    Colors.green,
                    Icons.schedule,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color,
    IconData icon,
    {String? tooltip}
  ) {
    Widget statItem = Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
    
    // If tooltip is provided, wrap the statItem with a Tooltip widget
    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        child: statItem,
      );
    }
    
    return statItem;
  }

  Widget _buildFineSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Fine Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSettingRow('Grace Period', '3 minutes'),
            const SizedBox(height: 8),
            _buildSettingRow('Fine Rate', 'RM 1.00 per minute'),
            const SizedBox(height: 8),
            _buildSettingRow('Status', 'Active'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Users have 3 minutes grace period after charging completion before fines start applying (optimized for 50kW fast chargers).',
                      style: TextStyle(fontSize: 14, color: Colors.blue[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildRecentFinesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Fine System Overview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How the Fine System Works:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoPoint(
                    '1. Charging completes automatically or user stops charging',
                  ),
                  _buildInfoPoint(
                    '2. User has 3 minutes grace period to remove charger',
                  ),
                  _buildInfoPoint(
                    '3. After grace period, RM 1.00/minute fine starts',
                  ),
                  _buildInfoPoint(
                    '4. Fine is added to the final payment amount',
                  ),
                  _buildInfoPoint(
                    '5. User must remove charger to proceed to payment',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green[700],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This encourages users to remove chargers promptly, improving station availability.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }
}