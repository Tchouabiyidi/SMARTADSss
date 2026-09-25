import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/smartads_api.dart';
import 'theme.dart';

const apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);

void main() => runApp(const SmartAdsApp());

class SmartAdsApp extends StatefulWidget {
  const SmartAdsApp({super.key});

  @override
  State<SmartAdsApp> createState() => _SmartAdsAppState();
}

class _SmartAdsAppState extends State<SmartAdsApp> {
  final api = SmartAdsApi(apiBase);
  Map<String, dynamic>? user;

  Future<void> _signedIn(Map<String, dynamic> result) async {
    api.token = result['token'] as String;
    if (mounted)
      setState(() => user = Map<String, dynamic>.from(result['user'] as Map));
  }

  Future<void> _signOut() async {
    api.token = null;
    if (mounted) setState(() => user = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMARTADS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(
            seedColor: teal, primary: teal, surface: Colors.white),
        appBarTheme: const AppBarTheme(
            backgroundColor: canvas, foregroundColor: ink, elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F9F8),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE6ECE9))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: teal, width: 1.5)),
        ),
      ),
      home: user == null
          ? AuthScreen(api: api, onSignedIn: _signedIn)
          : DashboardScreen(api: api, user: user!, onSignOut: _signOut),
    );
  }
}
