# Inventory Management System

A comprehensive Flutter-based inventory management application with Firebase backend, featuring role-based authentication, Excel data import, stock management, purchase order tracking, and invoice management with PDF support.

## 🎯 Current Status

**✅ PRODUCTION READY** - All core features implemented and tested

### Version 2.2.1 - Latest Updates (January 2026)
- ✅ **Inventory Report Overhaul**:
  - **Smart Location Resolution**: Eliminates "Unknown" locations by intelligently scanning full transaction history
  - **Data Normalization**: Automatically merges inconsistent category names (e.g., "Smart_Pen" → "Smart Pen") for accurate reporting
  - **User-Friendly CSV**: New export format with Executive Summary, Category Breakdown, and simplified headers
- ✅ **Invoice & Delivery UX**: Replaced standard dropdowns with **Searchable Dropdowns** for instant filtering by Order #, Dealer, or Client
- ✅ **Performance Boost**: Implemented lazy loading for order items, significantly reducing initial load time for Invoice and Delivery screens
- ✅ **Sales Report Responsive Design**: Optimized "Product Performance" layout to prevent overflow on smaller screens
- ✅ **Category Details Upgrade**:
  - Added "Demo Items" and "Returned Items" to status summary
  - Refined iconography: Cyan/Play for Demo, Red/Error for Returned to match system standards

### Version 2.2.0 - Updates (January 2026)
- ✅ **Update Reference Numbers**: Admin utility to edit Order and Demo numbers with duplicate validation
- ✅ **Advanced Reference Search**: Instant, case-insensitive, partial keyword search for orders and demos
- ✅ **Inventory Report Enhancements**: Added Demo and Returned items to summary, implemented responsive layout for web/mobile
- ✅ **Debug Mode Protection**: Restricted critical reference update tools to debug environment for safety
- ✅ **UI/UX Improvements**: Consistent card layouts and responsive grids in reporting screens

### Version 2.1.0 - Latest Updates (December 2025)
- ✅ **Authentication System**: Login, registration, role-based access control
- ✅ **Stock-In Operations**: Add inventory with QR scanning and batch processing
- ✅ **Stock-Out Operations**: Reserve items for purchase orders with smart search
- ✅ **Order Management**: Dual status system (invoice_status + delivery_status) for better workflow separation
- ✅ **Invoice Management**: Upload, view, replace PDF invoices with OCR text extraction
- ✅ **Delivery Order Management**: Dual PDF workflow (normal + signed delivery) with separate transaction creation
- ✅ **Demo Program**: Create demos, track expected returns, and process partial or full demo returns
- ✅ **Partial Demo Return**: Select specific items to return from demos, track remaining items, visual indicators for returned items
- ✅ **Image Upload Support**: Accept PDF, JPG, JPEG, and PNG formats for invoice and delivery orders (mobile & web)
- ✅ **AI-Powered OCR**: OpenRouter Gemini Flash integration for scanned PDFs and images with automatic data extraction
- ✅ **Monthly Inventory Activity**: Comprehensive monthly reporting with size and category breakdowns
- ✅ **Data Import**: Excel file processing for inventory and transaction data
- ✅ **User Management**: Admin controls for user roles and permissions
- ✅ **Performance Optimization**: Efficient queries and batch operations with caching
- ✅ **Error Handling**: Comprehensive error handling and user feedback
- ✅ **Architecture Improvements**: Dual status system, separate transaction audit trails, file type differentiation
- ✅ **UI/UX Fixes**: Color-coded status indicators, responsive dialogs, file name display accuracy
- ✅ **File Management**: Advanced file replacement, proper metadata tracking, Firebase Storage integration
- ✅ **Enhanced Security**: Admin-only edit/delete restrictions in inventory management
- ✅ **Improved User Interface**: Clean user dashboard without blue banner, mobile-optimized admin navigation

### Code Quality
- **83% improvement** in code quality (29 → 5 minor issues)
- Production-ready codebase with minimal linting warnings
- Comprehensive testing and validation completed
- **Recent Fixes**: Invoice replacement dropdown error resolved

