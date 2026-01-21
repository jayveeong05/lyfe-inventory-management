import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../services/demo_service.dart';
import 'demo_detail_screen.dart';

class DemoHistoryScreen extends StatefulWidget {
  const DemoHistoryScreen({super.key});

  @override
  State<DemoHistoryScreen> createState() => _DemoHistoryScreenState();
}

class _DemoHistoryScreenState extends State<DemoHistoryScreen> {
  List<Map<String, dynamic>> _returnedDemos = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadReturnedDemos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReturnedDemos() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final demoService = DemoService(authService: authProvider.authService);

      // Get returned demos only
      final demos = await demoService.getDemoHistory(
        status: 'Returned',
        limit: 100,
        fetchItems: true, // Fetch items for serial number search
      );

      if (mounted) {
        setState(() {
          _returnedDemos = demos;
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
            content: Text('Error loading demo history: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredDemos {
    if (_searchQuery.isEmpty) {
      return _returnedDemos;
    }
    return _returnedDemos.where((demo) {
      final demoNumber = (demo['demo_number'] ?? '').toString().toLowerCase();
      final demoPurpose = (demo['demo_purpose'] ?? '').toString().toLowerCase();
      final dealer = (demo['customer_dealer'] ?? '').toString().toLowerCase();
      final client = (demo['customer_client'] ?? '').toString().toLowerCase();

      // Check serial numbers
      final serialNumbers =
          (demo['serial_numbers'] as List<dynamic>?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          [];

      final query = _searchQuery.toLowerCase();
      final matchesSerial = serialNumbers.any((sn) => sn.contains(query));

      return demoNumber.contains(query) ||
          demoPurpose.contains(query) ||
          dealer.contains(query) ||
          client.contains(query) ||
          matchesSerial;
    }).toList();
  }

  Future<void> _navigateToDetailScreen(Map<String, dynamic> demo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DemoDetailScreen(demo: demo)),
    );
    // No need to refresh on return as history shouldn't change from detail view interaction usually
    // But if we add features later, we might want to.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo History'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadReturnedDemos,
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
                    'Search history by number, serial, dealer, or client...',
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
              _searchQuery.isNotEmpty ? Icons.search_off : Icons.history,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No history found matching "$_searchQuery"'
                  : 'No returned demos found',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReturnedDemos,
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
    final itemCount = demo['total_items'] ?? 0;
    final createdDate = demo['created_date'];
    final actualReturnDate = demo['actual_return_date'];

    // Format dates
    String createdDateStr = 'Unknown';
    String returnDateStr = 'Unknown';

    if (createdDate != null) {
      try {
        final date = createdDate.toDate();
        createdDateStr = DateFormat('dd/MM/yyyy').format(date);
      } catch (e) {
        createdDateStr = 'Invalid date';
      }
    }

    if (actualReturnDate != null) {
      try {
        final date = actualReturnDate.toDate();
        returnDateStr = DateFormat('dd/MM/yyyy').format(date);
      } catch (e) {
        returnDateStr = 'Invalid date';
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
            // Header
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
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        demoPurpose,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: const Text(
                    'Returned',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Details
            _buildDetailRow('Dealer', dealer),
            _buildDetailRow('Client', client),

            // Serial Numbers Display
            if (demo['serial_numbers'] != null &&
                (demo['serial_numbers'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Serial Numbers:',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: (demo['serial_numbers'] as List).map((sn) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            sn.toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 4), // Spacing after chips
                  ],
                ),
              ),

            _buildDetailRow('Items', '$itemCount items'),
            _buildDetailRow('Created', createdDateStr),
            _buildDetailRow('Returned', returnDateStr),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _navigateToDetailScreen(demo),
                icon: const Icon(Icons.visibility, size: 18),
                label: const Text('View Details'),
              ),
            ),
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
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
