# API Reference Documentation

## Overview

This document provides comprehensive API reference for all services in the Inventory Management System. Each service handles specific business logic and Firebase operations.

**Status: Production Ready ✅** - All APIs documented below are fully implemented, tested, and production-ready as of Version 2.1.0 (December 2025).

## Authentication Service

### AuthService (`lib/services/auth_service.dart`)

#### Methods

##### `signInWithEmailAndPassword(String email, String password)`
- **Purpose**: Authenticate user with email and password
- **Parameters**:
  - `email`: User's email address
  - `password`: User's password
- **Returns**: `Future<UserCredential?>`
- **Throws**: `FirebaseAuthException` on authentication failure

##### `registerWithEmailAndPassword(String email, String password, String displayName, UserRole role)`
- **Purpose**: Register new user account
- **Parameters**:
  - `email`: User's email address
  - `password`: User's password
  - `displayName`: User's display name
  - `role`: User role (admin or user)
- **Returns**: `Future<UserCredential?>`
- **Side Effects**: Creates user profile in Firestore

##### `signOut()`
- **Purpose**: Sign out current user
- **Returns**: `Future<void>`

##### `getCurrentUser()`
- **Purpose**: Get current authenticated user
- **Returns**: `User?`

##### `changePassword(String currentPassword, String newPassword)`
- **Purpose**: Securely update user password with re-authentication
- **Parameters**:
  - `currentPassword`: Current password for verification
  - `newPassword`: New password to set
- **Returns**: `Future<bool>` - true if successful, false otherwise
- **Operations**:
  - Re-authenticates user with current password
  - Updates password in Firebase Auth
  - Handles detailed error messages for wrong password/weak password

##### `hasAdminAccess()`
- **Purpose**: Check if current user has admin privileges
- **Returns**: `bool`
- **Usage**: Used for role-based UI controls and security restrictions

## Stock Service

### StockService (`lib/services/stock_service.dart`)

#### Methods

##### `stockInItem({required String serialNumber, required String equipmentCategory, required String model, String? size, required String batch, String? remarks})`
- **Purpose**: Add single item to inventory with manual input
- **Parameters**:
  - `serialNumber`: Unique serial number for the item
  - `equipmentCategory`: Category of equipment (e.g., Interactive Flat Panel)
  - `model`: Model number (manually entered, no longer extracted from serial)
  - `size`: Optional size specification (e.g., 65 Inch) - can be null for categories without size
  - `batch`: Batch information
  - `remarks`: Optional remarks/notes
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Validates serial number uniqueness
  - Creates inventory record with manual model input
  - Creates transaction record with "Stock_In" type
  - Uses Firestore batch operations for atomicity

##### `createStockOut(String poNumber, String customerDealer, String customerClient, List<String> serialNumbers, String userUid)`
- **Purpose**: Create purchase order and reserve items
- **Parameters**:
  - `poNumber`: Purchase order number
  - `customerDealer`: Dealer information
  - `customerClient`: Client information
  - `serialNumbers`: List of serial numbers to reserve
  - `userUid`: User ID performing the operation
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Creates order document with dual status fields (invoice_status: 'Reserved', delivery_status: 'Pending')
  - Updates item status to "Reserved"
  - Creates transaction records
  - Uses atomic transactions

##### `updateOrderWithFile(String orderNumber, String fileId, String fileType)`
- **Purpose**: Update order with uploaded file information
- **Parameters**:
  - `orderNumber`: Order number to update
  - `fileId`: File ID from files collection
  - `fileType`: Type of file ('invoice', 'delivery_order', 'signed_delivery_order')
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Updates order status based on file type
  - Creates new transactions for signed delivery orders
  - Maintains audit trail of status changes

##### `getAllOrders({String? status, String? invoiceStatus, String? deliveryStatus})`
- **Purpose**: Retrieve orders with filtering options
- **Parameters**:
  - `status`: Legacy status filter (for backward compatibility)
  - `invoiceStatus`: Filter by invoice_status ('Reserved', 'Invoiced')
  - `deliveryStatus`: Filter by delivery_status ('Pending', 'Issued', 'Delivered')
- **Returns**: `Future<List<Map<String, dynamic>>>`
- **Features**:
  - Supports both legacy single status and new dual status systems
  - In-memory filtering for backward compatibility