## 🚀 Features

### Authentication System
- **User Registration & Login**: Email/password authentication with Firebase Auth
- **Role-Based Access Control (RBAC)**: Two user types with different permissions
  - **Admin**: Full access to all features including data modification
  - **User**: Read-only access to view inventory and transaction data
- **Secure Authentication Flow**: Users must manually sign in after registration
- **User Profile Management**: Display name, email, and role information stored in Firestore

### Data Management
- **Excel File Import**: Upload and process inventory and transaction data from Excel files
- **Date Format Conversion**: Automatic conversion of Excel serial dates to Firestore Timestamps
- **Real-time Database**: Firebase Firestore for scalable data storage
- **Data Validation**: Comprehensive validation during import process

### Stock Management
- **Stock-In Operations**: Add new inventory items with batch processing
- **Stock-Out Operations**: Reserve items for purchase orders with serial number tracking
- **Transaction Logging**: Complete audit trail of all stock movements
- **Serial Number Management**: Track individual items by unique serial numbers
- **Inventory Status Tracking**: Real-time status updates (Active, Reserved, Sold)

### Order Management (Enhanced)
- **Order Creation**: Create orders with dealer and client information
- **Dual Status System**: Separate invoice_status (Reserved/Invoiced) and delivery_status (Pending/Issued/Delivered)
- **Status Workflow**: Reserved → Invoiced → Issued → Delivered with proper separation
- **Item Reservation**: Reserve specific serial numbers for orders
- **Comprehensive Order Details**: Store dealer, client, and item information with enhanced metadata

### Invoice Management (New)
- **PDF and Image Upload**: Support for PDF, JPG, JPEG, and PNG file formats (mobile & web)
- **AI-Powered OCR**: OpenRouter Gemini Flash integration for intelligent data extraction from scanned documents and images
- **Smart Fallback System**: Tries fast text extraction first, automatically uses AI for scanned/image-based documents
- **Confidence Scoring**: Built-in validation with user-friendly success messages
- **Invoice Replacement**: Replace existing invoices with new files and proper metadata updates
- **Firebase Storage Integration**: Secure cloud storage for files with file type differentiation
- **Invoice Information Display**: Comprehensive invoice details and metadata
- **Multi-platform Support**: Robust file viewing with fallback options
- **Format Validation**: Header-based validation for PDF (0x25504446), JPEG (0xFFD8FF), and PNG (0x89504E47)

### Delivery Order Management (New)
- **PDF and Image Upload**: Support for PDF, JPG, JPEG, and PNG file formats (mobile & web)
- **AI-Powered OCR**: OpenRouter Gemini Flash integration for intelligent data extraction from scanned documents and images
- **Smart Fallback System**: Tries fast text extraction first, automatically uses AI for scanned/image-based documents
- **Dual File Workflow**: Support for normal delivery order and signed delivery order files
- **Status Progression**: Normal file → "Issued" status, Signed file → "Delivered" status
- **Separate Transaction Creation**: Creates new "Delivered" transactions while preserving "Reserved" audit trail
- **File Type Differentiation**: Distinct file types ('delivery_order' vs 'signed_delivery_order') for proper organization
- **Shared Delivery Information**: Common delivery details (number, date, remarks) shared between both file types
- **Advanced File Management**: Replace functionality for both normal and signed delivery files
- **Color-coded Status Indicators**: Visual status differentiation (orange/green/blue/purple) across all screens

### Monthly Inventory Activity
- **Monthly Reporting**: Comprehensive monthly inventory activity reports with date range selection
- **Summary Analytics**: Total stock in, stock out, and cumulative remaining amounts
- **Size Breakdown**: Panel size analysis for items with meaningful dimensions (65 Inch, 75 Inch, etc.)
- **Category Breakdown**: Complete category analysis including Interactive Flat Panel and Others
- **Detailed Item Tracking**: Drill-down capability to view specific items in stock in/out operations
- **Hierarchical Organization**: Items grouped by category and size for easy navigation
- **Performance Optimized**: Smart caching and batch processing for fast loading with large datasets
- **Cumulative Calculations**: Accurate remaining amounts calculated from beginning until selected month

