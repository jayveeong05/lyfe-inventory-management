import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for managing user-defined warranty types stored in Firestore.
///
/// Data is persisted in: `settings/warranty_types`
/// Document shape:
/// ```json
/// {
///   "types": [
///     { "display": "1 Year", "value": "1 year", "period": 1 },
///     ...
///   ]
/// }
/// ```
class WarrantyTypeService {
  static const String _collection = 'settings';
  static const String _document = 'warranty_types';

  /// Default warranty types used when no Firestore document exists yet.
  static const List<Map<String, dynamic>> defaultWarrantyTypes = [
    {'display': '1 Year', 'value': '1 year', 'period': 1},
    {'display': '1+2 Year', 'value': '1+2 year', 'period': 3},
    {'display': '1+3 Year', 'value': '1+3 year', 'period': 4},
    {'display': '1+4 Year', 'value': '1+4 year', 'period': 5},
  ];

  final FirebaseFirestore _db;

  WarrantyTypeService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _db.collection(_collection).doc(_document);

  /// Fetches the list of warranty types from Firestore.
  /// Falls back to [defaultWarrantyTypes] if the document does not exist.
  Future<List<Map<String, dynamic>>> getWarrantyTypes() async {
    try {
      final snapshot = await _docRef.get();
      if (!snapshot.exists || snapshot.data() == null) {
        return List<Map<String, dynamic>>.from(defaultWarrantyTypes);
      }

      final data = snapshot.data()!;
      final rawTypes = data['types'] as List<dynamic>?;
      if (rawTypes == null || rawTypes.isEmpty) {
        return List<Map<String, dynamic>>.from(defaultWarrantyTypes);
      }

      return rawTypes.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return <String, dynamic>{
          'display': map['display'] as String? ?? '',
          'value': map['value'] as String? ?? '',
          'period': (map['period'] as num?)?.toInt() ?? 0,
        };
      }).toList();
    } catch (e) {
      // On error, fall back to defaults to keep the UI functional.
      return List<Map<String, dynamic>>.from(defaultWarrantyTypes);
    }
  }

  /// Persists [types] to Firestore, replacing the existing list.
  Future<void> saveWarrantyTypes(List<Map<String, dynamic>> types) async {
    await _docRef.set({'types': types});
  }
}
