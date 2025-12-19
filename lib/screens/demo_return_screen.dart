import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../services/demo_service.dart';
import 'demo_detail_screen.dart';
import 'demo_history_screen.dart';

class DemoReturnScreen extends StatefulWidget {
  const DemoReturnScreen({super.key});

  @override
  State<DemoReturnScreen> createState() => _DemoReturnScreenState();
}

class _DemoReturnScreenState extends State<DemoReturnScreen> {
  List<Map<String, dynamic>> _activeDemos = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadActiveDemos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveDemos() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final demoService = DemoService(authService: authProvider.authService);

      // Get active demos only
      final demos = await demoService.getDemoHistory(
        status: 'Active',
        limit: 100,
      );

      if (mounted) {
        setState(() {
          _activeDemos = demos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading demos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredDemos {
    if (_searchQuery.isEmpty) {
      return _activeDemos;
    }
    return _activeDemos.where((demo) {
      final demoNumber = (demo['demo_number'] ?? '').toString().toLowerCase();
      final demoPurpose = (demo['demo_purpose'] ?? '').toString().toLowerCase();
      final dealer = (demo['customer_dealer'] ?? '').toString().toLowerCase();
      final client = (demo['customer_client'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      return demoNumber.contains(query) ||
          demoPurpose.contains(query) ||
          dealer.contains(query) ||
          client.contains(query);
    }).toList();
  }

  Future<void> _navigateToDetailScreen(Map<String, dynamic> demo) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => DemoDetailScreen(demo: demo)),
    );

    // If demo was successfully returned, refresh the list
    if (result == true) {
      _loadActiveDemos();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo Return'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DemoHistoryScreen(),
                ),
              );
            },
            tooltip: 'History',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadActiveDemos,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[50],
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText:
                    'Search demos by number, purpose, dealer, or client...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildDemosList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDemosList() {
    final filteredDemos = _filteredDemos;

    if (filteredDemos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isNotEmpty
                  ? Icons.search_off
                  : Icons.assignment_return,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No demos found matching "$_searchQuery"'
                  : 'No active demos available for return',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Active demos will appear here when available',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadActiveDemos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredDemos.length,
        itemBuilder: (context, index) {
          return _buildDemoCard(filteredDemos[index]);
        },
      ),
    );
  }

  Widget _buildDemoCard(Map<String, dynamic> demo) {
    final demoNumber = demo['demo_number'] ?? 'Unknown';
    final demoPurpose = demo['demo_purpose'] ?? 'No purpose';
    final dealer = demo['customer_dealer'] ?? 'Unknown';
    final client = demo['customer_client'] ?? 'N/A';
    final location = demo['location'] ?? 'Unknown';

    // Use items_remaining_count if available (for partial returns), otherwise use total_items
    final itemsRemaining = demo['items_remaining_count'];
    final totalItems = demo['total_items'] ?? 0;
    final itemCount = itemsRemaining ?? totalItems;
    final isPartiallyReturned = demo['partially_returned'] == true;

    final createdDate = demo['created_date'];
    final expectedReturnDate = demo['expected_return_date'];
    final remarks = demo['remarks'] ?? '';

    // Format dates
    String createdDateStr = 'Unknown';
    String expectedReturnStr = 'Not set';

    if (createdDate != null) {
      try {
        final date = createdDate.toDate();
        createdDateStr = DateFormat('dd/MM/yyyy').format(date);
      } catch (e) {
        createdDateStr = 'Invalid date';
      }
    }

    if (expectedReturnDate != null) {
      try {
        final date = expectedReturnDate.toDate();
        expectedReturnStr = DateFormat('dd/MM/yyyy').format(date);

        // Check if overdue
        final now = DateTime.now();
        final isOverdue = date.isBefore(now);
        if (isOverdue) {
          expectedReturnStr += ' (OVERDUE)';
        }
      } catch (e) {
        expectedReturnStr = 'Invalid date';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with demo number and return button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        demoNumber,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        demoPurpose,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      if (isPartiallyReturned) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: Text(
                            'Partially Returned',
                            style: TextStyle(
                              color: Colors.orange[700],
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _navigateToDetailScreen(demo),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('View Details'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Demo details
            _buildDetailRow('Dealer', dealer),
            _buildDetailRow('Client', client),
            _buildDetailRow('Location', location),
            _buildDetailRow(
              'Items',
              isPartiallyReturned
                  ? '$itemCount items remaining (of $totalItems)'
                  : '$itemCount items',
            ),
            _buildDetailRow('Created', createdDateStr),
            _buildDetailRow('Expected Return', expectedReturnStr),

            if (remarks.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Remarks', remarks),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: value.contains('OVERDUE') ? Colors.red : Colors.black87,
                fontWeight: value.contains('OVERDUE')
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
