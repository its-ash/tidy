import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import 'media/media_platform.dart';
import 'media/tidy_settings.dart';
import 'media/tidy_store.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TidyApp(store: TidyStore(platform: ChannelMediaPlatform(), settings: TidySettings())));
}

class TidyApp extends StatelessWidget {
  const TidyApp({super.key, required this.store});

  final TidyStore store;

  @override
  Widget build(BuildContext context) {
    return UiApp(
      title: 'Tidy',
      home: HomeScreen(store: store),
    );
  }
}