### User Interface
- **Modern Material Design**: Clean, responsive UI following Material Design principles
- **Loading Animations**: Professional loading indicators during operations
- **Error Handling**: User-friendly error messages and validation feedback
- **Role-Based Dashboards**: Admin users get comprehensive admin dashboard with integrated navigation, regular users get clean banner-free dashboard
- **Integrated Navigation**: Admin dashboard includes direct access to all core operations (Stock In/Out, Invoice, Delivery)
- **Mobile-Optimized Navigation**: Admin dashboard features popup menus with back buttons on mobile, side navigation on desktop
- **Clean User Interface**: User dashboard without blue banner for more immersive experience
- **Search Functionality**: Advanced search for serial numbers and items
- **Dropdown Interfaces**: Intuitive selection interfaces for complex data
- **Information Cards**: Professional display of detailed information
- **Security-Based UI**: Role-based menu options with admin-only edit/delete restrictions

## 🏗️ Architecture

### Project Structure
```
lib/
├── main.dart                    # App entry point with authentication routing
├── firebase_options.dart       # Firebase configuration
├── providers/
│   └── auth_provider.dart      # Authentication state management
├── services/
│   ├── auth_service.dart       # Firebase Auth operations
│   ├── data_upload_service.dart # Excel import and data processing
│   ├── stock_service.dart      # Stock management operations
│   ├── order_service.dart      # Order management with dual status system
│   ├── file_service.dart       # File upload/management with Firebase Storage
│   ├── invoice_ocr_service.dart # Invoice OCR with AI fallback
│   ├── llm_ocr_service.dart    # OpenRouter Gemini Flash AI OCR
│   ├── invoice_service.dart    # Invoice management with OCR support
│   ├── delivery_service.dart   # Delivery order management
│   └── monthly_inventory_service.dart # Monthly inventory activity reporting
├── utils/
│   └── image_utils.dart        # Image processing and compression utilities
└── screens/
    ├── login_screen.dart       # User authentication
    ├── register_screen.dart    # User registration
    ├── dashboard_screen.dart   # Main dashboard with auto-refresh
    ├── data_upload_screen.dart # Excel file upload
    ├── stock_in_screen.dart    # Add new inventory items
    ├── stock_out_screen.dart   # Reserve items for orders
    ├── invoice_screen.dart     # Invoice upload with OCR extraction
    ├── delivery_order_screen.dart # Dual PDF delivery management
    └── monthly_inventory_activity_screen.dart # Monthly inventory reporting
```

### Technology Stack
- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Auth, Firestore, Storage)
- **AI/ML**: OpenRouter API with Gemini Flash 2.0 for OCR
- **State Management**: Provider pattern
- **Data Processing**: spreadsheet_decoder for Excel files
- **File Management**: file_picker for file selection
- **PDF Handling**: url_launcher for PDF viewing, Syncfusion Flutter PDF for text extraction
- **HTTP Client**: http package for API requests
- **Environment**: flutter_dotenv for secure API key management
- **Authentication**: Firebase Authentication
- **Database**: Cloud Firestore
- **File Storage**: Firebase Storage

## 🔐 Authentication & Authorization

### User Roles

#### Admin Users
- Create, read, update, and delete inventory data
- Upload Excel files (inventory and transactions)
- Add new stock items manually (Stock-In operations)
- Create purchase orders and reserve items (Stock-Out operations)
- Upload, view, and replace PDF invoices
- Access monthly inventory activity reports with detailed analytics
- Clear database collections
- Full access to all application features
- Manage purchase order lifecycle
- Access to all stock management operations
- **Exclusive edit/delete permissions**: Only admins can edit or delete inventory items
- **Advanced inventory management**: Full CRUD operations on inventory data