##### `searchAvailableItems(String query)`
- **Purpose**: Search for available inventory items
- **Parameters**:
  - `query`: Search query string
- **Returns**: `Future<List<Map<String, dynamic>>>`
- **Features**:
  - Searches across multiple fields
  - Filters by "Active" status
  - Real-time search capabilities

## Order Service (Enhanced)

### OrderService (`lib/services/order_service.dart`)

#### Methods

##### `createMultiItemStockOutOrder({required String orderNumber, required String dealerName, required String clientName, required String location, required List<Map<String, dynamic>> selectedItems})`
- **Purpose**: Create order and reserve multiple items with dual status system
- **Parameters**:
  - `orderNumber`: Order number
  - `dealerName`: Dealer information
  - `clientName`: Client information
  - `location`: Location abbreviation (e.g., "SGR")
  - `selectedItems`: List of selected items with complete information including individual warranty types and periods
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Validates all items are still available
  - Generates sequential transaction IDs to prevent duplicates
  - Creates multiple transaction records (one per item) with individual warranty information
  - Creates single purchase order with multiple transaction IDs
  - Uses Firestore batch operations for atomicity

##### `processItemReturn({required String returnedSerial, required String replacementSerial, required String dealerName, required String remarks, required String userUid})`
- **Purpose**: Process stock return with replacement
- **Parameters**:
  - `returnedSerial`: Serial number of item being returned
  - `replacementSerial`: Serial number of replacement item (from active inventory)
  - `dealerName`: Associated dealer/client name
  - `remarks`: Return remarks
  - `userUid`: User ID performing operation
- **Returns**: `Future<Map<String, dynamic>>`
- **Operations**:
  - Updates returned item status to 'Returned'
  - Updates replacement item status to 'Reserved' (preserving Dealer/Client info)
  - Creates return transaction records
  - Syncs inventory status fields for consistency

##### `getAllPurchaseOrders()`
- **Purpose**: Retrieve all purchase orders
- **Returns**: `Future<List<Map<String, dynamic>>>`
- **Ordering**: Sorted by creation date (newest first)

##### `getPurchaseOrderById(String id)`
- **Purpose**: Get specific purchase order by ID
- **Parameters**:
  - `id`: Purchase order document ID
- **Returns**: `Future<Map<String, dynamic>?>`

##### `updatePurchaseOrderStatus(String id, String status, Map<String, dynamic> additionalData)`
- **Purpose**: Update purchase order status and additional data
- **Parameters**:
  - `id`: Purchase order document ID
  - `status`: New status value
  - `additionalData`: Additional fields to update
- **Returns**: `Future<void>`

## File Service (New)

### FileService (`lib/services/file_service.dart`)

#### Methods

##### `uploadFile({required File file, required String orderNumber, required String fileType, required String userUid})`
- **Purpose**: Upload PDF files to Firebase Storage with metadata tracking
- **Parameters**:
  - `file`: File object to upload
  - `orderNumber`: Associated order number
  - `fileType`: Type of file ('invoice', 'delivery_order', 'signed_delivery_order')
  - `userUid`: User ID performing the upload
- **Returns**: `Future<Map<String, dynamic>>` with file ID and metadata
- **Operations**:
  - Validates file type and size
  - Uploads to Firebase Storage with organized path structure
  - Creates file document in Firestore with metadata
  - Generates unique file names with timestamps

##### `replaceFile({required File newFile, required String existingFileId, required String orderNumber, required String fileType, required String userUid})`
- **Purpose**: Replace existing file while maintaining proper references
- **Parameters**:
  - `newFile`: New file to upload
  - `existingFileId`: ID of file to replace
  - `orderNumber`: Associated order number
  - `fileType`: Type of file
  - `userUid`: User ID performing the replacement
- **Returns**: `Future<Map<String, dynamic>>` with new file information
- **Operations**:
  - Uploads new file to Firebase Storage
  - Creates new file document with updated metadata
  - Deletes old file from storage and Firestore
  - Maintains file version history

##### `deleteFile(String fileId)`
- **Purpose**: Delete file from both Storage and Firestore
- **Parameters**:
  - `fileId`: ID of file to delete
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Removes file from Firebase Storage
  - Deletes file document from Firestore
  - Handles cleanup of orphaned references

## Invoice Service (Enhanced)

