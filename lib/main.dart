import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'presentation/pages/login_page.dart';
import 'presentation/pages/umbrella_map_page.dart';
import 'presentation/pages/login_details_page.dart';
import 'presentation/widgets/rainfall_loading.dart';
import 'presentation/pages/home_page.dart';
import 'presentation/constants/admin_constants.dart';
import 'services/notification_service.dart';
import 'services/mqtt_bridge_service.dart';

import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'providers/location_provider.dart';
import 'providers/station_provider.dart';
import 'providers/map_provider.dart';
import 'providers/user_provider.dart';
import 'providers/rental_provider.dart';
import 'providers/connectivity_provider.dart';
import 'presentation/widgets/connection_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await dotenv.load(fileName: ".env");

  // Initialize notifications
  await NotificationService().init();

  // Initialize MQTT-Firebase Bridge
  MqttBridgeService().initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => StationProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => RentalProvider()),
      ],
      child: const RainNestApp(),
    ),
  );
}

class RainNestApp extends StatelessWidget {
  const RainNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RainNest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Outfit', // A modern font would be better
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ConnectionGuard(child: AuthWrapper()),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  Widget build(BuildContext context) {
    // Watch UserProvider here to ensure the state reacts reliably to user provider changes.
    // This is our single source of truth for both Auth state and User DB state.
    final userProvider = context.watch<UserProvider>();

    final User? user = userProvider.firebaseUser;

    if (user == null) {
      return const LoginPage();
    }

    // 1. IMMEDIATE Admin Bypass (Zero-latency)
    if (AdminConstants.isAdmin(user.email)) {
      return const UmbrellaMapPage();
    }

    // 2. Regular User Transition Logic

    // If we already have user data, show Home immediately
    if (userProvider.user != null) {
      return const HomePage();
    }

    // Only show loading if we are actively waiting for the FIRST fetch
    if (userProvider.isLoading) {
      return const RainfallLoading();
    }

    // If not loading and no user data, they must complete details
    return const LoginDetailsPage();
  }
}
