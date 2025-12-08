import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firebase_threading_fix.dart';

enum UserRole { admin, user }

class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final DateTime createdAt;
  final DateTime lastLoginAt;

  UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
    required this.lastLoginAt,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      role: UserRole.values.firstWhere(
        (role) => role.name == data['role'],
        orElse: () => UserRole.user,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLoginAt:
          (data['lastLoginAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
    };
  }

  bool get isAdmin => role == UserRole.admin;
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state stream with threading fix
  Stream<User?> get authStateChanges =>
      FirebaseThreadingFix.safeAuthStateChanges(_auth);

  // Get current user profile
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        return UserProfile.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get user profile by UID
  Future<UserProfile?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserProfile.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      // Error getting user profile, returning null
      return null;
    }
  }

  // Check if current user is admin
  Future<bool> isCurrentUserAdmin() async {
    final profile = await getCurrentUserProfile();
    return profile?.isAdmin ?? false;
  }

  // Sign in with email and password
  Future<UserCredential?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update last login time
      if (credential.user != null) {
        await _updateLastLoginTime(credential.user!.uid);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Register new user
  Future<UserCredential?> registerWithEmailAndPassword(
    String email,
    String password,
    String displayName,
    UserRole role,
  ) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        // Update display name
        await credential.user!.updateDisplayName(displayName);

        // Create user profile in Firestore
        await _createUserProfile(
          credential.user!.uid,
          email,
          displayName,
          role,
        );
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Create user profile in Firestore
  Future<void> _createUserProfile(
    String uid,
    String email,
    String displayName,
    UserRole role,
  ) async {
    final now = DateTime.now();
    final userProfile = UserProfile(
      uid: uid,
      email: email,
      displayName: displayName,
      role: role,
      createdAt: now,
      lastLoginAt: now,
    );

    await _firestore
        .collection('users')
        .doc(uid)
        .set(userProfile.toFirestore());
  }

  // Update last login time
  Future<void> _updateLastLoginTime(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'lastLoginAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      // Error updating last login time, continuing silently
    }
  }

  // Ensure current user has a profile (create if missing)
  Future<void> ensureUserProfile() async {
    final user = currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        // Create a default user profile
        await _createUserProfile(
          user.uid,
          user.email ?? 'unknown@example.com',
          user.displayName ?? 'Unknown User',
          UserRole.user, // Default to user role
        );
      }
    } catch (e) {
      // Silently handle errors
    }
  }

  // Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'invalid-credential':
        return 'The current password you entered is incorrect.';
      case 'wrong-password':
        return 'The current password you entered is incorrect.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Password is too weak. Please choose a stronger password.';
      case 'invalid-email':
        return 'Invalid email address format.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      default:
        return 'Authentication failed: ${e.message}';
    }
  }

  // Get all users (admin only)
  Future<List<UserProfile>> getAllUsers() async {
    if (!await isCurrentUserAdmin()) {
      throw Exception('Access denied. Admin privileges required.');
    }

    try {
      final querySnapshot = await _firestore
          .collection('users')
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => UserProfile.fromFirestore(doc))
          .toList();
    } catch (e) {
      // Error getting all users, returning empty list
      return [];
    }
  }

  // Update user role (admin only)
  Future<void> updateUserRole(String uid, UserRole newRole) async {
    if (!await isCurrentUserAdmin()) {
      throw Exception('Access denied. Admin privileges required.');
    }

    try {
      await _firestore.collection('users').doc(uid).update({
        'role': newRole.name,
      });
    } catch (e) {
      throw Exception('Failed to update user role: $e');
    }
  }

  // Delete user (admin only)
  Future<void> deleteUser(String uid) async {
    if (!await isCurrentUserAdmin()) {
      throw Exception('Access denied. Admin privileges required.');
    }

    try {
      // Delete user profile from Firestore
      await _firestore.collection('users').doc(uid).delete();

      // Note: Deleting the Firebase Auth user requires admin SDK
      // For now, we just remove the profile from Firestore
    } catch (e) {
      throw Exception('Failed to delete user: $e');
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Change password for currently signed-in user
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No user signed in');
    }

    if (user.email == null) {
      throw Exception('User email not found');
    }

    try {
      // Re-authenticate user
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }
}
