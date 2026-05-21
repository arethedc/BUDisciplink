import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/violation_types_service.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';
import 'widgets/osa_common_widgets.dart';

enum _SettingsSection { violations, sanctionTypes, setActions }

const _bg = Colors.white;
const _primary = Color(0xFF1B5E20);
const _hint = Color(0xFF6D7F62);
const _text = Color(0xFF1F2A1F);

enum _StatusFilterOption { active, inactive, all }

bool _matchesStatusFilter(bool isActive, _StatusFilterOption filter) {
  switch (filter) {
    case _StatusFilterOption.active:
      return isActive;
    case _StatusFilterOption.inactive:
      return !isActive;
    case _StatusFilterOption.all:
      return true;
  }
}

class _InlineFilterTab {
  final String value;
  final String label;

  const _InlineFilterTab({required this.value, required this.label});
}

Widget _buildReviewStyleFilterBar({
  required List<_InlineFilterTab> tabs,
  required String selectedValue,
  required ValueChanged<String> onSelect,
}) {
  const filterRadius = 12.0;

  Widget filterTab(_InlineFilterTab tab) {
    final selected = selectedValue == tab.value;
    return InkWell(
      borderRadius: BorderRadius.circular(filterRadius),
      onTap: () {
        if (selected) return;
        onSelect(tab.value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _primary.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(filterRadius),
          border: Border.all(
            color: selected
                ? _primary.withValues(alpha: 0.36)
                : Colors.black.withValues(alpha: 0.10),
          ),
        ),
        child: Text(
          tab.label,
          style: TextStyle(
            color: selected ? _primary : _text,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  return Align(
    alignment: Alignment.centerLeft,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            filterTab(tabs[i]),
            if (i != tabs.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    ),
  );
}

Widget _buildSettingsPanelHeader({
  required String title,
  required String subtitle,
  Widget? action,
}) {
  return Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 760;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              if (action != null) ...[const SizedBox(height: 10), action],
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 12), action],
          ],
        );
      },
    ),
  );
}

Widget _buildPanelHeaderActionButton({
  required VoidCallback onPressed,
  required IconData icon,
  required String label,
}) {
  return FilledButton.icon(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: _primary,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: Icon(icon, size: 18),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
  );
}

