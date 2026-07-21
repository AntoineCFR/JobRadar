"""Notifications push via Firebase Cloud Messaging.

On envoie à un *topic* ("offers") auquel l'app s'abonne : pas besoin de gérer
des tokens d'appareils côté serveur.
"""
from __future__ import annotations

import logging

log = logging.getLogger("jobradar.fcm")

TOPIC = "offers"


def notify_new_offers(count: int, sample_titles: list[str] | None = None) -> bool:
    """Envoie une notif "X nouvelles offres". Retourne True si envoyé."""
    if count <= 0:
        return False
    try:
        from firebase_admin import messaging

        body = ", ".join((sample_titles or [])[:3])
        if count > 3 and body:
            body += "…"
        message = messaging.Message(
            topic=TOPIC,
            notification=messaging.Notification(
                title=f"{count} nouvelle{'s' if count > 1 else ''} offre{'s' if count > 1 else ''}",
                body=body or "De nouvelles offres sont disponibles.",
            ),
            data={"type": "new_offers", "count": str(count)},
            android=messaging.AndroidConfig(priority="high"),
        )
        msg_id = messaging.send(message)
        log.info("FCM sent to topic '%s': %s", TOPIC, msg_id)
        return True
    except Exception as e:  # noqa: BLE001
        log.warning("FCM send failed: %s", e)
        return False