### InvoiceService (`lib/services/invoice_service.dart`)

**Architecture Change**: Invoice management now uses the dual status system with separate files collection for better organization and OCR text extraction capabilities.

#### Methods

##### `uploadInvoice({required File invoiceFile, required String orderNumber, required String invoiceNumber, required String invoiceDate, required String userUid})`
- **Purpose**: Upload invoice PDF with OCR text extraction and update order status
- **Parameters**:
  - `invoiceFile`: PDF file to upload
  - `orderNumber`: Order number
  - `invoiceNumber`: Invoice number (can be extracted via OCR)
  - `invoiceDate`: Invoice date (can be extracted via OCR)
  - `userUid`: User ID performing upload
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Uses FileService to upload PDF to Firebase Storage
  - Updates order invoice_status to "Invoiced"
  - Creates file metadata record with proper file type
  - Maintains transaction audit trail

##### `extractPdfData(File pdfFile)`
- **Purpose**: Extract invoice number and date from PDF using OCR
- **Parameters**:
  - `pdfFile`: PDF file to process
- **Returns**: `Future<Map<String, dynamic>>` with extracted data and confidence scores
- **Operations**:
  - Uses Syncfusion Flutter PDF library for text extraction
  - Applies multiple regex patterns for data parsing
  - Returns confidence scores for validation
  - Supports cross-platform PDF processing

##### `getAvailableOrders()`
- **Purpose**: Get orders available for invoice upload (Reserved status)
- **Returns**: `Future<List<Map<String, dynamic>>>` - List of orders with Reserved invoice_status
- **Operations**:
  - Filters orders by invoice_status = 'Reserved'
  - Supports backward compatibility with legacy status field

## Delivery Service (New)

### DeliveryService (`lib/services/delivery_service.dart`)

#### Methods

##### `uploadDeliveryOrder({required File deliveryFile, required String orderNumber, required String deliveryNumber, required String deliveryDate, String? deliveryRemarks, required String userUid})`
- **Purpose**: Upload normal delivery order PDF and update order status to "Issued"
- **Parameters**:
  - `deliveryFile`: PDF file to upload
  - `orderNumber`: Order number
  - `deliveryNumber`: Delivery order number
  - `deliveryDate`: Delivery date
  - `deliveryRemarks`: Optional delivery remarks
  - `userUid`: User ID performing upload
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Uses FileService with file_type 'delivery_order'
  - Updates order delivery_status to "Issued"
  - Stores delivery information in order document
  - Maintains existing transaction records

##### `uploadSignedDeliveryOrder({required File signedDeliveryFile, required String orderNumber, required String userUid})`
- **Purpose**: Upload signed delivery order PDF and create new "Delivered" transaction
- **Parameters**:
  - `signedDeliveryFile`: Signed PDF file to upload
  - `orderNumber`: Order number
  - `userUid`: User ID performing upload
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Uses FileService with file_type 'signed_delivery_order'
  - Updates order delivery_status to "Delivered"
  - Creates NEW transaction record with status "Delivered"
  - Preserves original "Reserved" transaction for audit trail
  - Uses shared delivery information from normal delivery upload

##### `getOrdersForDelivery()`
- **Purpose**: Get orders available for delivery operations (Invoiced status)
- **Returns**: `Future<List<Map<String, dynamic>>>` - List of orders with Invoiced invoice_status
- **Operations**:
  - Filters orders by invoice_status = 'Invoiced'
  - Supports all delivery_status values (Pending, Issued, Delivered)
  - Backward compatibility with legacy status field

##### `deleteDeliveryData(String orderNumber)`
- **Purpose**: Remove delivery PDFs and revert delivery status
- **Parameters**:
  - `orderNumber`: Order number to clean up
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Deletes both normal and signed delivery PDFs from storage
  - Removes delivery file references from order
  - Reverts delivery_status to "Pending"
  - Preserves invoice data and transaction records

##### `replaceInvoice({required String poId, required File newPdfFile, String? newInvoiceNumber, DateTime? newInvoiceDate, String? remarks})`
- **Purpose**: Replace existing invoice with new PDF
- **Parameters**:
  - `poId`: Purchase order ID (changed from invoiceId)
  - `newPdfFile`: New PDF file
  - `newInvoiceNumber`: Optional new invoice number
  - `newInvoiceDate`: Optional new invoice date
  - `remarks`: Optional remarks
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Validates new PDF file
  - Uploads new file to storage
  - Updates purchase order with new invoice data
  - Updates related transactions
  - Deletes old PDF file