#### Regular Users
- View inventory and transaction data
- Access dashboard and reports
- View purchase order information (read-only)
- View invoice information (read-only)
- Cannot modify any data
- Cannot upload files or create purchase orders
- Read-only access to all features
- **Restricted inventory access**: Can view inventory details and perform stock-out operations, but cannot edit or delete items

### Security Features
- **Firebase Authentication**: Industry-standard security
- **Role-based permissions**: Server-side validation in Firestore
- **Secure user profiles**: Encrypted storage of user information
- **Session management**: Automatic token refresh and validation

## 📊 Data Import System

### Supported File Formats
- **Excel files (.xlsx)**: Inventory and transaction data
- **Automatic date conversion**: Excel serial dates → Firestore Timestamps
- **Schema validation**: Ensures data integrity during import

### Import Process
1. **File Selection**: Choose Excel file from device
2. **Data Validation**: Verify schema and data types
3. **Date Conversion**: Convert Excel dates to proper timestamps
4. **Firestore Upload**: Batch upload to Firebase collections
5. **Success Confirmation**: User feedback on import status

## 🛠️ Setup & Installation

### Prerequisites
- Flutter SDK (latest stable version)
- Firebase project with Authentication and Firestore enabled
- Android Studio / VS Code with Flutter extensions

### Installation Steps

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd flutter_application
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Firebase Configuration**
   - Create a new Firebase project
   - Enable Authentication (Email/Password)
   - Enable Cloud Firestore
   - Download and add configuration files:
     - `android/app/google-services.json`
     - `ios/Runner/GoogleService-Info.plist`

4. **Run the application**
   ```bash
   flutter run
   ```

## 🔧 Configuration

### Firebase Setup
1. **Authentication**: Enable Email/Password provider
2. **Firestore Rules**: Configure security rules for role-based access
3. **Collections**: The app will automatically create required collections:
   - `users`: User profiles and roles
   - `inventory`: Product inventory data
   - `transactions`: Transaction history

