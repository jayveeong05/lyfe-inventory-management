import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CustomerDetailsScreen extends StatelessWidget {
  final String customerName;
  final List<dynamic> items;

  const CustomerDetailsScreen({
    super.key,
    required this.customerName,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    // Group items by order to show purchase history
    final Map<String, List<dynamic>> ordersMap = {};
    for (var item in items) {
      final orderNumber = item['order_number'] ?? 'Unknown Order';
      if (!ordersMap.containsKey(orderNumber)) {
        ordersMap[orderNumber] = [];
      }
      ordersMap[orderNumber]!.add(item);
    }

    // Sort orders by date (newest first)
    final sortedOrderKeys = ordersMap.keys.toList()
      ..sort((a, b) {
        final dateA = ordersMap[a]!.first['date'] as DateTime?;
        final dateB = ordersMap[b]!.first['date'] as DateTime?;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA);
      });

    return Scaffold(
      appBar: AppBar(title: Text(customerName)),
      body: Column(
        children: [
          // Sales Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    _buildSummaryMetric(
                      'Total Orders',
                      sortedOrderKeys.length.toString(),
                      Icons.shopping_bag_outlined,
                      Colors.blue,
                    ),
                    const SizedBox(width: 16),
                    _buildSummaryMetric(
                      'Total Items',
                      items.length.toString(),
                      Icons.inventory_2_outlined,
                      Colors.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildSummaryMetric(
                      'First Purchase',
                      sortedOrderKeys.isNotEmpty
                          ? DateFormat('MMM yyyy').format(
                              ordersMap[sortedOrderKeys.last]!.first['date']
                                  as DateTime,
                            )
                          : 'N/A',
                      Icons.calendar_today_outlined,
                      Colors.purple,
                    ),
                    const SizedBox(width: 16),
                    _buildSummaryMetric(
                      'Last Active',
                      sortedOrderKeys.isNotEmpty
                          ? DateFormat('MMM dd, yyyy').format(
                              ordersMap[sortedOrderKeys.first]!.first['date']
                                  as DateTime,
                            )
                          : 'N/A',
                      Icons.history,
                      Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Orders List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedOrderKeys.length,
              itemBuilder: (context, index) {
                final orderNumber = sortedOrderKeys[index];
                final orderItems = ordersMap[orderNumber]!;
                final date = orderItems.first['date'] as DateTime?;
                final dateStr = date != null
                    ? DateFormat('MMM dd, yyyy').format(date)
                    : 'Unknown Date';

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Order #$orderNumber',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${orderItems.length} items',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(),
                        ),
                        ...orderItems.map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.devices_other,
                                    size: 20,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['category'] ?? 'Unknown Category',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (item['model'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            item['model'],
                                            style: TextStyle(
                                              color: Colors.grey.shade800,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          'SN: ${item['serial_number'] ?? 'N/A'}',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color.withOpacity(0.8),
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