##### `deleteInvoice(String orderId)`
- **Purpose**: Remove invoice data from order
- **Parameters**:
  - `orderId`: Order ID (changed from invoiceId)
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Removes all invoice fields from order
  - Reverts order status to 'Pending'
  - Deletes PDF file from storage

##### `_validatePdfFile(File file)`
- **Purpose**: Validate PDF file format and size
- **Parameters**:
  - `file`: File to validate
- **Returns**: `bool`
- **Validation Rules**:
  - Must be PDF format
  - Maximum size: 10MB

## Monthly Inventory Service

### MonthlyInventoryService (`lib/services/monthly_inventory_service.dart`)

#### Methods

##### `getMonthlyInventoryActivity(DateTime selectedDate)`
- **Purpose**: Generate comprehensive monthly inventory activity report
- **Parameters**:
  - `selectedDate`: Date within the target month for reporting
- **Returns**: `Future<Map<String, dynamic>>` with complete monthly report data
- **Features**:
  - Summary analytics (total stock in, stock out, remaining)
  - Size breakdown (panel sizes with meaningful dimensions)
  - Category breakdown (all equipment categories)
  - Detailed item tracking with hierarchical organization
  - Performance optimization with caching and batch processing

##### `_getOptimizedCumulativeStockIn(DateTime endDate)`
- **Purpose**: Get cumulative stock-in data with caching optimization
- **Parameters**:
  - `endDate`: End date for cumulative calculation
- **Returns**: `Future<Map<String, int>>` - Size-based stock-in counts
- **Features**:
  - 5-minute cache for performance
  - Batch processing for large datasets
  - Excludes "Others" category for size analysis

##### `_getOptimizedCumulativeStockOut(DateTime endDate)`
- **Purpose**: Get cumulative stock-out data with caching optimization
- **Parameters**:
  - `endDate`: End date for cumulative calculation
- **Returns**: `Future<Map<String, int>>` - Size-based stock-out counts
- **Features**:
  - Excludes 'Active' status transactions
  - Batch serial number size lookups
  - Intelligent caching system

##### `_getSizeBreakdown(Map<String, int> stockIn, Map<String, int> stockOut, Map<String, int> remaining)`
- **Purpose**: Generate size breakdown table data
- **Parameters**:
  - `stockIn`: Stock-in counts by size
  - `stockOut`: Stock-out counts by size
  - `remaining`: Remaining counts by size
- **Returns**: `List<Map<String, dynamic>>` - Formatted size breakdown
- **Features**:
  - Includes all sizes with any activity or remaining items
  - Sorted alphabetically by size
  - Handles missing data gracefully

#### Performance Features
- **Smart Caching**: 5-minute cache validity for cumulative calculations
- **Batch Processing**: 500-document batches for large datasets
- **N+1 Query Prevention**: Batch lookups for serial number size information
- **Memory Optimization**: Efficient data processing for large inventories

#### Data Separation Strategy
- **Summary Calculations**: Include ALL items for accurate totals
- **Size Breakdown**: Exclude "Others" category (no meaningful sizes)
- **Category Breakdown**: Include ALL categories dynamically

## Inventory Management Service (Enhanced Security)

### InventoryManagementService (`lib/services/inventory_management_service.dart`)

#### Security Enhancements

##### Role-Based UI Controls
- **Admin-Only Operations**: Edit and delete inventory items restricted to admin users
- **Dynamic Menu Generation**: PopupMenuButton uses Consumer<AuthProvider> for real-time role checking
- **Preserved Functionality**: All users can view details and perform stock-out operations
- **Security Pattern**: `if (authProvider.hasAdminAccess()) ...` controls menu item visibility

##### Implementation Details
```dart
// Admin-only menu items in inventory management
if (authProvider.hasAdminAccess()) ...[
  const PopupMenuItem(value: 'edit', child: Text('Edit Item')),
  const PopupMenuItem(value: 'delete', child: Text('Delete Item')),
],
```

##### User Experience by Role
- **Regular Users**: See "View Details" and "Stock Out" options only
- **Admin Users**: See all options including "Edit Item" and "Delete Item"
- **Real-time Updates**: Permissions update immediately when user role changes

