import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _user;
  UserProfile? _userProfile;
  bool _isLoading = true;
  String? _errorMessage;

  // Getters
  User? get user => _user;
  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _user != null;
  bool get isAdmin => _userProfile?.isAdmin ?? false;
  AuthService get authService => _authService;

  AuthProvider() {
    _initializeAuth();
  }

  void _initializeAuth() {
    // Listen to auth state changes
    _authService.authStateChanges.listen((User? user) async {
      if (user != null) {
        // If the user is already signed in and the UID hasn't changed,
        // just update the user reference silently without notifying listeners.
        // This prevents UI interference during operations like re-authentication for password changes.
        if (_user?.uid == user.uid) {
          _user = user;
          // Do NOT call notifyListeners() here - it can interfere with ongoing async operations
          // like password changes that are using this user object.
          return;
        }

        // User is signed in (fresh login or different user)
        _user = user;
        _isLoading = true;

        // Ensure UI updates happen on main thread
        SchedulerBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });

        await _authService.ensureUserProfile();
        await _loadUserProfile();

        _isLoading = false;

        // Ensure UI updates happen on main thread
        SchedulerBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      } else {
        // User is signed out - clear all state completely
        _clearUserState();
      }
    });
  }

  Future<void> _loadUserProfile() async {
    try {
      _userProfile = await _authService.getCurrentUserProfile();
      _errorMessage = null;
      notifyListeners(); // Notify UI when profile is loaded
    } catch (e) {
      _errorMessage = 'Failed to load user profile: $e';
      notifyListeners(); // Notify UI even on error
    }
  }

  // Sign in with email and password
  Future<bool> signInWithEmailAndPassword(String email, String password) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final credential = await _authService.signInWithEmailAndPassword(
        email,
        password,
      );

      if (credential != null) {
        // User profile will be loaded automatically by the auth state listener
        return true;
      }
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Register new user
  Future<bool> registerWithEmailAndPassword(
    String email,
    String password,
    String displayName,
    UserRole role,
  ) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final credential = await _authService.registerWithEmailAndPassword(
        email,
        password,
        displayName,
        role,
      );

      if (credential != null) {
        // Sign out the user immediately after registration
        // They should sign in manually to access the app
        await _authService.signOut();
        return true;
      }
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Clear state immediately before Firebase signOut
      _clearUserState();

      // Sign out from Firebase
      await _authService.signOut();

      // Ensure state is cleared again after signOut
      _clearUserState();
    } catch (e) {
      _errorMessage = 'Failed to sign out: $e';
      notifyListeners();
    }
  }

  // Helper method to completely clear user state
  void _clearUserState() {
    _user = null;
    _userProfile = null;
    _errorMessage = null;
    _isLoading = false;

    // Ensure UI updates happen on main thread
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  // Reset password
  Future<bool> resetPassword(String email) async {
    try {
      await _authService.resetPassword(email);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Refresh user profile
  Future<void> refreshUserProfile() async {
    if (_user != null) {
      await _loadUserProfile();
      notifyListeners();
    }
  }

  // Check if current user has admin privileges
  bool hasAdminAccess() {
    return isAuthenticated && isAdmin;
  }

  // Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Get all users (admin only)
  Future<List<UserProfile>> getAllUsers() async {
    if (!hasAdminAccess()) {
      throw Exception('Access denied. Admin privileges required.');
    }

    try {
      return await _authService.getAllUsers();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // Update user role (admin only)
  Future<bool> updateUserRole(String uid, UserRole newRole) async {
    if (!hasAdminAccess()) {
      throw Exception('Access denied. Admin privileges required.');
    }

    try {
      await _authService.updateUserRole(uid, newRole);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Delete user (admin only)
  Future<bool> deleteUser(String uid) async {
    if (!hasAdminAccess()) {
      throw Exception('Access denied. Admin privileges required.');
    }

    try {
      await _authService.deleteUser(uid);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Change password
  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      // Do not set _isLoading = true here, as it triggers a global app rebuild in main.dart
      // which destroys the navigation stack (closing the dialog and ProfileScreen).
      _errorMessage = null;
      notifyListeners();

      await _authService.changePassword(currentPassword, newPassword);

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
}
