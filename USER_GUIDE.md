# InventoryPro - Complete User Guide

## 📱 Overview

InventoryPro is a comprehensive Flutter-based inventory management system with Firebase backend, designed for efficient stock management, order processing, and business analytics. The application supports both mobile and desktop/web platforms with role-based access control.

## 🔐 Getting Started

### User Registration & Login

1. **First Time Setup**
   - Open the InventoryPro application
   - Tap **"Register"** to create a new account
   - Fill in your details:
     - **Display Name**: Your full name
     - **Email**: Valid email address
     - **Password**: Secure password (minimum 6 characters)
     - **Role**: Select either "Admin" or "User"
   - Tap **"Register"** to create your account
   - You'll be redirected to the login screen

2. **Logging In**
   - Enter your registered email and password
   - Tap **"Login"** to access the application
   - The system will redirect you to the appropriate dashboard based on your role

### User Roles & Permissions

#### 👤 Regular Users
- **Read-only access** to inventory and transaction data
- View dashboard analytics and reports
- Access purchase order information (view only)
- View invoice information (view only)
- Cannot modify data or upload files

#### 👑 Admin Users
- **Full access** to all application features
- Create, read, update, and delete inventory data
- Upload Excel files for bulk data import
- Manage stock operations (Stock-In/Stock-Out)
- Upload and manage PDF invoices with OCR support
- Access comprehensive reporting and analytics
- Manage user accounts and system settings
- Clear database collections and perform maintenance

## 🏠 Dashboard Navigation

### User Dashboard
The user dashboard provides a clean, grid-based interface with:
- **Welcome Section**: Personalized greeting with user information
- **Quick Actions**: Direct access to core operations
  - Stock In: Add new inventory items
  - Order: Create purchase orders
  - Invoice: View invoice information
  - Delivery: Track delivery status
- **Profile Menu**: Access user profile and logout options

### Admin Dashboard
The admin dashboard features an adaptive interface:

#### Mobile View (≤768px width)
- **Bottom Navigation Bar** with popup menus:
  - **Actions**: Core operations (Stock In, Order, Invoice, Delivery)
  - **Manage**: Data management (Inventory, Users, File History)
  - **Reports**: Analytics and reporting tools
  - **Analytics**: Key metrics and detailed analytics

#### Desktop View (>768px width)
- **Side Navigation Panel** with organized menu sections
- **Popup Menus**: Positioned beside navigation buttons for better UX
- **Quick Actions Bar**: Horizontal bar with 4 most-used functions
- **Key Metrics Overview**: Real-time analytics display
- **Recent Activity**: Live transaction monitoring

## 📦 Core Features

### Stock Management

#### Stock In (Adding New Items)
1. Navigate to **Stock In** from dashboard or navigation menu
2. Fill in the modern form with required information:
   - **Serial Number**: Unique identifier (required)
   - **Equipment Category**: Product category (required)
   - **Model**: Product model (required)
   - **Size**: Product size (optional)
   - **Batch**: Batch number (required)
   - **Remarks**: Additional notes (optional)
3. Use **QR Scanner** button to scan serial numbers (mobile only)
4. Tap **"Save Item"** to add to inventory
5. System automatically creates transaction record

#### Stock Out (Creating Orders)
1. Navigate to **Order** from dashboard or navigation menu
2. Fill in order information:
   - **Order Number**: Unique PO number (required)
   - **Dealer Name**: Dealer information (required)
   - **Client Name**: End client (optional)
   - **Location**: Select Malaysian state (required)
3. Search and select items:
   - Use search field to find items by serial number, category, or model
   - Tap **QR Scanner** to scan item codes
   - Select items from search results
   - Set warranty type for each selected item
4. Review selected items and tap **"Save Order"**
5. System reserves items and updates inventory status

### Invoice Management

#### Uploading Invoices
1. Navigate to **Invoice** from dashboard or navigation menu
2. Select a purchase order from the dropdown
3. View order details and current status
4. For pending orders:
   - Tap **"Choose PDF File"** to select invoice
   - System automatically extracts invoice number and date using OCR
   - Review extracted information and edit if needed
   - Tap **"Upload Invoice"** to save
5. Order status automatically updates to "Invoiced"

#### Managing Existing Invoices
- **View**: Tap "View" button to open PDF in external viewer
- **Replace**: Tap "Replace" to upload a new version
- **Download**: Access invoice files from Firebase Storage

### Delivery Order Management

#### Two-Stage Delivery Process
1. **Stage 1 - Delivery Order Upload**:
   - Upload delivery order PDF
   - Order status updates to "Issued"
2. **Stage 2 - Signed Delivery Upload**:
   - Upload signed delivery confirmation
   - Order status updates to "Delivered"

#### File Management
- All delivery files stored in Firebase Storage
- Automatic status updates based on file uploads
- Version history tracking for all documents

## 📊 Data Management & Import

