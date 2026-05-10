import 'package:flutter/material.dart';

const _bg = Colors.white;
const _primary = Color(0xFF1B5E20);
const _textDark = Color(0xFF1F2A1F);

class UnsavedChangesController extends ChangeNotifier {
  bool _isDirty = false;
  VoidCallback? _discardHandler;
  Future<bool> Function()? _saveHandler;

  bool get isDirty => _isDirty;

  void setDirty(bool value) {
    if (_isDirty == value) return;
    _isDirty = value;
    notifyListeners();
  }

  void clear() => setDirty(false);

  void setDiscardHandler(VoidCallback? handler) {
    _discardHandler = handler;
  }

  void setSaveHandler(Future<bool> Function()? handler) {
    _saveHandler = handler;
  }

  void discardChanges() {
    _discardHandler?.call();
    clear();
  }

  bool get canSave => _saveHandler != null;

  Future<bool> saveChanges() async {
    final handler = _saveHandler;
    if (handler == null) return false;
    return handler();
  }
}

enum UnsavedChangesChoice { stay, discard, save }

Future<bool> showUnsavedChangesDialog(
  BuildContext context, {
  String title = 'Discard unsaved changes?',
  String message =
      'You have unsaved changes on this form. If you leave now, your draft will be lost.',
  String stayLabel = 'Stay',
  String leaveLabel = 'Leave',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: _bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFE67E22),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.edit_rounded),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primary,
                          side: BorderSide(
                            color: _primary.withValues(alpha: 0.45),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        label: Text(
                          stayLabel,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.exit_to_app_rounded),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        label: Text(
                          leaveLabel,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  return result == true;
}

Future<UnsavedChangesChoice> showUnsavedChangesChoiceDialog(
  BuildContext context, {
  String title = 'Unsaved changes',
  String message = 'You have unsaved changes.',
  String stayLabel = 'Continue Editing',
  String discardLabel = 'Discard',
  String saveLabel = 'Save',
}) async {
  final result = await showDialog<UnsavedChangesChoice>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: _bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFE67E22),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.pop(ctx, UnsavedChangesChoice.stay),
                    icon: const Icon(Icons.edit_rounded),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: BorderSide(color: _primary.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    label: Text(
                      stayLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.pop(ctx, UnsavedChangesChoice.discard),
                    icon: const Icon(Icons.delete_outline_rounded),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(
                        color: Colors.red.shade700.withValues(alpha: 0.45),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    label: Text(
                      discardLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.pop(ctx, UnsavedChangesChoice.save),
                    icon: const Icon(Icons.save_rounded),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    label: Text(
                      saveLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  return result ?? UnsavedChangesChoice.stay;
}
