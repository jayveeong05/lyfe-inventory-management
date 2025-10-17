# Development Guide

## Overview

This guide provides comprehensive information for developers working on the Inventory Management System. It covers code structure, development practices, testing strategies, and contribution guidelines.

## Project Structure

### Directory Organization
```
lib/
├── main.dart                    # Application entry point
├── firebase_options.dart        # Firebase configuration
├── providers/                   # State management
│   └── auth_provider.dart      # Authentication state
├── services/                    # Business logic services
│   ├── auth_service.dart       # Authentication operations
│   ├── data_upload_service.dart # Data import/export
│   ├── stock_service.dart      # Stock management operations
│   ├── purchase_order_service.dart # Purchase order operations
│   ├── invoice_service.dart    # Invoice management with PDF support
│   └── monthly_inventory_service.dart # Monthly inventory reporting
├── screens/                     # UI screens
│   ├── login_screen.dart       # Authentication UI
│   ├── register_screen.dart    # User registration
│   ├── dashboard_screen.dart   # Main dashboard
│   ├── data_upload_screen.dart # File upload interface
│   ├── stock_in_screen.dart    # Add new inventory items
│   ├── stock_out_screen.dart   # Reserve items for purchase orders
│   ├── invoice_screen.dart     # Invoice upload and management
│   └── monthly_inventory_activity_screen.dart # Monthly inventory reporting
└── models/                      # Data models (future)
    ├── user_model.dart         # User data structure
    ├── inventory_model.dart    # Inventory data structure
    ├── transaction_model.dart  # Transaction data structure
    ├── purchase_order_model.dart # Purchase order data structure
    └── invoice_model.dart      # Invoice data structure
```

### Architecture Patterns

#### 1. Provider Pattern (State Management)
```dart
// Provider setup in main.dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    // Add more providers as needed
  ],
  child: MyApp(),
)
```

#### 2. Service Layer Pattern
```dart
// Service classes handle business logic
class AuthService {
  // Authentication operations
  Future<UserCredential?> signInWithEmailAndPassword(String email, String password);
  Future<UserCredential?> registerWithEmailAndPassword(/* params */);
}

class StockService {
  // Stock management operations
  Future<Map<String, dynamic>> addStockIn(/* params */);
  Future<Map<String, dynamic>> createStockOut(/* params */);
}

class InvoiceService {
  // Invoice management with PDF support
  Future<Map<String, dynamic>> uploadInvoice(/* params */);
  Future<Map<String, dynamic>> replaceInvoice(/* params */);
}
```

#### 3. Screen-Service Separation
- **Screens**: Handle UI and user interactions
- **Services**: Handle business logic and data operations
- **Providers**: Manage application state
- **Dependency Injection**: Services passed through constructors for proper state management

## Code Standards

### Dart Style Guide
Follow the official [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style):

```dart
// Good: Use lowerCamelCase for variables and functions
String userName = 'john_doe';
void calculateTotal() { }

// Good: Use UpperCamelCase for classes
class UserProfile { }

// Good: Use descriptive names
bool isUserAuthenticated = true;
List<String> availableProducts = [];
```

### File Naming Conventions
- **Screens**: `*_screen.dart` (e.g., `login_screen.dart`)
- **Services**: `*_service.dart` (e.g., `auth_service.dart`)
- **Providers**: `*_provider.dart` (e.g., `auth_provider.dart`)
- **Models**: `*_model.dart` (e.g., `user_model.dart`)
- **Utilities**: `*_utils.dart` (e.g., `date_utils.dart`)

### Code Organization
```dart
// Import order: Dart SDK, Flutter, Third-party, Local
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../providers/auth_provider.dart';
```

## Development Workflow

### Git Workflow
```bash
# Create feature branch
git checkout -b feature/user-authentication

# Make changes and commit
git add .
git commit -m "feat: implement user authentication system"

# Push and create pull request
git push origin feature/user-authentication
```

### Commit Message Convention
```
type(scope): description

feat: new feature
fix: bug fix
docs: documentation changes
style: formatting changes
refactor: code refactoring
test: adding tests
chore: maintenance tasks
```

