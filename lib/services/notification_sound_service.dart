import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class NotificationSoundService {
  NotificationSoundService._();
  static final NotificationSoundService instance = NotificationSoundService._();

  final AudioPlayer _player = AudioPlayer(playerId: 'notification_sound');
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    _configured = true;
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  Future<bool> play() async {
    await _ensureConfigured();
    await _player.stop();

    final candidates = <Source>[
      AssetSource('assets/sounds/notification_ping.wav'),
      AssetSource('sounds/notification_ping.wav'),
    ];

    for (final source in candidates) {
      try {
        await _player.play(source, volume: 1.0);
        return true;
      } catch (e) {
        debugPrint('NotificationSoundService.play failed for $source: $e');
      }
    }
    return false;
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
