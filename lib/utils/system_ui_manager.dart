import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Utility class for managing system UI visibility and behavior
///
/// This class provides methods to control the system navigation bar,
/// status bar, and overall immersive experience across the app.
class SystemUIManager {
  /// Configure immersive mode - hide navigation bar, keep status bar
  ///
  /// This is the main mode used throughout the app for better UX
  static Future<void> setImmersiveMode() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [SystemUiOverlay.top], // Keep status bar visible
      );
      debugPrint('✅ System UI: Immersive mode enabled (navigation bar hidden)');
    } catch (e) {
      debugPrint('❌ Failed to set immersive mode: $e');
    }
  }

  /// Configure edge-to-edge mode - hide both status and navigation bars
  ///
  /// Use this for full-screen experiences like image viewers or presentations
  static Future<void> setFullscreenMode() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [], // Hide both status bar and navigation bar
      );
      debugPrint('✅ System UI: Fullscreen mode enabled');
    } catch (e) {
      debugPrint('❌ Failed to set fullscreen mode: $e');
    }
  }

  /// Restore normal system UI - show both status and navigation bars
  ///
  /// Use this when the app needs to show system UI temporarily
  static Future<void> setNormalMode() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values, // Show all system UI
      );
      debugPrint('✅ System UI: Normal mode enabled');
    } catch (e) {
      debugPrint('❌ Failed to set normal mode: $e');
    }
  }

  /// Set preferred device orientations
  ///
  /// By default, lock to portrait mode for better mobile UX
  static Future<void> setPortraitOrientation() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      debugPrint('✅ System UI: Portrait orientation set');
    } catch (e) {
      debugPrint('❌ Failed to set portrait orientation: $e');
    }
  }

  /// Allow all device orientations
  ///
  /// Use this for screens that benefit from landscape mode
  static Future<void> setAllOrientations() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      debugPrint('✅ System UI: All orientations enabled');
    } catch (e) {
      debugPrint('❌ Failed to set all orientations: $e');
    }
  }

  /// Configure system UI colors and style
  ///
  /// Set status bar and navigation bar colors to match app theme
  static Future<void> setSystemUIStyle({
    Color? statusBarColor,
    Brightness? statusBarIconBrightness,
    Color? systemNavigationBarColor,
    Brightness? systemNavigationBarIconBrightness,
  }) async {
    try {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor:
              statusBarColor ?? const Color(0x00000000), // Transparent
          statusBarIconBrightness: statusBarIconBrightness ?? Brightness.dark,
          systemNavigationBarColor:
              systemNavigationBarColor ?? const Color(0xFF000000),
          systemNavigationBarIconBrightness:
              systemNavigationBarIconBrightness ?? Brightness.light,
        ),
      );
      debugPrint('✅ System UI: Style configured');
    } catch (e) {
      debugPrint('❌ Failed to set system UI style: $e');
    }
  }

  /// Initialize system UI for the app
  ///
  /// Call this during app startup to configure the default system UI behavior
  static Future<void> initialize() async {
    debugPrint('🚀 Initializing System UI Manager...');

    // Set immersive mode as default
    await setImmersiveMode();

    // Lock to portrait orientation
    await setPortraitOrientation();

    // Configure system UI colors
    await setSystemUIStyle();

    debugPrint('✅ System UI Manager initialized successfully');
  }

  /// Handle app lifecycle changes
  ///
  /// Call this when the app resumes to ensure system UI stays hidden
  static Future<void> onAppResumed() async {
    debugPrint('📱 App resumed - restoring immersive mode');
    await setImmersiveMode();
  }

  /// Handle app going to background
  ///
  /// Optionally restore normal UI when app goes to background
  static Future<void> onAppPaused() async {
    debugPrint('📱 App paused');
    // Optionally restore normal mode here if needed
    // await setNormalMode();
  }
}
