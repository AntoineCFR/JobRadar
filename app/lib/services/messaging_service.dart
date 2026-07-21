import 'package:firebase_messaging/firebase_messaging.dart';

/// Abonnement aux notifications push « nouvelles offres » (topic FCM `offers`).
class MessagingService {
  final _fm = FirebaseMessaging.instance;

  Future<void> init() async {
    await _fm.requestPermission(alert: true, badge: true, sound: true);
    // Le backend publie sur le topic `offers` : tout appareil abonné reçoit
    // la notif quotidienne, sans gestion de token côté serveur.
    await _fm.subscribeToTopic('offers');
  }
}