### Environment Variables
- Firebase configuration is handled through `firebase_options.dart`
- **OpenRouter API Setup** (Required for AI-powered OCR):
  1. Get API key from [openrouter.ai](https://openrouter.ai/)
  2. Create `.env` file in project root:
     ```env
     OPENROUTER_API_KEY=sk-or-v1-your-api-key-here
     OPENROUTER_SITE_URL=https://yourdomain.com
     OPENROUTER_SITE_NAME=InventoryPro
     ```
  3. **Important**: Never commit `.env` file to version control (already in `.gitignore`)
  4. Use `.env.example` as template for required environment variables

## 📱 Usage

### First Time Setup
1. **Launch the app**: Opens to login screen
2. **Register new account**: Click "Create Account" and fill in details
3. **Choose role**: Select Admin or User during registration
4. **Sign in**: After registration, sign in with your credentials
5. **Access dashboard**: Admin users land on admin dashboard with integrated navigation and analytics, regular users get enhanced dashboard with core operations

### Admin Workflow
1. **Admin Dashboard**: Main landing page with all core operations and analytics
2. **Stock Management** (directly from dashboard):
   - Add new items through Stock-In screen
   - Create purchase orders through Stock-Out screen
   - Reserve specific serial numbers for orders
3. **Invoice Management**:
   - Upload PDF invoices for purchase orders
   - View existing invoices in external PDF viewers
   - Replace invoices when needed
4. **Monthly Inventory Reports**:
   - Access comprehensive monthly inventory activity reports
   - View summary analytics and detailed breakdowns
   - Analyze stock movements by size and category
   - Track cumulative inventory levels over time
5. **Monitor System**: View dashboard for system overview
6. **User Management**: Admins can see all system activity

### User Workflow
1. **Enhanced Dashboard**: Main landing page with personalized welcome and direct access to core operations
2. **Stock Management** (directly from dashboard):
   - Add new items through Stock-In screen
   - Create purchase orders through Stock-Out screen
3. **Invoice Management**: Upload and manage PDF invoices for purchase orders
4. **Delivery Tracking**: Monitor delivery status (coming soon)
5. **Streamlined Navigation**: All core operations accessible from main dashboard

## 🧪 Testing

### Running Tests
```bash
flutter test
```

### Test Coverage
- Widget tests for UI components
- Unit tests for business logic
- Integration tests for authentication flow

## 🚀 Deployment

### Android
```bash
flutter build apk --release
```

### iOS
```bash
flutter build ios --release
```

## 📋 Data Schemas

### Inventory Schema
- Product information with Excel date conversion
- Automatic timestamp generation
- Validation for required fields
- Serial number tracking
- Status management (Active, Reserved, Sold)

### Transaction Schema
- Transaction history with proper date handling
- User attribution and timestamps
- Audit trail for all changes
- Stock-In and Stock-Out operations
- Order references

### Order Schema
- Order number and status tracking
- Dealer and client information
- Item reservations with serial numbers
- Creation and update timestamps
- Status progression (Pending → Invoiced)

### Invoice Schema
- PDF file storage and metadata
- Invoice number and date tracking
- Purchase order associations
- File size and format information
- Upload and replacement history

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support and questions:
- Check the documentation
- Review Firebase console for backend issues
- Verify authentication configuration
- Check Firestore security rules

## 🔄 Version History

### v2.2.1 (January 2026)
- ✅ **Inventory Report Smart Logic**: Implemented intelligent fallback logic that scans entire transaction history to resolve "Unknown" locations when current location is missing
- ✅ **Data Normalization Engine**: Added automatic normalization in ReportService to group inconsistent category names (case/underscore variations) into single unified entries
- ✅ **Executive CSV Reports**: Completely redesigned Inventory CSV export to include dashboard-style Executive Summary and Category Breakdown tables before the detailed list
- ✅ **Searchable Order Selection**: Integrated `dropdown_search` to enable real-time filtering of orders by ID, Client, or Dealer in Invoice and Delivery screens
- ✅ **Optimized Data Loading**: Switched to lazy-loading pattern for order item details, preventing UI threads from locking up when loading large order lists
- ✅ **Responsive Sales Report**: Fixed RenderFlex overflow issues in Sales Report by implementing responsive layout builder that stacks widgets on narrow screens
- ✅ **Enhanced Category Analytics**: Updated Category Details screen to explicitly track and display "Demo" and "Returned" items with distinct color coding (Cyan/Red) to match global design system

### v2.2.0 (January 2026)
- ✅ **Update Reference Screen**: New admin tool to correct Order and Demo numbers (e.g., from TEMP-001 to OFFICIAL-001)
- ✅ **Smart Search Logic**: Implemented client-side fuzzy search for reference updates (instant, case-insensitive)
- ✅ **Inventory Report Upgrade**:
  - Added "Demo Items" and "Returned Items" to summary cards
  - Consolidated summary cards into a unified, responsive grid (2-col mobile, 6-col web)
  - Aligned card heights for consistent UI
- ✅ **Safety Controls**: Restricted "Update References" navigation option to Debug Mode only to prevent accidental changes in production
- ✅ **Data Integrity**: Service-level validation to ensure new reference numbers are unique before updating
- ✅ **Performance**: Optimized report generation to include demo/return counts in single pass

### v2.1.3 (Current - December 2025)
- ✅ **AI-Powered OCR Integration**: OpenRouter Gemini Flash 2.0 for intelligent document data extraction
- ✅ **Enhanced Image Support**: Full JPG/PNG support for invoice and delivery order uploads
- ✅ **Smart OCR Fallback**: Automatic detection of scanned PDFs with AI fallback for optimal cost efficiency
- ✅ **Platform-Agnostic Design**: PDFs sent directly to AI on all platforms (web, mobile, desktop)
- ✅ **User-Friendly Messages**: Simplified success messages without technical jargon
- ✅ **Secure API Configuration**: Environment-based API key management with .gitignore protection
- ✅ **Cost-Effective Processing**: ~$0.0002-$0.0005 per scanned document with free text extraction for digital PDFs

### v2.1.2 (December 2025)
- ✅ **Inventory Status Refactoring - Complete**: Unified all inventory reporting to use `inventory.status` as single source of truth
- ✅ **Performance Optimization**: Monthly Inventory screen loading improved by 93% (60+ seconds → 2-5 seconds)
- ✅ **Data Accuracy Fixes**: Resolved 35-item discrepancy in Monthly Inventory reports (244 → 209)
- ✅ **Code Simplification**: Removed 240 lines of complex transaction-based logic across 7 functions
- ✅ **Batch Query Optimization**: Eliminated 100+ individual Firestore queries per Stock Out operation
- ✅ **Widget Lifecycle Fixes**: Added mounted checks to prevent setState after dispose errors
- ✅ **Unified Calculation Approach**: Dashboard, Category, Reports, and Monthly Inventory now use consistent direct status queries

### v2.1.1 (December 2025)

- ✅ **Change Password Feature**: Secure self-service password change functionality for all users with re-authentication
- ✅ **Enhanced Email Validation**: Updated validation logic to support top-level domains with 2+ characters (e.g., .technology, .consulting)
- ✅ **Advanced Item Return Search**:
  - Split Dealer and Client search into separate dedicated fields
  - Added role indicators ("Recorded as: Dealer/Client") in search dropdowns
  - smart serial number filtering combining results from both entities
- ✅ **Admin Dashboard Improvements**: Replaced Logout button with Profile button for direct access to user settings and password management
- ✅ **Inventory Status Synchronization**: Improved status syncing between transaction and inventory records during returns and stock-outs

### v2.1.0 (December 2025)
- ✅ **Dual Status System Architecture**: Implemented separate invoice_status and delivery_status fields for better workflow separation
- ✅ **Delivery Order Management**: Complete dual PDF workflow supporting normal delivery order and signed delivery order uploads
- ✅ **Enhanced Transaction System**: Creates separate "Delivered" transactions while preserving "Reserved" audit trail
- ✅ **Advanced File Management**: New FileService with proper file type differentiation ('invoice', 'delivery_order', 'signed_delivery_order')
- ✅ **OCR Text Extraction**: Automatic extraction of invoice numbers and dates from PDF files using Syncfusion Flutter PDF
- ✅ **Color-coded Status Indicators**: Visual status differentiation with orange/green/blue/purple across all screens
- ✅ **Auto-refresh Dashboard**: Smart background data checking with efficient UI updates every 10 seconds
- ✅ **Cross-screen Data Synchronization**: Proper data refresh when navigating between screens
- ✅ **File Name Display Accuracy**: Real-time file information updates after file replacements
- ✅ **Responsive Dialog Design**: Improved UI layouts with proper overflow handling using Flexible widgets
- ✅ **Database Migration System**: Seamless migration from single status to dual status system
- ✅ **Development Tools**: Enhanced delete functionality for delivery data testing and development
- ✅ **Architectural Improvements**: Separate file references with shared delivery information for optimal data organization
- ✅ **Enhanced Security Model**: Admin-only edit/delete restrictions in inventory management with role-based UI controls
- ✅ **Improved User Dashboard**: Removed blue banner for cleaner interface, integrated header with user menu in body content
- ✅ **Mobile Navigation Enhancement**: Admin dashboard popup menus with back buttons on mobile, hidden on desktop
- ✅ **Key Metrics Optimization**: Fixed overflow errors, dynamic button text based on actual discrepancy values

### v2.0.22
- ✅ **Monthly Inventory Activity Critical Fixes**: Resolved Flutter rendering errors that prevented complete size breakdown display
- ✅ **Border Rendering Conflict Resolution**: Fixed hairline border + borderRadius conflict causing rendering exceptions
- ✅ **Complete Panel Size Display**: All panel sizes (65", 75", 86", 98") now display correctly in size breakdown table
- ✅ **Data Integrity Verification**: Confirmed remaining item counts match summary totals across all size categories
- ✅ **UI Stability Enhancement**: Eliminated Flutter rendering exceptions that were blocking last row visibility
- ✅ **Documentation Updates**: Updated all markdown documentation to reflect latest fixes and improvements

### v2.0.21
- ✅ **Monthly Inventory Activity UI Fixes**: Resolved Flutter rendering errors and display issues in size breakdown table
- ✅ **Border Styling Fix**: Fixed hairline border + borderRadius conflict that was preventing last row display
- ✅ **Complete Size Breakdown Display**: All panel sizes (65", 75", 86", 98") now display correctly without missing rows
- ✅ **Responsive Table Layout**: Improved table layout with proper flex ratios and no horizontal scrolling required
- ✅ **Data Accuracy Verification**: Confirmed all remaining item counts match summary totals (45 items total)

### v2.0.20
- ✅ **Monthly Inventory Activity Feature**: Comprehensive monthly reporting system with advanced analytics and performance optimization
- ✅ **Hierarchical Data Organization**: Stock in/out items grouped by category and size for improved navigation and clarity
- ✅ **Smart Data Separation**: Separate calculation methods for summary (all items) vs size breakdown (meaningful sizes only)
- ✅ **Performance Optimization**: Implemented caching, batch processing, and pagination for fast loading with large datasets
- ✅ **Cumulative Calculations**: Accurate remaining amounts calculated from beginning until selected month
- ✅ **Category & Size Breakdowns**: Dynamic category analysis and size-based reporting with proper data filtering
- ✅ **Detailed Item Tracking**: Drill-down capability to view specific items in tabbed interface
- ✅ **Data Quality Improvements**: Fixed blank rows in size breakdown by excluding "Others" category items without meaningful sizes

### v2.0.19
- ✅ **Admin Dashboard as Main Page**: Admin users now land directly on the admin dashboard instead of regular dashboard
- ✅ **Enhanced User Dashboard**: Regular users get improved dashboard with welcome section, descriptions, and consistent styling
- ✅ **Integrated Core Navigation**: Added Stock In, Stock Out, Invoice, and Delivery Order buttons directly to both admin and user dashboards
- ✅ **Unified User Experience**: Both admin and regular users now have streamlined workflows with all core operations accessible from main interface
- ✅ **Personalized Welcome**: Added welcome sections with user names and helpful descriptions for better user experience
- ✅ **Fixed Logout Navigation**: Fixed logout functionality to properly navigate to login screen for both admin and regular users
- ✅ **Status System Fix**: Fixed PO and transaction status mismatch where invoice uploads incorrectly changed transaction status to 'Invoiced'
- ✅ **Data Migration Utility**: Added admin utility to fix existing transactions with incorrect 'Invoiced' status back to 'Reserved'

### v2.0.18
- ✅ **Sales Report Screen**: Comprehensive sales analytics with purchase order tracking, customer insights, location analysis, and time-based filtering
- ✅ **Inventory Report Screen**: Detailed inventory analytics with stock levels, movement history, category breakdown, aging analysis, and status tracking
- ✅ **Report Service**: Backend service for advanced data processing, filtering, and aggregation of sales and inventory data
- ✅ **CSV Export Functionality**: Export sales and inventory reports to CSV files for external analysis and record-keeping
- ✅ **Report Navigation**: Integrated report access through admin dashboard with proper role-based access control
- ✅ **Fixed Report Overflow Issues**: Resolved text overflow issues in both sales and inventory report summary cards by adjusting aspect ratio and implementing responsive text sizing

### v2.0.17
- ✅ **Admin Dashboard with Analytics**: Comprehensive admin dashboard with sales summaries, inventory analytics, recent activity, and key metrics
- ✅ **Fixed Dashboard Analytics**: Corrected inventory statistics calculation to properly show active vs stocked out items
- ✅ **Fixed Monthly Stats & Recent Activity**: Corrected timestamp field references from 'created_at' to 'uploaded_at' to match actual transaction data structure
- ✅ **Delivery Order Preserved**: Maintained delivery order placeholder for all users while adding admin dashboard for admin users
- ✅ **QR Code Scanning in Stock-Out**: Added QR code scanning functionality to stock-out page for quick serial number input
- ✅ **QR Code Testing Enhancement**: Added image upload functionality to QR scanner for testing QR codes from gallery images
- ✅ **Simplified User Registration**: Removed role selection from signup screen - all new users are automatically assigned 'user' role for security
- ✅ **Invoice Field Mapping Fix**: Fixed "Uploaded At" field showing "N/A" by correcting field name mapping from 'uploaded_at' to 'invoice_uploaded_at'
- ✅ **Invoice Dropdown Architecture Fix**: Completely refactored invoice screen dropdown to use String IDs instead of Map objects, eliminating all reference comparison issues
- ✅ **Transaction ID Race Condition Fix**: Fixed duplicate transaction ID issue in multi-item purchase orders by implementing sequential ID generation
- ✅ **Individual Item Warranty Types**: Enhanced multi-item purchase orders to support different warranty types per item (1 Year, 1+2 Year, 1+3 Year)
- ✅ **Multi-Item Purchase Orders**: Enhanced stock-out flow to support multiple items per purchase order instead of single item limitation
- ✅ **Optional Size Field**: Made size field optional in stock-in page to accommodate equipment categories that don't require size specifications
- ✅ **Manual Model Input**: Added manual model input field to stock-in page, removing automatic extraction from serial number for better accuracy and flexibility
- ✅ **Entry Number Tracking**: Added automatic entry number generation and display in stock-out feature, fetching latest entry number from transaction table and incrementing by 1
- ✅ **Warranty Management Enhancement**: Added warranty type dropdown to stock-out feature with automatic warranty period calculation (1 Year = 1 year, 1+2 Year = 3 years)
- ✅ **Location Selection Enhancement**: Added Malaysian states dropdown to stock-out feature with proper state abbreviations (e.g., Selangor → SGR)
- ✅ **Enhanced PO Details Display**: Replaced generic "Total Items" field with detailed item information showing serial numbers, categories, models, sizes, batches, and transaction IDs
- ✅ **Batch Information Integration**: Fixed batch data fetching by retrieving accurate batch information from inventory table instead of transaction records
- ✅ **Order Simplification**: Refactored order storage to use transaction ID references instead of duplicating item details, reducing data redundancy
- ✅ **Invoice Storage Refactoring**: Eliminated separate invoice collection, integrated all invoice data directly into orders for simplified architecture
- ✅ **Dropdown Bug Fix**: Fixed critical assertion error in invoice replacement feature by ensuring proper object reference equality

### v2.0.0
- ✅ Complete authentication system with RBAC
- ✅ Excel data import with date conversion
- ✅ Firebase integration (Auth + Firestore + Storage)
- ✅ Role-based UI and permissions
- ✅ Professional loading animations
- ✅ Comprehensive error handling
- ✅ **Stock Management System**:
  - Stock-In operations with batch processing
  - Stock-Out operations with serial number reservation
  - Real-time inventory status tracking
  - Transaction logging and audit trails
- ✅ **Purchase Order Management**:
  - PO creation and status tracking
  - Dealer and client information management
  - Item reservation system
  - Status progression workflow
- ✅ **Invoice Management System**:
  - PDF invoice upload and storage
  - Multi-platform PDF viewing with fallbacks
  - Invoice replacement functionality
  - Comprehensive invoice metadata tracking
  - Firebase Storage integration
- ✅ **Advanced UI Features**:
  - Search-based serial number selection
  - Information cards for detailed data display
  - Dropdown interfaces for complex selections
  - Professional loading states and error handling
- ✅ **Performance Optimizations**:
  - Batch database operations
  - Efficient query patterns
  - Memory management improvements
  - Optimized file handling

### v1.0.0 (Previous)
- ✅ Basic authentication system with RBAC
- ✅ Excel data import with date conversion
- ✅ Firebase integration (Auth + Firestore)
- ✅ Role-based UI and permissions
- ✅ Professional loading animations
- ✅ Comprehensive error handling
