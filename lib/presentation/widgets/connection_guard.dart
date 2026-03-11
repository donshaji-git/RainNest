import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:app_settings/app_settings.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/location_provider.dart';

class ConnectionGuard extends StatelessWidget {
  final Widget child;

  const ConnectionGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityProvider>();
    final location = context.watch<LocationProvider>();

    bool noInternet = !connectivity.isConnected;
    bool noLocation = !location.isServiceEnabled;

    if (noInternet || noLocation) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0066FF).withValues(alpha: 0.05),
                Colors.white,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon with animated feel
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0066FF).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  noInternet
                      ? Icons.wifi_off_rounded
                      : Icons.location_off_rounded,
                  size: 64,
                  color: const Color(0xFF0066FF),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                noInternet
                    ? "No Internet Connection"
                    : "Location Services Disabled",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                noInternet
                    ? "Please check your network settings and try again to continue using RainNest."
                    : "We need your location to show nearby umbrella stations. Please enable GPS in settings.",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              // Action Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    if (noInternet) {
                      AppSettings.openAppSettings(type: AppSettingsType.wifi);
                    } else {
                      location.openLocationSettings();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066FF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    "Open Settings",
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  if (noInternet) {
                    // Manual trigger is handled by provider's init but can be forced
                  } else {
                    location.refreshLocation();
                  }
                },
                child: Text(
                  "Try Again",
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF0066FF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return child;
  }
}