## Data Upload Service

### DataUploadService (`lib/services/data_upload_service.dart`)

#### Methods

##### `uploadInventoryData(Uint8List fileBytes, String userUid)`
- **Purpose**: Upload inventory data from Excel file
- **Parameters**:
  - `fileBytes`: Excel file bytes
  - `userUid`: User ID performing upload
- **Returns**: `Future<Map<String, dynamic>>` with success/error status
- **Operations**:
  - Processes Excel file
  - Converts Excel dates to timestamps
  - Validates data format
  - Uploads to Firestore in batches

##### `uploadTransactionData(Uint8List fileBytes, String userUid)`
- **Purpose**: Upload transaction data from Excel file
- **Parameters**:
  - `fileBytes`: Excel file bytes
  - `userUid`: User ID performing upload
- **Returns**: `Future<Map<String, dynamic>>` with success/error status

##### `clearCollection(String collectionName)`
- **Purpose**: Clear all documents from a collection
- **Parameters**:
  - `collectionName`: Name of collection to clear
- **Returns**: `Future<void>`
- **Warning**: Destructive operation, use with caution

## Error Handling

### Common Error Patterns

#### Service Response Format
```dart
{
  'success': bool,
  'message': String,
  'error': String?, // Only present on failure
  'data': dynamic? // Additional data on success
}
```

#### Error Types
- **ValidationError**: Input validation failures
- **AuthenticationError**: Authentication/authorization failures
- **NetworkError**: Network connectivity issues
- **StorageError**: Firebase Storage operation failures
- **DatabaseError**: Firestore operation failures

### Exception Handling
```dart
try {
  final result = await stockService.addStockIn(items, userUid);
  if (result['success']) {
    // Handle success
  } else {
    // Handle business logic error
    showError(result['message']);
  }
} catch (e) {
  // Handle system error
  showError('System error: $e');
}
```

## Data Models

### User Profile
```dart
{
  'uid': String,
  'email': String,
  'displayName': String,
  'role': String, // 'admin' or 'user'
  'createdAt': Timestamp,
  'lastLoginAt': Timestamp
}
```

### Inventory Item
```dart
{
  'serial_number': String,
  'item_name': String,
  'category': String,
  'brand': String,
  'model': String,
  'specifications': String,
  'purchase_price': double,
  'selling_price': double,
  'supplier': String,
  'location': String,
  'status': String, // 'Active', 'Reserved', 'Sold'
  'created_at': Timestamp,
  'updated_at': Timestamp,
  'created_by_uid': String,
  'updated_by_uid': String
}
```

### Transaction Record
```dart
{
  'serial_number': String,
  'transaction_type': String, // 'Stock_In', 'Stock_Out'
  'item_name': String,
  'category': String,
  'brand': String,
  'model': String,
  'specifications': String,
  'purchase_price': double,
  'selling_price': double,
  'supplier': String,
  'location': String, // Malaysian state abbreviation (e.g., 'SGR', 'KUL', 'JHR')
  'warranty_type': String?, // '1 year' or '1+2 year'
  'warranty_period': int?, // Calculated warranty period in years (1 or 3)
  'status': String,
  'po_number': String?, // For Stock_Out transactions
  'customer_dealer': String?, // For Stock_Out transactions
  'customer_client': String?, // For Stock_Out transactions
  'created_at': Timestamp,
  'created_by_uid': String
}
```

### Purchase Order (with integrated invoice data and simplified item storage)
```dart
{
  'po_number': String,
  'customer_dealer': String,
  'customer_client': String,
  'transaction_ids': List<int>, // References to transaction records
  'total_items': int,
  'total_quantity': int,
  'status': String, // 'Pending', 'Invoiced'
  'created_at': Timestamp,
  'updated_at': Timestamp,
  'created_by_uid': String,
  'updated_by_uid': String?,

  // Invoice fields (added when invoice is uploaded)
  'invoice_number': String?, // Invoice number
  'invoice_date': Timestamp?, // Invoice date
  'pdf_url': String?, // Firebase Storage download URL
  'pdf_path': String?, // Storage path for file management
  'file_name': String?, // Original filename
  'file_size': int?, // File size in bytes
  'invoice_remarks': String?, // Optional remarks
  'invoice_uploaded_by_uid': String?, // User who uploaded
  'invoice_uploaded_at': Timestamp?, // Upload timestamp
  'invoice_updated_by_uid': String?, // User who last updated
  'invoice_updated_at': Timestamp? // Last update timestamp
}
```

