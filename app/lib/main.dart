import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'services/messaging_service.dart';
import 'services/offers_service.dart';
import 'services/profile_service.dart';
import 'services/scrape_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La config native (google-services.json / GoogleService-Info.plist) suffit à
  // initialiser Firebase sur Android/iOS.
  await Firebase.initializeApp();

  // Abonnement aux notifs push, sans bloquer le démarrage.
  MessagingService().init();

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => AuthService()),
        Provider(create: (_) => OffersService()),
        Provider(create: (_) => ScrapeService()),
        Provider(create: (_) => ProfileService()),
      ],
      child: const JobRadarApp(),
    ),
  );
}
