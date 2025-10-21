import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Utility class to handle Firebase Auth threading issues
/// Ensures all Firebase Auth callbacks execute on the main thread
class FirebaseThreadingFix {
  /// Wraps Firebase Auth state changes to ensure main thread execution
  static Stream<User?> safeAuthStateChanges(FirebaseAuth auth) {
    late StreamController<User?> controller;
    StreamSubscription<User?>? subscription;

    controller = StreamController<User?>(
      onListen: () {
        subscription = auth.authStateChanges().listen(
          (User? user) {
            // Ensure callback executes on main thread
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!controller.isClosed) {
                controller.add(user);
              }
            });
          },
          onError: (error) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!controller.isClosed) {
                controller.addError(error);
              }
            });
          },
        );
      },
      onCancel: () {
        subscription?.cancel();
      },
    );

    return controller.stream;
  }

  /// Wraps Firebase Auth ID token changes to ensure main thread execution
  static Stream<User?> safeIdTokenChanges(FirebaseAuth auth) {
    late StreamController<User?> controller;
    StreamSubscription<User?>? subscription;

    controller = StreamController<User?>(
      onListen: () {
        subscription = auth.idTokenChanges().listen(
          (User? user) {
            // Ensure callback executes on main thread
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!controller.isClosed) {
                controller.add(user);
              }
            });
          },
          onError: (error) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!controller.isClosed) {
                controller.addError(error);
              }
            });
          },
        );
      },
      onCancel: () {
        subscription?.cancel();
      },
    );

    return controller.stream;
  }

  /// Safely execute a callback on the main thread
  static void safeExecute(VoidCallback callback) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      callback();
    });
  }

  /// Safely execute an async callback on the main thread
  static void safeExecuteAsync(Future<void> Function() callback) {
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await callback();
    });
  }
}
