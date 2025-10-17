import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/stock_service.dart';
import 'qr_scanner_screen.dart';

class StockInScreen extends StatefulWidget {
  const StockInScreen({super.key});

  @override
  State<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends State<StockInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serialNumberController = TextEditingController();
  final _equipmentCategoryController = TextEditingController();
  final _modelController = TextEditingController();
  final _sizeController = TextEditingController();
  final _batchController = TextEditingController();
  final _remarksController = TextEditingController();

  StockService? _stockService;
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stockService == null) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _stockService = StockService(authService: authProvider.authService);
    }
  }

  @override
  void dispose() {
    _serialNumberController.dispose();
    _equipmentCategoryController.dispose();
    _modelController.dispose();
    _sizeController.dispose();
    _batchController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null && result is String) {
      setState(() {
        _serialNumberController.text = result;
      });
    }
  }

  Future<void> _submitStockIn() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Use StockService to handle the stock in operation
      final result = await _stockService!.stockInItem(
        serialNumber: _serialNumberController.text.trim(),
        equipmentCategory: _equipmentCategoryController.text.trim(),
        model: _modelController.text.trim(),
        size: _sizeController.text.trim().isEmpty
            ? null
            : _sizeController.text.trim(),
        batch: _batchController.text.trim(),
        remarks: _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${result['message']}\nTransaction ID: ${result['transaction_number']}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // Clear the form
          _formKey.currentState!.reset();
          _serialNumberController.clear();
          _equipmentCategoryController.clear();
          _modelController.clear();
          _sizeController.clear();
          _batchController.clear();
          _remarksController.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Unknown error occurred'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock In'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Serial Number field with QR scan button
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _serialNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Serial Number',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.qr_code),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a serial number';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _scanQRCode,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Scan'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Equipment Category field
                      TextFormField(
                        controller: _equipmentCategoryController,
                        decoration: const InputDecoration(
                          labelText: 'Equipment Category',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                          hintText: 'e.g., Interactive Flat Panel',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the equipment category';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Model field
                      TextFormField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.precision_manufacturing),
                          hintText: 'e.g., 65M6APRO, 9002',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the model';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Size field (optional)
                      TextFormField(
                        controller: _sizeController,
                        decoration: const InputDecoration(
                          labelText: 'Size (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.straighten),
                          hintText:
                              'e.g., 65 Inch, 75 Inch (leave empty if not applicable)',
                        ),
                        // No validator - field is optional
                      ),

                      const SizedBox(height: 20),

                      // Batch field
                      TextFormField(
                        controller: _batchController,
                        decoration: const InputDecoration(
                          labelText: 'Batch',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.inventory),
                          hintText: 'e.g., 成品出库-EDS01',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the batch';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Remarks field (optional)
                      TextFormField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                          labelText: 'Remarks (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.note),
                          hintText: 'Additional notes or comments',
                        ),
                        maxLines: 3,
                        // Remove validator to make it optional
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),

              // Submit button
              ElevatedButton(
                onPressed: _isLoading ? null : _submitStockIn,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Stock In Item',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