### Excel File Import (Admin Only)
1. Navigate to **Data Upload** from admin navigation menu
2. Choose import type:
   - **Inventory Data**: Bulk import inventory items
   - **Transaction Data**: Import transaction history
3. Select Excel file (.xlsx format)
4. System validates data format and shows preview
5. Confirm import to add data to database
6. View import summary and any error reports

### Supported Excel Formats

#### Inventory Data Columns
- Serial Number (required)
- Equipment Category (required)
- Model (required)
- Size (optional)
- Batch (required)
- Current Status (Active/Reserved/Sold)
- Location
- Date Added
- Remarks

#### Transaction Data Columns
- Transaction ID
- Serial Number
- Transaction Type (Stock_In/Stock_Out)
- Equipment Category
- Model
- Size
- Batch
- Date
- User
- Order Reference
- Remarks

## 📈 Reporting & Analytics

### Key Metrics Dashboard
Access comprehensive analytics through **Key Metrics** screen:

#### Overview Statistics
- **Total Items**: Complete inventory count
- **Active Stock**: Available items for sale
- **Total Orders**: All purchase orders created
- **Total Transactions**: All stock movements

#### Orders & Sales Analysis
- **Invoiced Orders**: Orders with uploaded invoices
- **Pending Orders**: Orders awaiting invoice
- **Issued Orders**: Orders with delivery documentation
- **Order Status Distribution**: Visual breakdown of order pipeline

#### Monthly Activity Summary
- **Stock In**: Items added this month
- **Stock Out**: Items reserved/sold this month
- **Net Movement**: Overall inventory change
- **Transaction Trends**: Monthly comparison data

### Inventory Reports
1. Navigate to **Inventory Report** from Reports menu
2. View paginated inventory data (20 items per page)
3. Use pagination controls:
   - **Previous/Next**: Navigate between pages
   - **Page Input**: Click page number to jump to specific page
4. Export data or print reports as needed

### Sales Reports
- Transaction history analysis
- Revenue tracking and trends
- Customer and dealer analytics
- Performance metrics by time period

### Monthly Inventory Activity
1. Access through **Monthly Activity** in Reports menu
2. Select month and year for analysis
3. View comprehensive breakdown:
   - **Summary Statistics**: Total movements and trends
   - **Category Analysis**: Breakdown by equipment type
   - **Size Distribution**: Analysis by product size (IFP panels vs accessories)
   - **Cumulative Tracking**: Month-over-month inventory levels
   - **Detailed Transaction List**: All movements with full details

## 🔧 Advanced Features (Admin Only)

### Inventory Management
1. Navigate to **Inventory Management** from Manage menu
2. Features include:
   - **Advanced Search**: Filter by category, status, location, size
   - **Bulk Operations**: Select multiple items for batch actions
   - **Real-time Updates**: Live inventory status monitoring
   - **Detailed Item View**: Complete item history and information
   - **Status Management**: Update item status and location
   - **Edit Capabilities**: Modify item details and specifications

### User Management
1. Access **User Management** from admin navigation
2. Capabilities:
   - **View All Users**: Complete user directory with roles
   - **Create New Users**: Add users with specific roles
   - **Role Management**: Assign Admin or User permissions
   - **User Statistics**: Active users and role distribution
   - **Search & Filter**: Find users by name, email, or role
   - **Account Status**: Monitor user activity and access

### File History & Version Control
1. Navigate to **File History** from Manage menu
2. Track all uploaded files:
   - **Invoice Files**: All uploaded invoices with versions
   - **Delivery Orders**: Delivery documentation history
   - **Excel Imports**: Data import file history
   - **Version Tracking**: See file replacement history
   - **Storage Management**: Monitor Firebase Storage usage

### Order Cancellation & Inventory Restoration
1. Access **Cancel Order** from admin navigation
2. Features:
   - **Order Search**: Find orders by number or status
   - **Cancellation Process**: Cancel orders and restore inventory
   - **Inventory Restoration**: Automatically return items to active status
   - **Audit Trail**: Track all cancellation activities
   - **Bulk Cancellation**: Cancel multiple orders simultaneously

## 🔍 Search & Filter Capabilities

### Global Search Features
- **Serial Number Search**: Find items by exact or partial serial numbers
- **Category Filtering**: Filter by equipment categories
- **Model Search**: Search by product models
- **Status Filtering**: Filter by Active, Reserved, or Sold status
- **Location Filtering**: Filter by Malaysian state locations
- **Date Range Filtering**: Search by date ranges
- **Batch Number Search**: Find items by batch numbers

### Advanced Filtering Options
- **Multi-criteria Search**: Combine multiple filters
- **Real-time Results**: Instant search results as you type
- **Saved Searches**: Save frequently used search criteria
- **Export Filtered Results**: Export search results to Excel
- **Pagination Support**: Navigate through large result sets

## 📱 Mobile-Specific Features

