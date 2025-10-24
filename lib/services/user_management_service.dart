import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class UserManagementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  /// Get all users with pagination and search
  Future<Map<String, dynamic>> getUsers({
    int limit = 20,
    DocumentSnapshot? lastDocument,
    String? searchQuery,
    UserRole? roleFilter,
  }) async {
    try {
      // Check admin permissions
      if (!await _authService.isCurrentUserAdmin()) {
        return {
          'success': false,
          'error': 'Access denied. Admin privileges required.',
        };
      }

      Query query = _firestore
          .collection('users')
          .orderBy('createdAt', descending: true);

      // Apply role filter if specified
      if (roleFilter != null) {
        query = query.where('role', isEqualTo: roleFilter.name);
      }

      // Apply pagination
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      query = query.limit(limit);

      final querySnapshot = await query.get();
      List<UserProfile> users = querySnapshot.docs
          .map((doc) => UserProfile.fromFirestore(doc))
          .toList();

      // Apply search filter (post-processing since Firestore doesn't support
      // case-insensitive search on multiple fields)
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final searchLower = searchQuery.toLowerCase();
        users = users.where((user) {
          return user.email.toLowerCase().contains(searchLower) ||
              user.displayName.toLowerCase().contains(searchLower);
        }).toList();
      }

      return {
        'success': true,
        'users': users,
        'lastDocument': querySnapshot.docs.isNotEmpty
            ? querySnapshot.docs.last
            : null,
        'hasMore': querySnapshot.docs.length == limit,
      };
    } catch (e) {
      return {'success': false, 'error': 'Failed to fetch users: $e'};
    }
  }

  /// Get user statistics
  Future<Map<String, dynamic>> getUserStatistics() async {
    try {
      // Check admin permissions
      if (!await _authService.isCurrentUserAdmin()) {
        return {
          'success': false,
          'error': 'Access denied. Admin privileges required.',
        };
      }

      final usersSnapshot = await _firestore.collection('users').get();
      final users = usersSnapshot.docs
          .map((doc) => UserProfile.fromFirestore(doc))
          .toList();

      final totalUsers = users.length;
      final adminUsers = users.where((user) => user.isAdmin).length;
      final regularUsers = totalUsers - adminUsers;

      // Calculate recent activity (users created in last 30 days)
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final recentUsers = users
          .where((user) => user.createdAt.isAfter(thirtyDaysAgo))
          .length;

      // Calculate active users (logged in within last 7 days)
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final activeUsers = users
          .where((user) => user.lastLoginAt.isAfter(sevenDaysAgo))
          .length;

      return {
        'success': true,
        'totalUsers': totalUsers,
        'adminUsers': adminUsers,
        'regularUsers': regularUsers,
        'recentUsers': recentUsers,
        'activeUsers': activeUsers,
      };
    } catch (e) {
      return {'success': false, 'error': 'Failed to fetch user statistics: $e'};
    }
  }

  /// Create new user (admin only)
  Future<Map<String, dynamic>> createUser({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
  }) async {
    try {
      // Check admin permissions
      if (!await _authService.isCurrentUserAdmin()) {
        return {
          'success': false,
          'error': 'Access denied. Admin privileges required.',
        };
      }

      // Check if user already exists
      final existingUsers = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (existingUsers.docs.isNotEmpty) {
        return {
          'success': false,
          'error': 'User with this email already exists.',
        };
      }

      // Create user using AuthService
      final credential = await _authService.registerWithEmailAndPassword(
        email,
        password,
        displayName,
        role,
      );

      if (credential != null) {
        return {
          'success': true,
          'message': 'User created successfully',
          'uid': credential.user!.uid,
        };
      } else {
        return {'success': false, 'error': 'Failed to create user account'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Failed to create user: $e'};
    }
  }

  /// Update user information (admin only)
  Future<Map<String, dynamic>> updateUser({
    required String uid,
    String? displayName,
    UserRole? role,
  }) async {
    try {
      // Check admin permissions
      if (!await _authService.isCurrentUserAdmin()) {
        return {
          'success': false,
          'error': 'Access denied. Admin privileges required.',
        };
      }

      // Prevent admin from demoting themselves
      final currentUser = _authService.currentUser;
      if (currentUser?.uid == uid && role == UserRole.user) {
        return {
          'success': false,
          'error': 'You cannot remove your own admin privileges.',
        };
      }

      final updateData = <String, dynamic>{};

      if (displayName != null) {
        updateData['displayName'] = displayName;
      }

      if (role != null) {
        updateData['role'] = role.name;
      }

      if (updateData.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updateData);
      }

      return {'success': true, 'message': 'User updated successfully'};
    } catch (e) {
      return {'success': false, 'error': 'Failed to update user: $e'};
    }
  }

  /// Delete user (admin only)
  Future<Map<String, dynamic>> deleteUser(String uid) async {
    try {
      // Check admin permissions
      if (!await _authService.isCurrentUserAdmin()) {
        return {
          'success': false,
          'error': 'Access denied. Admin privileges required.',
        };
      }

      // Prevent admin from deleting themselves
      final currentUser = _authService.currentUser;
      if (currentUser?.uid == uid) {
        return {
          'success': false,
          'error': 'You cannot delete your own account.',
        };
      }

      // Delete user profile from Firestore
      await _firestore.collection('users').doc(uid).delete();

      return {'success': true, 'message': 'User deleted successfully'};
    } catch (e) {
      return {'success': false, 'error': 'Failed to delete user: $e'};
    }
  }

  /// Send password reset email (admin only)
  Future<Map<String, dynamic>> resetUserPassword(String email) async {
    try {
      // Check admin permissions
      if (!await _authService.isCurrentUserAdmin()) {
        return {
          'success': false,
          'error': 'Access denied. Admin privileges required.',
        };
      }

      await _authService.resetPassword(email);

      return {
        'success': true,
        'message': 'Password reset email sent successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to send password reset email: $e',
      };
    }
  }
}