**Architecture Improvements**:
- **Simplified Item Storage**: Purchase orders now only store `transaction_ids` instead of duplicating item details
- **Data Consistency**: Item information is retrieved from transaction records, ensuring single source of truth
- **Reduced Redundancy**: Eliminates duplicate storage of item details across collections
- **Backward Compatibility**: System supports both new format (`transaction_ids`) and legacy format (`items` array)

**UI Improvements**:
- **Multi-Item Orders**: Stock-out feature now supports adding multiple items to a single order with enhanced UI
- **Manual Model Input**: Stock-in feature now includes manual model input field for better accuracy and flexibility
- **Entry Number Display**: Stock-out feature now shows the next entry number that will be assigned to the transaction
- **Warranty Management**: Stock-out feature now includes warranty type selection with automatic period calculation
- **Location Selection**: Stock-out feature now includes Malaysian states dropdown with proper abbreviations
- **Enhanced Order Details Display**: Invoice screen now shows detailed item information instead of generic "Total Items" count
- **Comprehensive Item Cards**: Each item displays serial number, category, model, size, batch, and transaction ID
- **Accurate Batch Information**: Batch data is fetched from inventory table ensuring correct and up-to-date information
- **Improved User Experience**: Users can see complete item details when selecting purchase orders for invoicing

## Malaysian States Reference

The system supports all 16 Malaysian states and federal territories with their official abbreviations:

| State/Territory | Abbreviation |
|----------------|--------------|
| Johor Darul Ta'zim | JHR |
| Kedah Darul Aman | KDH |
| Kelantan Darul Naim | KTN |
| Melaka | MLK |
| Negeri Sembilan Darul Khusus | NSN |
| Pahang Darul Makmur | PHG |
| Pulau Pinang | PNG |
| Perak Darul Ridzuan | PRK |
| Perlis Indera Kayangan | PLS |
| Selangor Darul Ehsan | SGR |
| Terengganu Darul Iman | TRG |
| Sabah | SBH |
| Sarawak | SWK |
| Wilayah Persekutuan Kuala Lumpur | KUL |
| Wilayah Persekutuan Labuan | LBN |
| Wilayah Persekutuan Putra Jaya | PJY |

**Note**: Only the abbreviations are stored in the database to maintain consistency and reduce storage overhead.

## Warranty Types Reference

The system supports predefined warranty types with automatic period calculation:

| Warranty Type | Display Name | Period (Years) | Description |
|---------------|--------------|----------------|-------------|
| 1 year | 1 Year | 1 | Standard 1-year warranty |
| 1+2 year | 1+2 Year | 3 | Extended warranty: 1 year standard + 2 years extended |
| 1+3 year | 1+3 Year | 4 | Extended warranty: 1 year standard + 3 years extended |

**Implementation Details**:
- **Individual Item Warranty**: Each item in a multi-item order can have its own warranty type and period
- **Automatic Calculation**: Warranty period is automatically calculated based on selected type for each item
- **Database Storage**: Both `warranty_type` (string) and `warranty_period` (integer) are stored per transaction record
- **UI Integration**: Warranty dropdown is displayed for each selected item in the order
- **Extensible**: Additional warranty types can be easily added to the system

## Entry Number Management

The system automatically manages entry numbers for all transactions:

**Entry Number Generation**:
- **Sequential Numbering**: Entry numbers are assigned sequentially starting from 1
- **Automatic Increment**: System fetches the highest existing entry number and adds 1
- **Real-time Display**: Users can see the entry number that will be assigned before creating the transaction
- **Database Query**: `SELECT MAX(entry_no) FROM transactions` equivalent logic used

**Implementation Details**:
- **Service Method**: `OrderService.getNextEntryNumber()` provides the next available entry number
- **UI Display**: Entry number shown in a highlighted blue container in the selected item information
- **Auto-refresh**: Entry number automatically refreshes after successful transaction creation
- **Error Handling**: Defaults to entry number 1 if database query fails

## Manual Model Input Enhancement

