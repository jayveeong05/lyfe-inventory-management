import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/stock_in_screen.dart';
import 'screens/stock_out_screen.dart';
import 'screens/data_upload_screen.dart';
import 'screens/invoice_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with error handling
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: const InventoryProApp(),
    ),
  );
}

class InventoryProApp extends StatelessWidget {
  const InventoryProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InventoryPro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 2),
      ),
      routes: {
        '/stock_in': (context) => const StockInScreen(),
        '/stock_out': (context) => const StockOutScreen(),
        '/data_upload': (context) => const DataUploadScreen(),
        '/invoice': (context) => const InvoiceScreen(),
      },
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (authProvider.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (authProvider.isAuthenticated) {
            // Force complete widget rebuild by using separate MaterialApp instances
            // This ensures proper dashboard switching without widget caching issues
            if (authProvider.isAdmin) {
              return MaterialApp(
                key: ValueKey('admin_app_${authProvider.user?.uid}'),
                home: AdminDashboardScreen(
                  key: ValueKey('admin_dashboard_${authProvider.user?.uid}'),
                ),
                debugShowCheckedModeBanner: false,
              );
            } else {
              return MaterialApp(
                key: ValueKey('user_app_${authProvider.user?.uid}'),
                home: DashboardScreen(
                  key: ValueKey('user_dashboard_${authProvider.user?.uid}'),
                ),
                debugShowCheckedModeBanner: false,
              );
            }
          } else {
            return const LoginScreen(key: ValueKey('login_screen'));
          }
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
