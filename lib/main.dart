import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Hive (Offline-First)
  await Hive.initFlutter();
  await Hive.openBox('wesios_cache');
  await Hive.openBox('wesios_settings');
  await Hive.openBox('wesios_offline_queue');

  runApp(const WesiOSApp());
}