Widget _buildNoDataSetupCard({
  required String title,
  required String subtitle,
  required String primaryButtonLabel,
  required IconData primaryIcon,
  required VoidCallback primaryOnPressed,
  String? secondaryButtonLabel,
  IconData? secondaryIcon,
  VoidCallback? secondaryOnPressed,
  double maxWidth = 640,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _hint,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 520;
                  final primaryButton = FilledButton.icon(
                    onPressed: primaryOnPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: Icon(primaryIcon, size: 18),
                    label: Text(
                      primaryButtonLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  );

                  final hasSecondary =
                      secondaryButtonLabel != null &&
                      secondaryOnPressed != null &&
                      secondaryIcon != null;
                  final secondaryButton = hasSecondary
                      ? OutlinedButton.icon(
                          onPressed: secondaryOnPressed,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            side: BorderSide(
                              color: _primary.withValues(alpha: 0.35),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Icon(secondaryIcon, size: 18),
                          label: Text(
                            secondaryButtonLabel,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        )
                      : null;

                  if (secondaryButton == null) return primaryButton;

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        primaryButton,
                        const SizedBox(height: 12),
                        secondaryButton,
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(child: primaryButton),
                      const SizedBox(width: 12),
                      Flexible(child: secondaryButton),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

InputDecoration _modalDecor({
  required String label,
  required IconData icon,
  String? helperText,
  bool enabled = true,
}) {
  return InputDecoration(
    labelText: label,
    helperText: helperText,
    labelStyle: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
    prefixIcon: Icon(icon, color: _primary.withValues(alpha: 0.85)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _primary, width: 1.6),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

ButtonStyle _modalPrimaryButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: _primary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  );
}

String _daysLabel(int days) => days == 1 ? '1 day' : '$days days';

String _meetingStatusSummary({
  required bool meetingRequired,
  required int bookingDays,
  required int graceDays,
}) {
  if (!meetingRequired) return 'No meeting required';
  final bookingText = 'Booking window: ${_daysLabel(bookingDays)}';
  if (graceDays > 0) {
    return '$bookingText | Grace period: ${_daysLabel(graceDays)}';
  }
  return '$bookingText | No grace period';
}

class ViolationTypesPage extends StatefulWidget {
  final String? initialTab;
  final ValueChanged<String>? onTabChanged;

  const ViolationTypesPage({super.key, this.initialTab, this.onTabChanged});

  @override
  State<ViolationTypesPage> createState() => _ViolationTypesPageState();
}

class _ViolationTypesPageState extends State<ViolationTypesPage>
    with TickerProviderStateMixin {
  final _svc = ViolationTypesService();
  late TabController _sectionController;

  _SettingsSection _section = _SettingsSection.violations;
  bool _seeding = false;
  bool _seedingDefaults = false;

  _SettingsSection get _activeSection =>
      _sectionFromIndex(_sectionController.index);

  _SettingsSection _sectionFromKey(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    switch (value) {
      case 'sanctions':
      case 'sanction':
        return _SettingsSection.sanctionTypes;
      case 'actions':
      case 'action':
        return _SettingsSection.setActions;
      case 'violations':
      case 'violation':
      default:
        return _SettingsSection.violations;
    }
  }

  String _sectionKey(_SettingsSection section) {
    switch (section) {
      case _SettingsSection.sanctionTypes:
        return 'sanctions';
      case _SettingsSection.setActions:
        return 'actions';
      case _SettingsSection.violations:
      default:
        return 'violations';
    }
  }

  @override
  void initState() {
    super.initState();
    _sectionController = TabController(length: 3, vsync: this);
    final initialSection = _sectionFromKey(widget.initialTab);
    _section = initialSection;
    _sectionController.index = switch (initialSection) {
      _SettingsSection.violations => 0,
      _SettingsSection.sanctionTypes => 1,
      _SettingsSection.setActions => 2,
    };
    _sectionController.addListener(() {
      if (_sectionController.indexIsChanging) return;
      final next = _sectionFromIndex(_sectionController.index);
      if (next != _section) {
        setState(() => _section = next);
        widget.onTabChanged?.call(_sectionKey(next));
      }
    });
  }

  @override
  void didUpdateWidget(covariant ViolationTypesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab == widget.initialTab) return;
    final nextSection = _sectionFromKey(widget.initialTab);
    final nextIndex = switch (nextSection) {
      _SettingsSection.violations => 0,
      _SettingsSection.sanctionTypes => 1,
      _SettingsSection.setActions => 2,
    };
    if (_sectionController.index != nextIndex) {
      _sectionController.index = nextIndex;
    }
    if (_section != nextSection) {
      setState(() => _section = nextSection);
    }
  }

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  _SettingsSection _sectionFromIndex(int index) {
    switch (index) {
      case 1:
        return _SettingsSection.sanctionTypes;
      case 2:
        return _SettingsSection.setActions;
      case 0:
      default:
        return _SettingsSection.violations;
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    AppScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _seedData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Seed Default Violation Data?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This creates default violation categories and specific violations.',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
            ),
          ),
          FilledButton(
            style: _modalPrimaryButtonStyle(),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Seed',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _seeding = true);
    try {
      await _svc.seedDefaultData();
      _showSnack('Default data seeded.');
    } catch (e) {
      _showSnack('Seed failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _seedDefaultActionAndSanctionTypes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Seed Default Violation Config?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This will seed Actions and Sanctions if they are missing.',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
            ),
          ),
          FilledButton(
            style: _modalPrimaryButtonStyle(),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Seed Defaults',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _seedingDefaults = true);
    try {
      final result = await _svc.seedDefaultActionAndSanctionTypes();
      _showSnack(
        'Seeded ${result['actions']} actions and ${result['sanctions']} sanctions.',
      );
    } catch (e) {
      _showSnack('Seed defaults failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _seedingDefaults = false);
    }
  }

  Future<void> _seedDefaultActionTypes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Seed Default Actions?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This will seed the default violation action types if they are missing.',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
            ),
          ),
          FilledButton(
            style: _modalPrimaryButtonStyle(),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Seed Actions',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _seedingDefaults = true);
    try {
      final count = await _svc.seedDefaultActionTypes();
      _showSnack('Seeded $count action types.');
    } catch (e) {
      _showSnack('Seed actions failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _seedingDefaults = false);
    }
  }

  Future<void> _seedDefaultSanctionTypes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Seed Default Sanctions?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This will seed the default sanction types if they are missing.',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
            ),
          ),
          FilledButton(
            style: _modalPrimaryButtonStyle(),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Seed Sanctions',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _seedingDefaults = true);
    try {
      final count = await _svc.seedDefaultSanctionTypes();
      _showSnack('Seeded $count sanction types.');
    } catch (e) {
      _showSnack('Seed sanctions failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _seedingDefaults = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = _activeSection;
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
            color: Colors.white,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildSectionTabs(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: section == _SettingsSection.violations
                ? _buildViolationContent(searchQuery: '')
                : section == _SettingsSection.sanctionTypes
                ? _buildCenteredPanel(
                    child: _SanctionTypesPane(searchQuery: ''),
                  )
                : section == _SettingsSection.setActions
                ? _buildCenteredPanel(child: _SetActionsPane(searchQuery: ''))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildCenteredPanel({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPanelWidth = constraints.maxWidth >= 1600
            ? 1180.0
            : constraints.maxWidth >= 1200
            ? 1080.0
            : constraints.maxWidth;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxPanelWidth),
              child: SizedBox(
                width: double.infinity,
                child: OsaPanelCard(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTabs() {
    return TabBar(
      controller: _sectionController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: _primary,
      unselectedLabelColor: _hint.withValues(alpha: 0.75),
      indicatorColor: _primary,
      indicatorWeight: 4,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      tabs: const [
        Tab(text: 'Violations'),
        Tab(text: 'Sanctions'),
        Tab(text: 'Actions'),
      ],
      onTap: (index) {
        final next = _sectionFromIndex(index);
        if (next != _section) {
          setState(() => _section = next);
        }
        widget.onTabChanged?.call(_sectionKey(next));
      },
    );
  }

  Widget _buildViolationContent({required String searchQuery}) {
    return _ViolationHierarchyPane(searchQuery: searchQuery);
  }
}

class _ViolationHierarchyPane extends StatefulWidget {
  final String searchQuery;

  const _ViolationHierarchyPane({required this.searchQuery});

  @override
  State<_ViolationHierarchyPane> createState() =>
      _ViolationHierarchyPaneState();
}

class _ViolationHierarchyPaneState extends State<_ViolationHierarchyPane> {
  final _svc = ViolationTypesService();
  String? _selectedConcern;
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  _StatusFilterOption _statusFilter = _StatusFilterOption.active;

  bool _matches(String source, String query) {
    if (query.isEmpty) return true;
    return source.toLowerCase().contains(query.toLowerCase());
  }

  String _concernLabel(String concern) {
    switch (concern.toLowerCase()) {
      case 'basic':
        return 'Basic Offenses';
      case 'serious':
        return 'Serious Offenses';
      default:
        return concern;
    }
  }

  void _showPaneSnack(String message, {bool error = false}) {
    if (!mounted) return;
    AppScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : _primary,
      ),
    );
  }

  Future<void> _openAddCategoryForConcern(String concern) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddCategoryDialog(initialConcern: concern),
    );
    if (created == true) {
      _showPaneSnack('Category rows saved.');
    }
  }

  Future<void> _openEditCategory({
    required String categoryId,
    required String concern,
    required String name,
    required bool isActive,
  }) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditCategoryDialog(
        categoryId: categoryId,
        concern: concern,
        initialName: name,
        initialActive: isActive,
      ),
    );
    if (updated == true) {
      _showPaneSnack('Category updated.');
    }
  }

  Future<void> _openAddTypeForCategory({
    required String concern,
    required String categoryId,
    required String categoryName,
  }) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddViolationTypeDialog(
        initialConcern: concern,
        initialCategoryId: categoryId,
        initialCategoryName: categoryName,
      ),
    );
    if (created == true) {
      _showPaneSnack('Specific violation rows saved.');
    }
  }

  Future<void> _openEditType({
    required String typeId,
    required String label,
    required bool isActive,
  }) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditViolationTypeDialog(
        typeId: typeId,
        initialLabel: label,
        initialActive: isActive,
      ),
    );
    if (updated == true) {
      _showPaneSnack('Specific violation updated.');
    }
  }

  Future<void> _seedDefaultViolationData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Seed Default Violation Data?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This will create the default violation categories and specific violations if they are missing.',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
            ),
          ),
          FilledButton(
            style: _modalPrimaryButtonStyle(),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Seed Data',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _svc.seedDefaultData();
      _showPaneSnack('Default violation data seeded.');
    } catch (e) {
      _showPaneSnack('Seed failed: $e', error: true);
    }
  }

  Widget _buildConcernCard({
    required String concern,
    required String description,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _svc.streamCategories(concern: concern),
      builder: (context, snap) {
        final categories = snap.data?.docs ?? const [];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              _selectedConcern = concern;
              _selectedCategoryId = null;
              _selectedCategoryName = null;
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_concernLabel(concern)} (${categories.length})',
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConcernLevel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSettingsPanelHeader(
          title: 'Violations',
          subtitle:
              'Select a violation type container to manage categories and specific violations.',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: _buildConcernCard(
                    concern: 'basic',
                    description:
                        'Manage categories and specific basic offenses.',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _buildConcernCard(
                    concern: 'serious',
                    description:
                        'Manage categories and specific serious offenses.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryLevel() {
    final concern = _selectedConcern!;
    final query = widget.searchQuery.trim();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _svc.streamCategories(concern: concern),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allCategories = [...snap.data!.docs]
          ..sort((a, b) {
            final aName = (a.data()['name'] ?? '').toString().toLowerCase();
            final bName = (b.data()['name'] ?? '').toString().toLowerCase();
            return aName.compareTo(bName);
          });

        final filteredByQuery = allCategories.where((doc) {
          final name = (doc.data()['name'] ?? '').toString();
          return _matches(name, query);
        }).toList();

        final allCount = filteredByQuery.length;
        final activeCount = filteredByQuery
            .where((doc) => doc.data()['isActive'] != false)
            .length;
        final inactiveCount = allCount - activeCount;
        final listDocs = filteredByQuery
            .where(
              (doc) => _matchesStatusFilter(
                doc.data()['isActive'] != false,
                _statusFilter,
              ),
            )
            .toList();

        if (allCategories.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPathHeader(
                title: 'Categories',
                subtitle: _concernLabel(concern),
                onBack: () => setState(() => _selectedConcern = null),
              ),
              Expanded(
                child: _buildNoDataSetupCard(
                  title: 'No categories yet',
                  subtitle:
                      'Create the first category so specific violations can be grouped under this concern.',
                  primaryButtonLabel: 'Add Category',
                  primaryIcon: Icons.add_rounded,
                  primaryOnPressed: () => _openAddCategoryForConcern(concern),
                  secondaryButtonLabel: 'Seed Default Violation Data',
                  secondaryIcon: Icons.download_rounded,
                  secondaryOnPressed: _seedDefaultViolationData,
                  maxWidth: 720,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPathHeader(
              title: 'Categories',
              subtitle: _concernLabel(concern),
              onBack: () => setState(() => _selectedConcern = null),
              action: _buildPanelHeaderActionButton(
                onPressed: () => _openAddCategoryForConcern(concern),
                icon: Icons.add_rounded,
                label: 'Add Category',
              ),
            ),
            _buildStatusFilterBar(
              allCount: allCount,
              activeCount: activeCount,
              inactiveCount: inactiveCount,
            ),
            Expanded(
              child: listDocs.isEmpty
                  ? Center(
                      child: Text(
                        query.isNotEmpty
                            ? 'No matching categories.'
                            : 'No categories for this filter.',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: listDocs.length,
                      itemBuilder: (context, index) {
                        final doc = listDocs[index];
                        final data = doc.data();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: _CategoryListTile(
                            title: (data['name'] ?? '').toString(),
                            active: data['isActive'] != false,
                            showStatus:
                                _statusFilter == _StatusFilterOption.all,
                            onEdit: () => _openEditCategory(
                              categoryId: doc.id,
                              concern: concern,
                              name: (data['name'] ?? '').toString(),
                              isActive: data['isActive'] != false,
                            ),
                            onTap: () {
                              setState(() {
                                _selectedCategoryId = doc.id;
                                _selectedCategoryName = (data['name'] ?? '')
                                    .toString();
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTypesLevel() {
    final categoryId = _selectedCategoryId!;
    final query = widget.searchQuery.trim();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _svc.streamTypesByCategoryRaw(categoryId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allTypes = [...snap.data!.docs]
          ..sort((a, b) {
            final aName = (a.data()['label'] ?? '').toString().toLowerCase();
            final bName = (b.data()['label'] ?? '').toString().toLowerCase();
            return aName.compareTo(bName);
          });

        final filteredByQuery = allTypes.where((doc) {
          final data = doc.data();
          final label = (data['label'] ?? '').toString();
          return _matches(label, query);
        }).toList();

        final allCount = filteredByQuery.length;
        final activeCount = filteredByQuery
            .where((doc) => doc.data()['isActive'] != false)
            .length;
        final inactiveCount = allCount - activeCount;
        final listDocs = filteredByQuery
            .where(
              (doc) => _matchesStatusFilter(
                doc.data()['isActive'] != false,
                _statusFilter,
              ),
            )
            .toList();
        final categoryName = _selectedCategoryName ?? 'Category';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPathHeader(
              title: 'Specific Violation',
              subtitle: categoryName,
              onBack: () => setState(() {
                _selectedCategoryId = null;
                _selectedCategoryName = null;
              }),
              action: _buildPanelHeaderActionButton(
                onPressed: () => _openAddTypeForCategory(
                  concern: _selectedConcern ?? 'basic',
                  categoryId: categoryId,
                  categoryName: categoryName,
                ),
                icon: Icons.add_rounded,
                label: 'Add Specific Violation',
              ),
            ),
            _buildStatusFilterBar(
              allCount: allCount,
              activeCount: activeCount,
              inactiveCount: inactiveCount,
            ),
            Expanded(
              child: listDocs.isEmpty
                  ? Center(
                      child: Text(
                        query.isNotEmpty
                            ? 'No matching specific violations.'
                            : 'No specific violations for this filter.',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: listDocs.length,
                      itemBuilder: (context, index) {
                        final doc = listDocs[index];
                        final data = doc.data();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: _ViolationTypeListTile(
                            label: (data['label'] ?? '').toString(),
                            active: data['isActive'] != false,
                            showStatus:
                                _statusFilter == _StatusFilterOption.all,
                            onEdit: () => _openEditType(
                              typeId: doc.id,
                              label: (data['label'] ?? '').toString(),
                              isActive: data['isActive'] != false,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusFilterBar({
    required int allCount,
    required int activeCount,
    required int inactiveCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _buildReviewStyleFilterBar(
        selectedValue: _statusFilter.name,
        onSelect: (value) {
          setState(() {
            _statusFilter = value == 'inactive'
                ? _StatusFilterOption.inactive
                : value == 'all'
                ? _StatusFilterOption.all
                : _StatusFilterOption.active;
          });
        },
        tabs: [
          _InlineFilterTab(value: 'active', label: 'Active ($activeCount)'),
          _InlineFilterTab(
            value: 'inactive',
            label: 'Inactive ($inactiveCount)',
          ),
          _InlineFilterTab(value: 'all', label: 'All ($allCount)'),
        ],
      ),
    );
  }

  Widget _buildPathHeader({
    required String title,
    required VoidCallback onBack,
    String? subtitle,
    Widget? action,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: _primary),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 4), action],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = _selectedConcern == null
        ? _buildConcernLevel()
        : (_selectedCategoryId == null
              ? _buildCategoryLevel()
              : _buildTypesLevel());

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPanelWidth = constraints.maxWidth >= 1600
            ? 1180.0
            : constraints.maxWidth >= 1200
            ? 1080.0
            : constraints.maxWidth;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxPanelWidth),
              child: SizedBox(
                width: double.infinity,
                child: OsaPanelCard(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CategoryListTile extends StatelessWidget {
  final String title;
  final bool active;
  final bool showStatus;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const _CategoryListTile({
    required this.title,
    required this.active,
    this.showStatus = false,
    required this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (showStatus) _CompactStatusIndicator(active: active),
            if (onEdit != null)
              IconButton(
                tooltip: 'Edit Category',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: _primary,
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _ViolationTypeListTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool active;
  final bool showStatus;
  final VoidCallback? onEdit;

  const _ViolationTypeListTile({
    required this.label,
    this.subtitle,
    required this.active,
    this.showStatus = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showStatus) _CompactStatusIndicator(active: active),
          if (onEdit != null)
            IconButton(
              tooltip: 'Edit Specific Violation',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: _primary,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _CompactStatusIndicator extends StatelessWidget {
  final bool active;

  const _CompactStatusIndicator({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF2E7D32) : const Color(0xFF9E9E9E);
    final label = active ? 'Active' : 'Inactive';
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SanctionTypesPane extends StatefulWidget {
  final String searchQuery;

  const _SanctionTypesPane({required this.searchQuery});

  @override
  State<_SanctionTypesPane> createState() => _SanctionTypesPaneState();
}

class _SanctionTypesPaneState extends State<_SanctionTypesPane> {
  final _svc = ViolationTypesService();
  _StatusFilterOption _statusFilter = _StatusFilterOption.active;

  bool _matches(String source, String query) {
    if (query.isEmpty) return true;
    return source.toLowerCase().contains(query.toLowerCase());
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    AppScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : _primary,
      ),
    );
  }

  Future<void> _openAddDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddSanctionTypeDialog(),
    );
    if (created == true) _showSnack('Sanction type added.');
  }

  Future<void> _openEditDialog({
    required String sanctionTypeId,
    required String label,
    required String description,
    required bool isActive,
  }) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditSanctionTypeDialog(
        sanctionTypeId: sanctionTypeId,
        initialLabel: label,
        initialDescription: description,
        initialActive: isActive,
      ),
    );
    if (updated == true) _showSnack('Sanction type updated.');
  }

  Future<void> _seedDefaultSanctionTypes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Seed Default Sanctions?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This will create the default sanction types if they are missing.',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
            ),
          ),
          FilledButton(
            style: _modalPrimaryButtonStyle(),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Seed Sanctions',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final count = await _svc.seedDefaultSanctionTypes();
      _showSnack('Seeded $count sanction types.');
    } catch (e) {
      _showSnack('Seed sanctions failed: $e', error: true);
    }
  }

  Widget _buildHeader({Widget? action}) {
    return _buildSettingsPanelHeader(
      title: 'Sanctions',
      subtitle: 'Manage sanction labels and availability.',
      action: action,
    );
  }

  Widget _buildStatusFilterBar({
    required int allCount,
    required int activeCount,
    required int inactiveCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _buildReviewStyleFilterBar(
        selectedValue: _statusFilter.name,
        onSelect: (value) {
          setState(() {
            _statusFilter = value == 'inactive'
                ? _StatusFilterOption.inactive
                : value == 'all'
                ? _StatusFilterOption.all
                : _StatusFilterOption.active;
          });
        },
        tabs: [
          _InlineFilterTab(value: 'active', label: 'Active ($activeCount)'),
          _InlineFilterTab(
            value: 'inactive',
            label: 'Inactive ($inactiveCount)',
          ),
          _InlineFilterTab(value: 'all', label: 'All ($allCount)'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _svc.streamSanctionTypes(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final query = widget.searchQuery.trim();
        final docsByQuery = snap.data!.docs.where((doc) {
          final data = doc.data();
          return _matches(
                (data['label'] ?? '').toString(),
                widget.searchQuery,
              ) ||
              _matches(
                (data['description'] ?? '').toString(),
                widget.searchQuery,
              );
        }).toList();
        final allCount = docsByQuery.length;
        final activeCount = docsByQuery
            .where((doc) => doc.data()['isActive'] != false)
            .length;
        final inactiveCount = allCount - activeCount;
        final listDocs = docsByQuery
            .where(
              (doc) => _matchesStatusFilter(
                doc.data()['isActive'] != false,
                _statusFilter,
              ),
            )
            .toList();

        if (snap.data!.docs.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              Expanded(
                child: _buildNoDataSetupCard(
                  title: 'No sanction types yet',
                  subtitle:
                      'Create the first sanction type so reports can point to a clear outcome.',
                  primaryButtonLabel: 'Add Sanction Type',
                  primaryIcon: Icons.add_rounded,
                  primaryOnPressed: _openAddDialog,
                  secondaryButtonLabel: 'Seed Default Sanctions',
                  secondaryIcon: Icons.download_rounded,
                  secondaryOnPressed: _seedDefaultSanctionTypes,
                  maxWidth: 700,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(
              action: _buildPanelHeaderActionButton(
                onPressed: _openAddDialog,
                icon: Icons.add_rounded,
                label: 'Add Sanction Type',
              ),
            ),
            _buildStatusFilterBar(
              allCount: allCount,
              activeCount: activeCount,
              inactiveCount: inactiveCount,
            ),
            Expanded(
              child: listDocs.isEmpty
                  ? Center(
                      child: Text(
                        query.isNotEmpty
                            ? 'No matching sanction types.'
                            : 'No sanction types for this filter.',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: listDocs.length,
                      itemBuilder: (_, index) {
                        final doc = listDocs[index];
                        final data = doc.data();
                        final label = (data['label'] ?? '').toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: _ViolationTypeListTile(
                            label: label,
                            active: data['isActive'] != false,
                            showStatus:
                                _statusFilter == _StatusFilterOption.all,
                            onEdit: () => _openEditDialog(
                              sanctionTypeId: doc.id,
                              label: label,
                              description: (data['description'] ?? '')
                                  .toString(),
                              isActive: data['isActive'] != false,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SetActionsPane extends StatefulWidget {
  final String searchQuery;

  const _SetActionsPane({required this.searchQuery});

  @override
  State<_SetActionsPane> createState() => _SetActionsPaneState();
}

class _SetActionsPaneState extends State<_SetActionsPane> {
  final _svc = ViolationTypesService();
  _StatusFilterOption _statusFilter = _StatusFilterOption.active;

  bool _matches(String source, String query) {
    if (query.isEmpty) return true;
    return source.toLowerCase().contains(query.toLowerCase());
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    AppScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : _primary,
      ),
    );
  }

  Future<void> _openAddDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddSetActionDialog(),
    );
    if (created == true) _showSnack('Action type added.');
  }

  Future<void> _openEditDialog({
    required String setActionId,
    required String label,
    required String description,
    required bool meetingRequired,
    required int bookingWindowDays,
    required int graceWindowDays,
    required bool isActive,
  }) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditSetActionDialog(
        setActionId: setActionId,
        initialLabel: label,
        initialDescription: description,
        initialMeetingRequired: meetingRequired,
        initialBookingWindowDays: bookingWindowDays,
        initialGraceWindowDays: graceWindowDays,
        initialActive: isActive,
      ),
    );
    if (updated == true) _showSnack('Action type updated.');
  }

  Future<void> _seedDefaultActionTypes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Seed Default Actions?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This will create the default action types if they are missing.',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
            ),
          ),
          FilledButton(
            style: _modalPrimaryButtonStyle(),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Seed Actions',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final count = await _svc.seedDefaultActionTypes();
      _showSnack('Seeded $count action types.');
    } catch (e) {
      _showSnack('Seed actions failed: $e', error: true);
    }
  }

  Widget _buildHeader({Widget? action}) {
    return _buildSettingsPanelHeader(
      title: 'Actions',
      subtitle: 'Manage set actions and meeting requirements.',
      action: action,
    );
  }

  Widget _buildStatusFilterBar({
    required int allCount,
    required int activeCount,
    required int inactiveCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _buildReviewStyleFilterBar(
        selectedValue: _statusFilter.name,
        onSelect: (value) {
          setState(() {
            _statusFilter = value == 'inactive'
                ? _StatusFilterOption.inactive
                : value == 'all'
                ? _StatusFilterOption.all
                : _StatusFilterOption.active;
          });
        },
        tabs: [
          _InlineFilterTab(value: 'active', label: 'Active ($activeCount)'),
          _InlineFilterTab(
            value: 'inactive',
            label: 'Inactive ($inactiveCount)',
          ),
          _InlineFilterTab(value: 'all', label: 'All ($allCount)'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _svc.streamSetActions(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final query = widget.searchQuery.trim();
        final docsByQuery = snap.data!.docs.where((doc) {
          final data = doc.data();
          return _matches(
                (data['label'] ?? '').toString(),
                widget.searchQuery,
              ) ||
              _matches(
                (data['description'] ?? '').toString(),
                widget.searchQuery,
              );
        }).toList();
        final allCount = docsByQuery.length;
        final activeCount = docsByQuery
            .where((doc) => doc.data()['isActive'] != false)
            .length;
        final inactiveCount = allCount - activeCount;
        final listDocs = docsByQuery
            .where(
              (doc) => _matchesStatusFilter(
                doc.data()['isActive'] != false,
                _statusFilter,
              ),
            )
            .toList();

        if (snap.data!.docs.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              Expanded(
                child: _buildNoDataSetupCard(
                  title: 'No action types yet',
                  subtitle:
                      'Create the first action type so case handling has a clear step to follow.',
                  primaryButtonLabel: 'Add Action Type',
                  primaryIcon: Icons.add_rounded,
                  primaryOnPressed: _openAddDialog,
                  secondaryButtonLabel: 'Seed Default Actions',
                  secondaryIcon: Icons.download_rounded,
                  secondaryOnPressed: _seedDefaultActionTypes,
                  maxWidth: 700,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(
              action: _buildPanelHeaderActionButton(
                onPressed: _openAddDialog,
                icon: Icons.add_rounded,
                label: 'Add Action Type',
              ),
            ),
            _buildStatusFilterBar(
              allCount: allCount,
              activeCount: activeCount,
              inactiveCount: inactiveCount,
            ),
            Expanded(
              child: listDocs.isEmpty
                  ? Center(
                      child: Text(
                        query.isNotEmpty
                            ? 'No matching action types.'
                            : 'No action types for this filter.',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: listDocs.length,
                      itemBuilder: (_, index) {
                        final doc = listDocs[index];
                        final data = doc.data();
                        final meetingRequired = data['meetingRequired'] == true;
                        final isImmediateAction =
                            doc.id.trim().toLowerCase() ==
                            'immediate_action_required';
                        final bookingDays =
                            (data['bookingWindowDays'] as num?)?.toInt() ??
                            (isImmediateAction ? 2 : 3);
                        final graceDays =
                            (data['graceWindowDays'] as num?)?.toInt() ??
                            (meetingRequired ? (isImmediateAction ? 0 : 2) : 0);
                        final meetingText = _meetingStatusSummary(
                          meetingRequired: meetingRequired,
                          bookingDays: bookingDays,
                          graceDays: graceDays,
                        );
                        final label = (data['label'] ?? '').toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: _ViolationTypeListTile(
                            label: label,
                            subtitle: meetingText,
                            active: data['isActive'] != false,
                            showStatus:
                                _statusFilter == _StatusFilterOption.all,
                            onEdit: () => _openEditDialog(
                              setActionId: doc.id,
                              label: label,
                              description: (data['description'] ?? '')
                                  .toString(),
                              meetingRequired: meetingRequired,
                              bookingWindowDays: bookingDays,
                              graceWindowDays: graceDays,
                              isActive: data['isActive'] != false,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AddCategoryDialog extends StatefulWidget {
  final String? initialConcern;

  const _AddCategoryDialog({this.initialConcern});

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _svc = ViolationTypesService();
  final List<TextEditingController> _nameCtrls = [TextEditingController()];
  String _concern = 'basic';
  bool _saving = false;

  String _slug(String value) {
    final base = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return base.isEmpty ? 'category' : base;
  }

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialConcern ?? '').trim().toLowerCase();
    if (initial == 'basic' || initial == 'serious') {
      _concern = initial;
    }
  }

  @override
  void dispose() {
    for (final ctrl in _nameCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _nameCtrls.add(TextEditingController()));
  }

  void _removeRow(int index) {
    if (_nameCtrls.length == 1) return;
    final ctrl = _nameCtrls.removeAt(index);
    ctrl.dispose();
    setState(() {});
  }

  List<String> _validNames() {
    return _nameCtrls
        .map((ctrl) => ctrl.text.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  bool _hasDuplicateSlugs(List<String> names) {
    final seen = <String>{};
    for (final name in names) {
      if (!seen.add(_slug(name))) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Add Category',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CATEGORY DETAILS',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _hint,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _concern,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                items: const [
                  DropdownMenuItem(value: 'basic', child: Text('Basic')),
                  DropdownMenuItem(value: 'serious', child: Text('Serious')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _concern = value ?? 'basic'),
                decoration: _modalDecor(
                  label: 'Violation Type',
                  icon: Icons.flag_outlined,
                  helperText: widget.initialConcern != null
                      ? 'Auto-selected from current view. You can still change it.'
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _nameCtrls.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrls[i],
                        enabled: !_saving,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                        decoration: _modalDecor(
                          label: 'Category Name ${i + 1}',
                          icon: Icons.category_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Remove row',
                      onPressed: _saving || _nameCtrls.length == 1
                          ? null
                          : () => _removeRow(i),
                      icon: const Icon(Icons.close_rounded),
                      color: _hint,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: _saving ? null : _addRow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primary,
                  side: BorderSide(color: _primary.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Add Row',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: _primary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
          ),
        ),
        FilledButton(
          style: _modalPrimaryButtonStyle(),
          onPressed: _saving
              ? null
              : () async {
                  final names = _validNames();
                  if (names.isEmpty) return;
                  if (_hasDuplicateSlugs(names)) {
                    AppScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Remove duplicate category names first.'),
                      ),
                    );
                    return;
                  }
                  setState(() => _saving = true);
                  try {
                    for (final name in names) {
                      await _svc.createCategory(
                        categoryId: _slug(name),
                        concern: _concern,
                        name: name,
                      );
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    AppScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Add failed: $e')));
                    setState(() => _saving = false);
                  }
                },
          child: const Text(
            'Save All',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _AddViolationTypeDialog extends StatefulWidget {
  final String? initialConcern;
  final String? initialCategoryId;
  final String? initialCategoryName;

  const _AddViolationTypeDialog({
    this.initialConcern,
    this.initialCategoryId,
    this.initialCategoryName,
  });

  @override
  State<_AddViolationTypeDialog> createState() =>
      _AddViolationTypeDialogState();
}

class _AddViolationTypeDialogState extends State<_AddViolationTypeDialog> {
  final _svc = ViolationTypesService();
  final List<TextEditingController> _labelCtrls = [TextEditingController()];
  bool _saving = false;
  String _concern = 'basic';
  String? _categoryId;

  String _slug(String value) {
    final base = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return base.isEmpty ? 'type' : base;
  }

  @override
  void initState() {
    super.initState();
    final initialConcern = (widget.initialConcern ?? '').trim().toLowerCase();
    if (initialConcern == 'basic' || initialConcern == 'serious') {
      _concern = initialConcern;
    }
    final initialCategoryId = (widget.initialCategoryId ?? '').trim();
    if (initialCategoryId.isNotEmpty) {
      _categoryId = initialCategoryId;
    }
  }

  @override
  void dispose() {
    for (final ctrl in _labelCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _labelCtrls.add(TextEditingController()));
  }

  void _removeRow(int index) {
    if (_labelCtrls.length == 1) return;
    final ctrl = _labelCtrls.removeAt(index);
    ctrl.dispose();
    setState(() {});
  }

  List<String> _validLabels() {
    return _labelCtrls
        .map((ctrl) => ctrl.text.trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
  }

  bool _hasDuplicateTypeIds(List<String> labels) {
    final categoryId = _categoryId;
    if (categoryId == null) return false;
    final seen = <String>{};
    for (final label in labels) {
      if (!seen.add('${categoryId}_${_slug(label)}')) return true;
    }
    return false;
  }

  Widget _buildViolationRows() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _labelCtrls.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _labelCtrls[i],
                  enabled: !_saving,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                  decoration: _modalDecor(
                    label: 'Specific Violation ${i + 1}',
                    icon: Icons.rule_folder_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove row',
                onPressed: _saving || _labelCtrls.length == 1
                    ? null
                    : () => _removeRow(i),
                icon: const Icon(Icons.close_rounded),
                color: _hint,
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: _saving ? null : _addRow,
          style: OutlinedButton.styleFrom(
            foregroundColor: _primary,
            side: BorderSide(color: _primary.withValues(alpha: 0.35)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Add Row',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        if (_saving) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(color: _primary),
        ],
      ],
    );
  }

  Widget _buildScopedContent() {
    final categoryName = (widget.initialCategoryName ?? '').trim().isEmpty
        ? (_categoryId ?? 'Selected category')
        : widget.initialCategoryName!.trim();
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'VIOLATION DETAILS',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: _hint,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: _modalDecor(
              label: 'Category',
              icon: Icons.category_outlined,
              enabled: false,
              helperText: 'Specific violations will be added here.',
            ),
            child: Text(
              categoryName,
              style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          _buildViolationRows(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isScopedAdd =
        widget.initialConcern != null && widget.initialCategoryId != null;
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Add Specific Violation',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: isScopedAdd
            ? _buildScopedContent()
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _svc.streamCategories(concern: _concern),
                builder: (context, snap) {
                  final categories = snap.data?.docs ?? const [];
                  if (_categoryId == null && categories.isNotEmpty) {
                    _categoryId = categories.first.id;
                  } else if (_categoryId != null &&
                      categories.every((doc) => doc.id != _categoryId)) {
                    _categoryId = categories.isNotEmpty
                        ? categories.first.id
                        : null;
                  }

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'VIOLATION DETAILS',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _hint,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (!isScopedAdd) ...[
                          DropdownButtonFormField<String>(
                            initialValue: _concern,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _text,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'basic',
                                child: Text('Basic'),
                              ),
                              DropdownMenuItem(
                                value: 'serious',
                                child: Text('Serious'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    setState(() {
                                      _concern = value ?? 'basic';
                                      _categoryId = null;
                                    });
                                  },
                            decoration: _modalDecor(
                              label: 'Concern',
                              icon: Icons.flag_outlined,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        DropdownButtonFormField<String>(
                          initialValue: _categoryId,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _text,
                          ),
                          items: categories
                              .map(
                                (doc) => DropdownMenuItem(
                                  value: doc.id,
                                  child: Text(
                                    (doc.data()['name'] ?? '').toString(),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _categoryId = value),
                          decoration: _modalDecor(
                            label: 'Category',
                            icon: Icons.category_outlined,
                            helperText: isScopedAdd
                                ? 'Auto-selected from current category. You can change it.'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildViolationRows(),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
          ),
        ),
        FilledButton(
          style: _modalPrimaryButtonStyle(),
          onPressed: _saving
              ? null
              : () async {
                  final labels = _validLabels();
                  if (labels.isEmpty || _categoryId == null) return;
                  if (_hasDuplicateTypeIds(labels)) {
                    AppScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Remove duplicate violation names first.',
                        ),
                      ),
                    );
                    return;
                  }
                  setState(() => _saving = true);
                  try {
                    for (final label in labels) {
                      await _svc.createType(
                        typeId: '${_categoryId!}_${_slug(label)}',
                        categoryId: _categoryId!,
                        concern: _concern,
                        label: label,
                      );
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    AppScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Add failed: $e')));
                    setState(() => _saving = false);
                  }
                },
          child: const Text(
            'Save All',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _EditCategoryDialog extends StatefulWidget {
  final String categoryId;
  final String concern;
  final String initialName;
  final bool initialActive;

  const _EditCategoryDialog({
    required this.categoryId,
    required this.concern,
    required this.initialName,
    required this.initialActive,
  });

  @override
  State<_EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<_EditCategoryDialog> {
  final _svc = ViolationTypesService();
  late final TextEditingController _nameCtrl;
  late final String _concern;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _concern = widget.concern.toLowerCase().trim() == 'serious'
        ? 'serious'
        : 'basic';
    _active = widget.initialActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Edit Category',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputDecorator(
                decoration: _modalDecor(
                  label: 'Violation Type',
                  icon: Icons.flag_outlined,
                  enabled: false,
                ),
                child: Text(
                  _concern == 'serious' ? 'Serious' : 'Basic',
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Category Name',
                  icon: Icons.category_outlined,
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: _primary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: 500,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() => _active = !_active),
                style: TextButton.styleFrom(
                  foregroundColor: _active ? _primary : _hint,
                  backgroundColor: _active
                      ? _primary.withValues(alpha: 0.10)
                      : Colors.grey.withValues(alpha: 0.10),
                  side: BorderSide(
                    color: _active
                        ? _primary.withValues(alpha: 0.55)
                        : Colors.black.withValues(alpha: 0.20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: Icon(
                  _active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                ),
                label: Text(
                  _active ? 'Active' : 'Inactive',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: _modalPrimaryButtonStyle(),
                onPressed: _saving
                    ? null
                    : () async {
                        final name = _nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        setState(() => _saving = true);
                        try {
                          await _svc.updateCategory(
                            categoryId: widget.categoryId,
                            name: name,
                            concern: _concern,
                            isActive: _active,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          if (!context.mounted) return;
                          AppScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Update failed: $e')),
                          );
                          setState(() => _saving = false);
                        }
                      },
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditViolationTypeDialog extends StatefulWidget {
  final String typeId;
  final String initialLabel;
  final bool initialActive;

  const _EditViolationTypeDialog({
    required this.typeId,
    required this.initialLabel,
    required this.initialActive,
  });

  @override
  State<_EditViolationTypeDialog> createState() =>
      _EditViolationTypeDialogState();
}

class _EditViolationTypeDialogState extends State<_EditViolationTypeDialog> {
  final _svc = ViolationTypesService();
  late final TextEditingController _labelCtrl;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initialLabel);
    _active = widget.initialActive;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Edit Specific Violation',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _labelCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Specific Violation',
                  icon: Icons.rule_folder_outlined,
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: _primary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: 500,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() => _active = !_active),
                style: TextButton.styleFrom(
                  foregroundColor: _active ? _primary : _hint,
                  backgroundColor: _active
                      ? _primary.withValues(alpha: 0.10)
                      : Colors.grey.withValues(alpha: 0.10),
                  side: BorderSide(
                    color: _active
                        ? _primary.withValues(alpha: 0.55)
                        : Colors.black.withValues(alpha: 0.20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: Icon(
                  _active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                ),
                label: Text(
                  _active ? 'Active' : 'Inactive',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: _modalPrimaryButtonStyle(),
                onPressed: _saving
                    ? null
                    : () async {
                        final label = _labelCtrl.text.trim();
                        if (label.isEmpty) return;
                        setState(() => _saving = true);
                        try {
                          await _svc.updateType(
                            typeId: widget.typeId,
                            label: label,
                            isActive: _active,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          if (!context.mounted) return;
                          AppScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Update failed: $e')),
                          );
                          setState(() => _saving = false);
                        }
                      },
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddSanctionTypeDialog extends StatefulWidget {
  const _AddSanctionTypeDialog();

  @override
  State<_AddSanctionTypeDialog> createState() => _AddSanctionTypeDialogState();
}

class _AddSanctionTypeDialogState extends State<_AddSanctionTypeDialog> {
  final _svc = ViolationTypesService();
  final List<TextEditingController> _labelCtrls = [TextEditingController()];
  final List<TextEditingController> _descriptionCtrls = [
    TextEditingController(),
  ];
  bool _saving = false;

  String _slug(String value) {
    final base = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return base.isEmpty ? 'sanction_type' : base;
  }

  @override
  void dispose() {
    for (final ctrl in _labelCtrls) {
      ctrl.dispose();
    }
    for (final ctrl in _descriptionCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _labelCtrls.add(TextEditingController());
      _descriptionCtrls.add(TextEditingController());
    });
  }

  void _removeRow(int index) {
    if (_labelCtrls.length == 1) return;
    final labelCtrl = _labelCtrls.removeAt(index);
    final descriptionCtrl = _descriptionCtrls.removeAt(index);
    labelCtrl.dispose();
    descriptionCtrl.dispose();
    setState(() {});
  }

  List<_SanctionRowValue> _validRows() {
    final rows = <_SanctionRowValue>[];
    for (var i = 0; i < _labelCtrls.length; i++) {
      final label = _labelCtrls[i].text.trim();
      if (label.isEmpty) continue;
      rows.add(
        _SanctionRowValue(
          label: label,
          description: _descriptionCtrls[i].text.trim(),
        ),
      );
    }
    return rows;
  }

  bool _hasDuplicateSlugs(List<_SanctionRowValue> rows) {
    final seen = <String>{};
    for (final row in rows) {
      if (!seen.add(_slug(row.label))) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Add Sanction Type',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SANCTION DETAILS',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _hint,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _labelCtrls.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: _labelCtrls[i],
                            enabled: !_saving,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _text,
                            ),
                            decoration: _modalDecor(
                              label: 'Label ${i + 1}',
                              icon: Icons.gavel_rounded,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionCtrls[i],
                            enabled: !_saving,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _text,
                            ),
                            decoration: _modalDecor(
                              label: 'Description ${i + 1}',
                              icon: Icons.notes_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Remove row',
                      onPressed: _saving || _labelCtrls.length == 1
                          ? null
                          : () => _removeRow(i),
                      icon: const Icon(Icons.close_rounded),
                      color: _hint,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: _saving ? null : _addRow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primary,
                  side: BorderSide(color: _primary.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Add Row',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: _primary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
          ),
        ),
        FilledButton(
          style: _modalPrimaryButtonStyle(),
          onPressed: _saving
              ? null
              : () async {
                  final rows = _validRows();
                  if (rows.isEmpty) return;
                  if (_hasDuplicateSlugs(rows)) {
                    AppScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Remove duplicate sanction names first.'),
                      ),
                    );
                    return;
                  }
                  setState(() => _saving = true);
                  try {
                    for (final row in rows) {
                      await _svc.createSanctionType(
                        sanctionTypeId: _slug(row.label),
                        label: row.label,
                        description: row.description,
                      );
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    AppScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Add failed: $e')));
                    setState(() => _saving = false);
                  }
                },
          child: const Text(
            'Save All',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _SanctionRowValue {
  final String label;
  final String description;

  const _SanctionRowValue({required this.label, required this.description});
}

class _AddSetActionDialog extends StatefulWidget {
  const _AddSetActionDialog();

  @override
  State<_AddSetActionDialog> createState() => _AddSetActionDialogState();
}

class _AddSetActionDialogState extends State<_AddSetActionDialog> {
  final _svc = ViolationTypesService();
  final _labelCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _bookingDaysCtrl = TextEditingController(text: '3');
  final _graceDaysCtrl = TextEditingController(text: '2');
  bool _meetingRequired = false;
  bool _saving = false;

  String _slug(String value) {
    final base = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return base.isEmpty ? 'set_action' : base;
  }

  bool get _isImmediateAction =>
      _slug(_labelCtrl.text.trim()) == 'immediate_action_required';

  int? _parsePositiveInt(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 1) return null;
    return parsed;
  }

  int? _parseNonNegativeInt(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descriptionCtrl.dispose();
    _bookingDaysCtrl.dispose();
    _graceDaysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Add Set Action',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SET ACTION DETAILS',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _hint,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _labelCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Label',
                  icon: Icons.rule_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Description',
                  icon: Icons.notes_outlined,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Meeting Required',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                value: _meetingRequired,
                activeThumbColor: _primary,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _meetingRequired = value;
                        if (_isImmediateAction) {
                          _graceDaysCtrl.text = '0';
                        }
                      }),
              ),
              if (_meetingRequired) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _bookingDaysCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                  decoration: _modalDecor(
                    label: 'Booking Window (Days)',
                    icon: Icons.calendar_month_rounded,
                    helperText:
                        'Number of days the student can book after this action is set.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _graceDaysCtrl,
                  enabled: !_isImmediateAction,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                  decoration: _modalDecor(
                    label: 'Grace Period (Days)',
                    icon: Icons.more_time_rounded,
                    enabled: !_isImmediateAction,
                    helperText: _isImmediateAction
                        ? 'Immediate Action Required uses a 0-day grace period.'
                        : 'Extra days allowed after the booking window.',
                  ),
                ),
              ],
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: _primary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
          ),
        ),
        FilledButton(
          style: _modalPrimaryButtonStyle(),
          onPressed: _saving
              ? null
              : () async {
                  final label = _labelCtrl.text.trim();
                  if (label.isEmpty) return;
                  if (_meetingRequired) {
                    final bookingDays = _parsePositiveInt(
                      _bookingDaysCtrl.text,
                    );
                    if (bookingDays == null) {
                      AppScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Booking window must be at least 1 day.',
                          ),
                        ),
                      );
                      return;
                    }
                    if (!_isImmediateAction) {
                      final graceDays = _parseNonNegativeInt(
                        _graceDaysCtrl.text,
                      );
                      if (graceDays == null) {
                        AppScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Grace period must be 0 days or more.',
                            ),
                          ),
                        );
                        return;
                      }
                    }
                  }
                  setState(() => _saving = true);
                  try {
                    final bookingDays =
                        _parsePositiveInt(_bookingDaysCtrl.text) ??
                        (_isImmediateAction ? 2 : 3);
                    final graceDays = _isImmediateAction
                        ? 0
                        : (_parseNonNegativeInt(_graceDaysCtrl.text) ?? 2);
                    await _svc.createSetAction(
                      setActionId: _slug(label),
                      label: label,
                      description: _descriptionCtrl.text.trim(),
                      meetingRequired: _meetingRequired,
                      bookingWindowDays: bookingDays,
                      graceWindowDays: _meetingRequired ? graceDays : 0,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    AppScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Add failed: $e')));
                    setState(() => _saving = false);
                  }
                },
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _EditSanctionTypeDialog extends StatefulWidget {
  final String sanctionTypeId;
  final String initialLabel;
  final String initialDescription;
  final bool initialActive;

  const _EditSanctionTypeDialog({
    required this.sanctionTypeId,
    required this.initialLabel,
    required this.initialDescription,
    required this.initialActive,
  });

  @override
  State<_EditSanctionTypeDialog> createState() =>
      _EditSanctionTypeDialogState();
}

class _EditSanctionTypeDialogState extends State<_EditSanctionTypeDialog> {
  final _svc = ViolationTypesService();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _descriptionCtrl;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initialLabel);
    _descriptionCtrl = TextEditingController(text: widget.initialDescription);
    _active = widget.initialActive;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Edit Sanction Type',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _labelCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Label',
                  icon: Icons.gavel_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Description',
                  icon: Icons.notes_outlined,
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: _primary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: 500,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() => _active = !_active),
                style: TextButton.styleFrom(
                  foregroundColor: _active ? _primary : _hint,
                  backgroundColor: _active
                      ? _primary.withValues(alpha: 0.10)
                      : Colors.grey.withValues(alpha: 0.10),
                  side: BorderSide(
                    color: _active
                        ? _primary.withValues(alpha: 0.55)
                        : Colors.black.withValues(alpha: 0.20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: Icon(
                  _active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                ),
                label: Text(
                  _active ? 'Active' : 'Inactive',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: _modalPrimaryButtonStyle(),
                onPressed: _saving
                    ? null
                    : () async {
                        final label = _labelCtrl.text.trim();
                        if (label.isEmpty) return;
                        setState(() => _saving = true);
                        try {
                          await _svc.updateSanctionType(
                            sanctionTypeId: widget.sanctionTypeId,
                            label: label,
                            description: _descriptionCtrl.text.trim(),
                            isActive: _active,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          if (!context.mounted) return;
                          AppScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Update failed: $e')),
                          );
                          setState(() => _saving = false);
                        }
                      },
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditSetActionDialog extends StatefulWidget {
  final String setActionId;
  final String initialLabel;
  final String initialDescription;
  final bool initialMeetingRequired;
  final int initialBookingWindowDays;
  final int initialGraceWindowDays;
  final bool initialActive;

  const _EditSetActionDialog({
    required this.setActionId,
    required this.initialLabel,
    required this.initialDescription,
    required this.initialMeetingRequired,
    required this.initialBookingWindowDays,
    required this.initialGraceWindowDays,
    required this.initialActive,
  });

  @override
  State<_EditSetActionDialog> createState() => _EditSetActionDialogState();
}

class _EditSetActionDialogState extends State<_EditSetActionDialog> {
  final _svc = ViolationTypesService();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _bookingDaysCtrl;
  late final TextEditingController _graceDaysCtrl;
  late bool _meetingRequired;
  late bool _active;
  bool _saving = false;

  bool get _isImmediateAction =>
      widget.setActionId.trim().toLowerCase() == 'immediate_action_required';

  int? _parsePositiveInt(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 1) return null;
    return parsed;
  }

  int? _parseNonNegativeInt(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initialLabel);
    _descriptionCtrl = TextEditingController(text: widget.initialDescription);
    _bookingDaysCtrl = TextEditingController(
      text: widget.initialBookingWindowDays.toString(),
    );
    _graceDaysCtrl = TextEditingController(
      text: widget.initialGraceWindowDays.toString(),
    );
    _meetingRequired = widget.initialMeetingRequired;
    _active = widget.initialActive;
    if (_isImmediateAction) {
      _graceDaysCtrl.text = '0';
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descriptionCtrl.dispose();
    _bookingDaysCtrl.dispose();
    _graceDaysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Edit Action Type',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _labelCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Label',
                  icon: Icons.rule_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Description',
                  icon: Icons.notes_outlined,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Meeting Required',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                value: _meetingRequired,
                activeThumbColor: _primary,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _meetingRequired = value;
                        if (_isImmediateAction) {
                          _graceDaysCtrl.text = '0';
                        }
                      }),
              ),
              if (_meetingRequired) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _bookingDaysCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                  decoration: _modalDecor(
                    label: 'Booking Window (Days)',
                    icon: Icons.calendar_month_rounded,
                    helperText:
                        'Number of days the student can book after this action is set.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _graceDaysCtrl,
                  enabled: !_isImmediateAction,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                  decoration: _modalDecor(
                    label: 'Grace Period (Days)',
                    icon: Icons.more_time_rounded,
                    enabled: !_isImmediateAction,
                    helperText: _isImmediateAction
                        ? 'Immediate Action Required uses a 0-day grace period.'
                        : 'Extra days allowed after the booking window.',
                  ),
                ),
              ],
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: _primary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: 500,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() => _active = !_active),
                style: TextButton.styleFrom(
                  foregroundColor: _active ? _primary : _hint,
                  backgroundColor: _active
                      ? _primary.withValues(alpha: 0.10)
                      : Colors.grey.withValues(alpha: 0.10),
                  side: BorderSide(
                    color: _active
                        ? _primary.withValues(alpha: 0.55)
                        : Colors.black.withValues(alpha: 0.20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: Icon(
                  _active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                ),
                label: Text(
                  _active ? 'Active' : 'Inactive',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: _modalPrimaryButtonStyle(),
                onPressed: _saving
                    ? null
                    : () async {
                        final label = _labelCtrl.text.trim();
                        if (label.isEmpty) return;
                        if (_meetingRequired) {
                          final bookingDays = _parsePositiveInt(
                            _bookingDaysCtrl.text,
                          );
                          if (bookingDays == null) {
                            AppScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Booking window must be at least 1 day.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (!_isImmediateAction) {
                            final graceDays = _parseNonNegativeInt(
                              _graceDaysCtrl.text,
                            );
                            if (graceDays == null) {
                              AppScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Grace period must be 0 days or more.',
                                  ),
                                ),
                              );
                              return;
                            }
                          }
                        }
                        setState(() => _saving = true);
                        try {
                          final bookingDays =
                              _parsePositiveInt(_bookingDaysCtrl.text) ??
                              (_isImmediateAction ? 2 : 3);
                          final graceDays = _isImmediateAction
                              ? 0
                              : (_parseNonNegativeInt(_graceDaysCtrl.text) ??
                                    2);
                          await _svc.updateSetAction(
                            setActionId: widget.setActionId,
                            label: label,
                            description: _descriptionCtrl.text.trim(),
                            meetingRequired: _meetingRequired,
                            bookingWindowDays: bookingDays,
                            graceWindowDays: _meetingRequired ? graceDays : 0,
                            isActive: _active,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          if (!context.mounted) return;
                          AppScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Update failed: $e')),
                          );
                          setState(() => _saving = false);
                        }
                      },
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