### QR Code Scanning
- **Built-in Scanner**: Integrated QR code reader
- **Serial Number Input**: Automatically populate serial number fields
- **Batch Scanning**: Scan multiple items quickly
- **Error Handling**: Validation and error correction
- **Platform Support**: Available on mobile devices only

### Touch-Optimized Interface
- **Gesture Navigation**: Swipe and tap interactions
- **Responsive Design**: Adapts to different screen sizes
- **Touch-friendly Buttons**: Large, accessible touch targets
- **Pull-to-Refresh**: Refresh data with pull gesture
- **Haptic Feedback**: Touch response for better UX

## 🖥️ Desktop/Web Features

### Enhanced Navigation
- **Side Navigation Panel**: Persistent navigation menu
- **Keyboard Shortcuts**: Quick access to common functions
- **Multi-window Support**: Open multiple screens simultaneously
- **Drag & Drop**: File upload via drag and drop
- **Right-click Menus**: Context-sensitive options

### Advanced Data Management
- **Bulk Selection**: Select multiple items with checkboxes
- **Keyboard Navigation**: Navigate with arrow keys and shortcuts
- **Advanced Sorting**: Multi-column sorting capabilities
- **Column Customization**: Show/hide columns as needed
- **Export Options**: Multiple export formats available

## 🔧 Technical Features

### OCR (Optical Character Recognition)
- **Automatic Data Extraction**: Extract invoice numbers and dates from PDFs
- **Google ML Kit Integration**: Advanced text recognition
- **Manual Override**: Edit extracted data if needed
- **Multiple Language Support**: Recognize text in various languages
- **Error Correction**: Validate and correct extracted data

### Real-time Updates
- **Live Data Sync**: Real-time database synchronization
- **Auto-refresh**: Automatic data updates every 5 seconds
- **Push Notifications**: Instant updates for important changes
- **Conflict Resolution**: Handle concurrent data modifications
- **Offline Support**: Limited offline functionality

### Data Security & Backup
- **Firebase Security Rules**: Server-side data protection
- **Role-based Access**: Granular permission system
- **Automatic Backups**: Regular data backups to Firebase
- **Audit Trails**: Complete activity logging
- **Data Encryption**: Encrypted data transmission and storage

## 🚨 Troubleshooting

### Common Issues & Solutions

#### Login Problems
- **Forgot Password**: Use password reset feature
- **Account Locked**: Contact administrator
- **Role Issues**: Verify role assignment with admin
- **Network Problems**: Check internet connection

#### File Upload Issues
- **File Size Limits**: Maximum 10MB per file
- **Supported Formats**: PDF for invoices, XLSX for data
- **Network Timeout**: Retry upload with stable connection
- **Storage Quota**: Contact admin if storage is full

#### Search & Filter Problems
- **No Results**: Check spelling and filter criteria
- **Slow Performance**: Clear filters and try again
- **Missing Data**: Refresh the screen or check permissions
- **Export Errors**: Verify data selection and try again

#### Mobile-Specific Issues
- **QR Scanner Not Working**: Check camera permissions
- **App Crashes**: Update to latest version
- **Slow Performance**: Close other apps and restart
- **Sync Issues**: Check internet connection and retry

### Getting Help
- **In-App Support**: Use help buttons throughout the application
- **Admin Contact**: Reach out to system administrators
- **Documentation**: Refer to this user guide
- **Training Resources**: Access video tutorials and guides

## 📋 Best Practices

### Data Entry Guidelines
- **Consistent Naming**: Use standardized naming conventions
- **Complete Information**: Fill all required fields
- **Regular Updates**: Keep inventory status current
- **Batch Processing**: Use bulk operations for efficiency
- **Data Validation**: Review data before submission

### File Management
- **Organized Naming**: Use clear, descriptive file names
- **Version Control**: Track file versions and changes
- **Regular Cleanup**: Remove outdated files periodically
- **Backup Strategy**: Maintain local backups of important files
- **Access Control**: Limit file access to authorized users

### Security Best Practices
- **Strong Passwords**: Use complex, unique passwords
- **Regular Updates**: Keep login credentials current
- **Secure Access**: Log out when finished
- **Permission Management**: Request only necessary permissions
- **Data Privacy**: Handle sensitive information appropriately

## 🔄 System Maintenance

### Regular Tasks (Admin)
- **Database Cleanup**: Remove outdated records periodically
- **User Management**: Review and update user accounts
- **File Organization**: Organize and archive old files
- **Performance Monitoring**: Check system performance metrics
- **Backup Verification**: Ensure backups are working properly

### Monthly Reviews
- **Inventory Audit**: Verify physical vs. system inventory
- **Transaction Review**: Check transaction accuracy
- **User Activity**: Monitor user access and activity
- **System Updates**: Apply software updates as needed
- **Performance Analysis**: Review system performance reports

---

## 📞 Support & Contact

For technical support, feature requests, or training assistance, please contact your system administrator or IT support team.

**Application Version**: InventoryPro v1.0
**Last Updated**: November 2024
**Platform Support**: iOS, Android, Web, Desktop