The stock-in feature has been enhanced to use manual model input instead of automatic extraction:

**Previous Behavior**:
- Model was automatically extracted from serial number using pattern matching
- Example: "65M6APRO-244H90171-000011" → "65M6APRO"
- Limited flexibility and potential for extraction errors

**Current Behavior**:
- **Manual Input**: Users manually enter the model in a dedicated input field
- **Better Accuracy**: Eliminates extraction errors and supports any model format
- **Validation**: Model field is required and validated before submission
- **Flexibility**: Supports models that don't follow standard serial number patterns

**Implementation Details**:
- **UI Field**: Added model input field between equipment category and size fields
- **Validation**: Required field with proper error messages
- **Optional Size**: Size field is now optional to accommodate equipment without size specifications
- **Database Storage**: Model stored in both inventory and transaction records, size stored as empty string if not provided
- **Service Update**: `StockService.stockInItem()` now accepts manual model parameter and optional size parameter

## Multi-Item Order Enhancement

The stock-out feature has been enhanced to support multiple items per order instead of the previous single-item limitation:

**Previous Behavior**:
- One purchase order could only contain one item
- Users had to create separate POs for multiple items
- Limited efficiency for bulk orders

**Current Behavior**:
- **Multiple Items**: Users can add multiple items to a single purchase order
- **Enhanced UI**: Selected items displayed in a comprehensive list with remove functionality
- **Batch Processing**: All items processed atomically using Firestore batch operations
- **Validation**: System validates all items are still available before creating the PO

**Implementation Details**:
- **UI Enhancement**: Search and add items individually, view selected items list with remove buttons
- **Service Method**: New `createMultiItemStockOutOrder()` method handles multiple transaction records
- **Data Structure**: Single PO record stores array of transaction IDs instead of duplicating item data
- **Atomicity**: Firestore batch operations ensure all-or-nothing transaction creation
- **Validation**: Pre-flight checks ensure all selected items are still available

**User Experience Flow**:
1. **Search Items**: Type to search available inventory items
2. **Add Items**: Tap on search results to add items to selection (default warranty: 1 year)
3. **Configure Warranties**: Set individual warranty type for each selected item using dropdown
4. **Review Selection**: View selected items list with details, warranty settings, and remove options
5. **Configure PO**: Set location and other PO details
6. **Save**: Create PO with all selected items and their individual warranty settings atomically
  'customer_dealer': String,
  'customer_client': String,
  'total_items': int,
  'total_quantity': int,
  'remarks': String?,
  'status': String, // 'Uploaded'
  'uploaded_by_uid': String,
  'uploaded_at': Timestamp,
  'created_at': Timestamp,
  'updated_by_uid': String?, // Set on replacement
  'updated_at': Timestamp? // Set on replacement
}
```

## Firebase Collections

### Collection Structure
- **users**: User profiles and authentication data
- **inventory**: Current inventory items with status
- **transactions**: Complete transaction history
- **orders**: Order documents with integrated invoice data

**Note**: The separate `invoices` collection has been removed. Invoice data is now stored directly in the `orders` collection, reducing complexity and improving data consistency.

### Security Rules
All collections implement role-based security rules:
- Read access: Authenticated users
- Write access: Admin users only
- User profile access: Own profile only
- **UI-Level Security**: Role-based menu options and button visibility
- **Inventory Management**: Edit/delete operations restricted to admin users only
- **Dynamic Permissions**: Real-time role checking with Consumer<AuthProvider> pattern

## Performance Considerations

### Batch Operations
- Use Firestore batch writes for multiple document operations
- Maximum 500 operations per batch
- Implement proper error handling for batch failures

### Query Optimization
- Use indexed queries for better performance
- Implement pagination for large datasets
- Cache frequently accessed data

### File Handling
- Validate file size and format before upload
- Use streaming for large file operations
- Implement proper cleanup for replaced files

## Testing

### Unit Testing
```dart
// Example service test
testWidgets('StockService.addStockIn should create inventory and transaction records', (tester) async {
  // Mock dependencies
  // Call service method
  // Verify results
});
```

### Integration Testing
- Test complete workflows end-to-end
- Verify database consistency
- Test error scenarios and recovery

### Manual Testing
- Test with various file types and sizes
- Verify role-based access controls
- Test concurrent user scenarios
