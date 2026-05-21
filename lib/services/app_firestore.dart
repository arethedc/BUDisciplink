import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_firestore_target.dart';

/// Central Firestore accessor for the app.
class AppFirestore {
  AppFirestore._();

  static FirebaseFirestore get instance => kUseDefaultFirestoreDatabase
      ? FirebaseFirestore.instance
      : FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: kFirestoreDatabaseId,
        );
}
