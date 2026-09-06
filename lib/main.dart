import 'package:flutter/material.dart';

import 'chrono_screen.dart';
import 'chrono_theme.dart';

void main() {
  // SharedPreferences needs the binding up before the first read.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StopwatchApp());
}

class StopwatchApp extends StatelessWidget {
  const StopwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stopwatch',
      debugShowCheckedModeBanner: false,
      theme: chronoThemeData(Brightness.light),
      darkTheme: chronoThemeData(Brightness.dark),
      home: const ChronoScreen(),
    );
  }
}
