import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class UserPreferenceEvent {
  final String uid;
  final bool notificationSoundEnabled;

  const UserPreferenceEvent({
    required this.uid,
    required this.notificationSoundEnabled,
  });
}

class UserPreferencesService {
  static const String _notificationSoundPrefix = 'notification_sound_enabled_';
  static const String _notificationLastOpenedPrefix =
      'notification_last_opened_ms_';
  static final StreamController<UserPreferenceEvent> _events =
      StreamController<UserPreferenceEvent>.broadcast();

  static Stream<UserPreferenceEvent> get changes => _events.stream;

  static String _notificationSoundKey(String uid) =>
      '$_notificationSoundPrefix$uid';
  static String _notificationLastOpenedKey(String uid) =>
      '$_notificationLastOpenedPrefix$uid';

  static Future<bool> getNotificationSoundEnabled(String uid) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationSoundKey(safeUid)) ?? false;
  }

  static Future<void> setNotificationSoundEnabled(
    String uid,
    bool enabled,
  ) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationSoundKey(safeUid), enabled);
    _events.add(
      UserPreferenceEvent(uid: safeUid, notificationSoundEnabled: enabled),
    );
  }

  static Future<DateTime?> getNotificationLastOpenedAt(String uid) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_notificationLastOpenedKey(safeUid));
    if (raw == null || raw <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  static Future<void> setNotificationLastOpenedAt(
    String uid,
    DateTime value,
  ) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _notificationLastOpenedKey(safeUid),
      value.millisecondsSinceEpoch,
    );
  }
}