### Branch Strategy
- **main**: Production-ready code
- **develop**: Integration branch for features
- **feature/***: Individual feature development
- **hotfix/***: Critical bug fixes
- **release/***: Release preparation

## Testing Strategy

### Unit Tests
```dart
// test/services/auth_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('AuthService', () {
    test('should authenticate user with valid credentials', () async {
      // Arrange
      final authService = AuthService();
      
      // Act
      final result = await authService.signInWithEmailAndPassword(
        'test@example.com',
        'password123',
      );
      
      // Assert
      expect(result, isNotNull);
    });
  });
}
```

### Widget Tests
```dart
// test/screens/login_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LoginScreen should display email and password fields', (tester) async {
    // Arrange
    await tester.pumpWidget(MaterialApp(home: LoginScreen()));
    
    // Act & Assert
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
```

### Integration Tests
```dart
// integration_test/app_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Authentication Flow', () {
    testWidgets('complete login flow', (tester) async {
      // Test complete user journey
    });
  });
}
```

### Running Tests
```bash
# Unit tests
flutter test

# Widget tests
flutter test test/screens/

# Integration tests
flutter test integration_test/

# Test with coverage
flutter test --coverage
```

## Firebase Integration

### Firestore Data Models
```dart
// lib/models/user_model.dart
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final DateTime createdAt;
  final DateTime lastLoginAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
    required this.lastLoginAt,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'],
      displayName: data['displayName'],
      role: UserRole.values.firstWhere((e) => e.toString() == 'UserRole.${data['role']}'),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastLoginAt: (data['lastLoginAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
    };
  }
}
```

### Security Rules
```javascript
// firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // User profiles
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Inventory data
    match /inventory/{document} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
    
    // Transaction data
    match /transactions/{document} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
  }
}
```

## Error Handling

### Global Error Handling
```dart
// lib/utils/error_handler.dart
class ErrorHandler {
  static void handleError(dynamic error, StackTrace stackTrace) {
    // Log error
    print('Error: $error');
    print('Stack trace: $stackTrace');
    
    // Report to crash analytics
    FirebaseCrashlytics.instance.recordError(error, stackTrace);
    
    // Show user-friendly message
    if (error is FirebaseAuthException) {
      _handleAuthError(error);
    } else if (error is FirebaseException) {
      _handleFirebaseError(error);
    } else {
      _handleGenericError(error);
    }
  }
  
  static void _handleAuthError(FirebaseAuthException error) {
    String message;
    switch (error.code) {
      case 'user-not-found':
        message = 'No user found with this email address.';
        break;
      case 'wrong-password':
        message = 'Incorrect password.';
        break;
      case 'email-already-in-use':
        message = 'An account already exists with this email.';
        break;
      default:
        message = 'Authentication failed. Please try again.';
    }
    // Show message to user
  }
}
```

### Service Error Handling
```dart
// lib/services/base_service.dart
abstract class BaseService {
  Future<T> handleServiceCall<T>(Future<T> Function() serviceCall) async {
    try {
      return await serviceCall();
    } on FirebaseException catch (e) {
      throw ServiceException('Firebase error: ${e.message}');
    } on Exception catch (e) {
      throw ServiceException('Service error: ${e.toString()}');
    }
  }
}

class ServiceException implements Exception {
  final String message;
  ServiceException(this.message);
}
```

## Performance Optimization

### Widget Optimization
```dart
// Use const constructors when possible
const Text('Static text');

// Use ListView.builder for large lists
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemWidget(items[index]),
);

// Implement efficient state management
class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Only rebuild when authProvider changes
        return Text(authProvider.user?.displayName ?? 'Guest');
      },
    );
  }
}
```

### Memory Management
```dart
// Dispose controllers and streams
class MyScreen extends StatefulWidget {
  @override
  _MyScreenState createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  late TextEditingController _controller;
  late StreamSubscription _subscription;
  
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _subscription = someStream.listen((data) {
      // Handle data
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _subscription.cancel();
    super.dispose();
  }
}
```

## Debugging

### Debug Tools
```dart
// Debug prints
debugPrint('User authenticated: ${user.email}');

// Flutter Inspector
// Use Flutter Inspector in IDE for widget tree analysis

// Performance overlay
MaterialApp(
  debugShowMaterialGrid: true,
  showPerformanceOverlay: true,
  home: MyHomePage(),
);
```

### Logging
```dart
// lib/utils/logger.dart
import 'dart:developer' as developer;

class Logger {
  static void info(String message) {
    developer.log(message, name: 'INFO');
  }
  
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: 'ERROR',
      error: error,
      stackTrace: stackTrace,
    );
  }
  
  static void debug(String message) {
    developer.log(message, name: 'DEBUG');
  }
}
```

## Contributing Guidelines

### Code Review Checklist
- [ ] Code follows style guidelines
- [ ] All tests pass
- [ ] Documentation updated
- [ ] No hardcoded values
- [ ] Error handling implemented
- [ ] Performance considerations addressed
- [ ] Security best practices followed

### Pull Request Template
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests pass
```

### Development Environment Setup
```bash
# Clone repository
git clone <repository-url>
cd flutter_application

# Install dependencies
flutter pub get

# Run code generation (if needed)
flutter packages pub run build_runner build

# Run tests
flutter test

# Start development server
flutter run
```

## Best Practices

### Security
- Never commit sensitive data (API keys, passwords)
- Use environment variables for configuration
- Implement proper input validation
- Follow Firebase security rules best practices
- Regular security audits

### Performance
- Use const constructors where possible
- Implement lazy loading for large datasets
- Optimize images and assets
- Monitor app performance metrics
- Profile memory usage regularly

### Maintainability
- Write self-documenting code
- Use meaningful variable and function names
- Keep functions small and focused
- Implement proper error handling
- Maintain comprehensive documentation

### Testing
- Write tests for all business logic
- Aim for high test coverage
- Use mocking for external dependencies
- Test edge cases and error scenarios
- Automate testing in CI/CD pipeline

## Deployment

### Build Commands
```bash
# Debug build
flutter run

# Release build for Android
flutter build apk --release

# Release build for iOS
flutter build ios --release

# Web build
flutter build web --release
```

### Environment Setup
- Ensure Firebase configuration files are in place
- Configure platform-specific settings in `android/` and `ios/` directories
- Set up proper signing certificates for release builds

### Production Checklist
- [ ] Firebase security rules configured
- [ ] App signing certificates configured
- [ ] Performance testing completed
- [ ] User acceptance testing completed
- [ ] Backup and recovery procedures in place
