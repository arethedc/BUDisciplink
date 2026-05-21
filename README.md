# apps

A new Flutter practice project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Firestore Database Target Configuration

Use `config/firebase_target.json` as the only source of truth for Firestore target values.
Do not manually edit generated files:
- `lib/services/app_firestore_target.dart`
- `functions/firestore_target.js`
- `extensions/firestore-send-email.env`

After editing `config/firebase_target.json`, run:

```powershell
node scripts/sync_firebase_target.js
```

`npm run serve` and `npm run deploy` in `functions` also auto-sync before running.
