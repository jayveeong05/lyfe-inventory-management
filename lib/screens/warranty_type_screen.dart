import 'package:flutter/material.dart';
import '../services/warranty_type_service.dart';

class WarrantyTypeScreen extends StatefulWidget {
  const WarrantyTypeScreen({super.key});

  @override
  State<WarrantyTypeScreen> createState() => _WarrantyTypeScreenState();
}

class _WarrantyTypeScreenState extends State<WarrantyTypeScreen> {
  final WarrantyTypeService _service = WarrantyTypeService();
  List<Map<String, dynamic>> _types = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    setState(() => _isLoading = true);
    final types = await _service.getWarrantyTypes();
    if (mounted) {
      setState(() {
        _types = types;
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _service.saveWarrantyTypes(_types);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Warranty types saved successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showAddEditDialog({int? editIndex}) {
    final existing = editIndex != null
        ? Map<String, dynamic>.from(_types[editIndex])
        : null;

    final displayController = TextEditingController(
      text: existing?['display'] as String? ?? '',
    );
    final periodController = TextEditingController(
      text: existing != null ? '${existing['period']}' : '',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          editIndex == null ? 'Add Warranty Type' : 'Edit Warranty Type',
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: displayController,
                decoration: const InputDecoration(
                  labelText: 'Display Name *',
                  hintText: 'e.g. 1+2 Year',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: periodController,
                decoration: const InputDecoration(
                  labelText: 'Period (years) *',
                  hintText: 'e.g. 3',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final parsed = int.tryParse(v.trim());
                  if (parsed == null || parsed < 1) {
                    return 'Enter a valid positive number';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final display = displayController.text.trim();
              final period = int.parse(periodController.text.trim());
              // Derive the stored value from the display name (lowercase).
              final value = display.toLowerCase();

              setState(() {
                if (editIndex == null) {
                  _types.add(<String, dynamic>{
                    'display': display,
                    'value': value,
                    'period': period,
                  });
                } else {
                  _types[editIndex] = <String, dynamic>{
                    'display': display,
                    'value': value,
                    'period': period,
                  };
                }
              });
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
            ),
            child: Text(editIndex == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _deleteType(int index) {
    final type = _types[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Warranty Type'),
        content: Text(
          'Delete "${type['display']}"? This will not affect existing records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _types.removeAt(index));
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Warranty Types'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text(
                      'Save',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Description banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.blue.shade50,
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Define the warranty options available when creating orders. '
                          'Tap Save to apply changes app-wide.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // List
                Expanded(
                  child: _types.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.security_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No warranty types defined.',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap + to add one.',
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _types.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex--;
                              final item = _types.removeAt(oldIndex);
                              _types.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (context, index) {
                            final type = _types[index];
                            return Card(
                              key: ValueKey(index),
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green.shade50,
                                  child: Icon(
                                    Icons.security,
                                    color: Colors.green.shade700,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  type['display'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${type['period']} year${(type['period'] as int) == 1 ? '' : 's'} coverage  •  stored as "${type['value']}"',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.blue,
                                        size: 20,
                                      ),
                                      tooltip: 'Edit',
                                      onPressed: () =>
                                          _showAddEditDialog(editIndex: index),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteType(index),
                                    ),
                                    const Icon(
                                      Icons.drag_handle,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddEditDialog(),
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add Type'),
            ),
    );
  }
}
