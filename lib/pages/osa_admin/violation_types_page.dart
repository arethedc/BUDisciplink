import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/violation_case_migration.dart';
import '../../services/violation_types_service.dart';

enum _SettingsSection { violations, reviewTypes, sanctionTypes, setActions }

const _bg = Color(0xFFF6FAF6);
const _primary = Color(0xFF1B5E20);
const _hint = Color(0xFF6D7F62);
const _text = Color(0xFF1F2A1F);

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
    fillColor: enabled ? Colors.white : Colors.grey[100],
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

class ViolationTypesPage extends StatefulWidget {
  const ViolationTypesPage({super.key});

  @override
  State<ViolationTypesPage> createState() => _ViolationTypesPageState();
}

class _ViolationTypesPageState extends State<ViolationTypesPage>
    with TickerProviderStateMixin {
  final _svc = ViolationTypesService();
  final _searchCtrl = TextEditingController();
  late TabController _concernController;
  late TabController _sectionController;

  _SettingsSection _section = _SettingsSection.violations;
  bool _seeding = false;
  bool _migratingCaseTypes = false;
  bool _seedingDefaults = false;

  _SettingsSection get _activeSection =>
      _sectionFromIndex(_sectionController.index);

  @override
  void initState() {
    super.initState();
    _concernController = TabController(length: 2, vsync: this);
    _sectionController = TabController(length: 4, vsync: this);
    _sectionController.addListener(() {
      if (_sectionController.indexIsChanging) return;
      final next = _sectionFromIndex(_sectionController.index);
      if (next != _section) {
        setState(() => _section = next);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _concernController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  _SettingsSection _sectionFromIndex(int index) {
    switch (index) {
      case 1:
        return _SettingsSection.reviewTypes;
      case 2:
        return _SettingsSection.sanctionTypes;
      case 3:
        return _SettingsSection.setActions;
      case 0:
      default:
        return _SettingsSection.violations;
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _openAddCategoryDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddCategoryDialog(),
    );
    if (created == true) {
      _showSnack('Category added.');
    }
  }

  Future<void> _openAddViolationDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddViolationTypeDialog(),
    );
    if (created == true) {
      _showSnack('Specific violation added.');
    }
  }

  Future<void> _openAddReviewTypeDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddReviewTypeDialog(),
    );
    if (created == true) {
      _showSnack('Review type added.');
    }
  }

  Future<void> _openAddSanctionTypeDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddSanctionTypeDialog(),
    );
    if (created == true) {
      _showSnack('Sanction type added.');
    }
  }

  Future<void> _openAddSetActionDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddSetActionDialog(),
    );
    if (created == true) {
      _showSnack('Set action added.');
    }
  }

  Future<void> _seedDefaultActionAndSanctionTypes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Seed Default Action & Sanction Types?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This will add default Action Types and Sanction Types if they are missing.',
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
      await _svc.seedDefaultActionAndSanctionTypes();
      _showSnack('Default action and sanction types seeded.');
    } catch (e) {
      _showSnack('Seed defaults failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _seedingDefaults = false);
    }
  }

  Future<void> _runCaseTypeMigration() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Run Case Type Migration?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This will backfill actionTypeCode and sanctionTypeCode for existing violation cases.',
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
              'Run Migration',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _migratingCaseTypes = true);
    try {
      final result = await ViolationCaseMigration()
          .migrateActionAndSanctionTypes();
      _showSnack(
        'Migration done. Scanned ${result['scanned']}, updated ${result['updated']}.',
      );
    } catch (e) {
      _showSnack('Migration failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _migratingCaseTypes = false);
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
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 760;
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Violation Settings',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: _primary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildPrimaryActionButton(
                            section: section,
                            expanded: true,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Violation Settings',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: _primary,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        _buildPrimaryActionButton(section: section),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                const Text(
                  'Manage categories, specific violations, review types, sanctions, and set actions.',
                  style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 900;
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTabs(),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Search settings...',
                              prefixIcon: const Icon(
                                Icons.search,
                                color: _primary,
                              ),
                              filled: true,
                              fillColor: _bg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: _buildSectionTabs()),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 300,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Search settings...',
                              prefixIcon: const Icon(
                                Icons.search,
                                color: _primary,
                              ),
                              filled: true,
                              fillColor: _bg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _migratingCaseTypes
                          ? null
                          : _runCaseTypeMigration,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primary,
                      ),
                      icon: _migratingCaseTypes
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _primary,
                              ),
                            )
                          : const Icon(Icons.sync_alt_rounded),
                      label: Text(
                        _migratingCaseTypes
                            ? 'Migrating...'
                            : 'Migrate Case Types',
                      ),
                    ),
                    if (section == _SettingsSection.sanctionTypes ||
                        section == _SettingsSection.setActions)
                      OutlinedButton.icon(
                        onPressed: _seedingDefaults
                            ? null
                            : _seedDefaultActionAndSanctionTypes,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primary,
                        ),
                        icon: _seedingDefaults
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _primary,
                                ),
                              )
                            : const Icon(Icons.auto_fix_high_rounded),
                        label: Text(
                          _seedingDefaults
                              ? 'Seeding defaults...'
                              : 'Seed Action/Sanction Defaults',
                        ),
                      ),
                    if (section == _SettingsSection.violations)
                      OutlinedButton.icon(
                        onPressed: _openAddViolationDialog,
                        icon: const Icon(Icons.playlist_add_rounded),
                        label: const Text('Add Specific Violation'),
                      ),
                    if (section == _SettingsSection.violations)
                      OutlinedButton.icon(
                        onPressed: _seeding ? null : _seedData,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primary,
                        ),
                        icon: _seeding
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _primary,
                                ),
                              )
                            : const Icon(Icons.download_rounded),
                        label: Text(_seeding ? 'Seeding...' : 'Seed Default'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: section == _SettingsSection.violations
                ? _buildViolationContent(searchQuery: _searchCtrl.text.trim())
                : section == _SettingsSection.reviewTypes
                ? _ReviewTypesPane(searchQuery: _searchCtrl.text.trim())
                : section == _SettingsSection.sanctionTypes
                ? _SanctionTypesPane(searchQuery: _searchCtrl.text.trim())
                : _SetActionsPane(searchQuery: _searchCtrl.text.trim()),
          ),
        ],
      ),
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
        Tab(text: 'Violation Types'),
        Tab(text: 'Review Types'),
        Tab(text: 'Sanction Types'),
        Tab(text: 'Action Types'),
      ],
      onTap: (index) => setState(() => _section = _sectionFromIndex(index)),
    );
  }

  Widget _buildPrimaryActionButton({
    required _SettingsSection section,
    bool expanded = false,
  }) {
    final bool isViolation = section == _SettingsSection.violations;
    final bool isReview = section == _SettingsSection.reviewTypes;
    final bool isSanction = section == _SettingsSection.sanctionTypes;
    final bool isSetAction = section == _SettingsSection.setActions;

    final String label = isViolation
        ? 'Add Category'
        : isReview
        ? 'Add Review Type'
        : isSanction
        ? 'Add Sanction Type'
        : isSetAction
        ? 'Add Set Action'
        : 'Add';
    final IconData icon = isViolation
        ? Icons.add_circle_outline_rounded
        : Icons.add_rounded;
    final VoidCallback onPressed = isViolation
        ? _openAddCategoryDialog
        : isReview
        ? _openAddReviewTypeDialog
        : isSanction
        ? _openAddSanctionTypeDialog
        : _openAddSetActionDialog;

    final button = FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      ),
    );
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }

  Widget _buildViolationContent({required String searchQuery}) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _concernController,
            labelColor: _primary,
            unselectedLabelColor: Colors.black54,
            indicatorColor: _primary,
            tabs: const [
              Tab(text: 'BASIC OFFENSES'),
              Tab(text: 'SERIOUS OFFENSES'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _concernController,
            children: [
              _ConcernView(concern: 'basic', searchQuery: searchQuery),
              _ConcernView(concern: 'serious', searchQuery: searchQuery),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConcernView extends StatelessWidget {
  final String concern;
  final String searchQuery;

  const _ConcernView({required this.concern, required this.searchQuery});

  bool _matches(String source, String query) {
    if (query.isEmpty) return true;
    return source.toLowerCase().contains(query.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final svc = ViolationTypesService();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.streamCategories(concern: concern),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final categories = snap.data!.docs.where((doc) {
          final data = doc.data();
          final name = (data['name'] ?? '').toString();
          return _matches(name, searchQuery);
        }).toList();
        if (categories.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty
                  ? 'No categories yet.'
                  : 'No matching categories.',
              style: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: categories.length,
          itemBuilder: (_, index) {
            final doc = categories[index];
            final data = doc.data();
            return _CategoryCard(
              categoryId: doc.id,
              name: (data['name'] ?? '').toString(),
              order: (data['order'] as num?)?.toInt() ?? 0,
              isActive: data['isActive'] != false,
              searchQuery: searchQuery,
            );
          },
        );
      },
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final String categoryId;
  final String name;
  final int order;
  final bool isActive;
  final String searchQuery;

  const _CategoryCard({
    required this.categoryId,
    required this.name,
    required this.order,
    required this.isActive,
    required this.searchQuery,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.searchQuery.isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant _CategoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        widget.searchQuery.isNotEmpty) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            leading: Icon(
              Icons.category_rounded,
              color: widget.isActive ? Colors.green : Colors.grey,
            ),
            title: Text(
              widget.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text('Order: ${widget.order}'),
            trailing: Icon(
              _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
          ),
          if (_expanded) const Divider(height: 1),
          if (_expanded)
            _TypesList(
              categoryId: widget.categoryId,
              searchQuery: widget.searchQuery,
            ),
        ],
      ),
    );
  }
}

class _TypesList extends StatelessWidget {
  final String categoryId;
  final String searchQuery;

  const _TypesList({required this.categoryId, required this.searchQuery});

  bool _matches(String source, String query) {
    if (query.isEmpty) return true;
    return source.toLowerCase().contains(query.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final svc = ViolationTypesService();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.streamTypes(categoryId: categoryId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Error: ${snap.error}'),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final types = snap.data!.docs.where((doc) {
          final d = doc.data();
          final label = (d['label'] ?? '').toString();
          final hint = (d['descriptionHint'] ?? '').toString();
          return _matches(label, searchQuery) || _matches(hint, searchQuery);
        }).toList();
        if (types.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              searchQuery.isEmpty
                  ? 'No specific violations in this category.'
                  : 'No matching specific violations.',
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: types.map((doc) {
              final d = doc.data();
              return ListTile(
                dense: true,
                leading: Icon(
                  d['isActive'] == false
                      ? Icons.cancel_rounded
                      : Icons.check_circle_rounded,
                  color: d['isActive'] == false ? Colors.grey : Colors.green,
                ),
                title: Text((d['label'] ?? '').toString()),
                subtitle: (d['descriptionHint'] ?? '').toString().trim().isEmpty
                    ? null
                    : Text((d['descriptionHint'] ?? '').toString()),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _ReviewTypesPane extends StatelessWidget {
  final String searchQuery;

  const _ReviewTypesPane({required this.searchQuery});

  bool _matches(String source, String query) {
    if (query.isEmpty) return true;
    return source.toLowerCase().contains(query.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final svc = ViolationTypesService();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.streamReviewTypes(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs.where((doc) {
          final data = doc.data();
          return _matches((data['label'] ?? '').toString(), searchQuery) ||
              _matches((data['description'] ?? '').toString(), searchQuery);
        }).toList();
        if (docs.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty
                  ? 'No review types yet.'
                  : 'No matching review types.',
              style: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, index) {
            final doc = docs[index];
            final data = doc.data();
            return Card(
              child: SwitchListTile(
                value: data['isActive'] != false,
                onChanged: (value) async {
                  await svc.updateReviewTypeActive(
                    reviewTypeId: doc.id,
                    isActive: value,
                  );
                },
                title: Text(
                  (data['label'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${data['meetingRequired'] == true ? 'Meeting required' : 'No meeting required'}${(data['description'] ?? '').toString().trim().isEmpty ? '' : '\n${data['description']}'}',
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SanctionTypesPane extends StatelessWidget {
  final String searchQuery;

  const _SanctionTypesPane({required this.searchQuery});

  bool _matches(String source, String query) {
    if (query.isEmpty) return true;
    return source.toLowerCase().contains(query.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final svc = ViolationTypesService();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.streamSanctionTypes(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs.where((doc) {
          final data = doc.data();
          return _matches((data['label'] ?? '').toString(), searchQuery) ||
              _matches((data['description'] ?? '').toString(), searchQuery) ||
              _matches((data['severity'] ?? '').toString(), searchQuery);
        }).toList();
        if (docs.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty
                  ? 'No sanction types yet.'
                  : 'No matching sanction types.',
              style: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, index) {
            final doc = docs[index];
            final data = doc.data();
            final severity = (data['severity'] ?? '').toString();
            return Card(
              child: SwitchListTile(
                value: data['isActive'] != false,
                onChanged: (value) async {
                  await svc.updateSanctionTypeActive(
                    sanctionTypeId: doc.id,
                    isActive: value,
                  );
                },
                title: Text(
                  (data['label'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${severity.isEmpty ? 'No severity tag' : 'Severity: $severity'}${(data['description'] ?? '').toString().trim().isEmpty ? '' : '\n${data['description']}'}',
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SetActionsPane extends StatelessWidget {
  final String searchQuery;

  const _SetActionsPane({required this.searchQuery});

  bool _matches(String source, String query) {
    if (query.isEmpty) return true;
    return source.toLowerCase().contains(query.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final svc = ViolationTypesService();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.streamSetActions(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs.where((doc) {
          final data = doc.data();
          return _matches((data['label'] ?? '').toString(), searchQuery) ||
              _matches((data['description'] ?? '').toString(), searchQuery);
        }).toList();
        if (docs.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty
                  ? 'No action types yet.'
                  : 'No matching action types.',
              style: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, index) {
            final doc = docs[index];
            final data = doc.data();
            final meetingText = data['meetingRequired'] == true
                ? 'Meeting required'
                : 'No meeting required';
            return Card(
              child: SwitchListTile(
                value: data['isActive'] != false,
                onChanged: (value) async {
                  await svc.updateSetActionActive(
                    setActionId: doc.id,
                    isActive: value,
                  );
                },
                title: Text(
                  (data['label'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '$meetingText${(data['description'] ?? '').toString().trim().isEmpty ? '' : '\n${data['description']}'}',
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog();

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _svc = ViolationTypesService();
  final _nameCtrl = TextEditingController();
  final _orderCtrl = TextEditingController(text: '1');
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
  void dispose() {
    _nameCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
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
                  label: 'Concern',
                  icon: Icons.flag_outlined,
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
              const SizedBox(height: 12),
              TextField(
                controller: _orderCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                keyboardType: TextInputType.number,
                decoration: _modalDecor(
                  label: 'Order',
                  icon: Icons.format_list_numbered_rounded,
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
                  final name = _nameCtrl.text.trim();
                  final order = int.tryParse(_orderCtrl.text.trim()) ?? 1;
                  if (name.isEmpty) return;
                  setState(() => _saving = true);
                  try {
                    await _svc.createCategory(
                      categoryId: _slug(name),
                      concern: _concern,
                      name: name,
                      order: order,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
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

class _AddViolationTypeDialog extends StatefulWidget {
  const _AddViolationTypeDialog();

  @override
  State<_AddViolationTypeDialog> createState() =>
      _AddViolationTypeDialogState();
}

class _AddViolationTypeDialogState extends State<_AddViolationTypeDialog> {
  final _svc = ViolationTypesService();
  final _labelCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
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
  void dispose() {
    _labelCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Add Specific Violation',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _svc.streamCategories(concern: _concern),
          builder: (context, snap) {
            final categories = snap.data?.docs ?? const [];
            if (_categoryId == null && categories.isNotEmpty) {
              _categoryId = categories.first.id;
            } else if (_categoryId != null &&
                categories.every((doc) => doc.id != _categoryId)) {
              _categoryId = categories.isNotEmpty ? categories.first.id : null;
            }

            return Column(
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
                          child: Text((doc.data()['name'] ?? '').toString()),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _categoryId = value),
                  decoration: _modalDecor(
                    label: 'Category',
                    icon: Icons.category_outlined,
                  ),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                TextField(
                  controller: _descCtrl,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                  decoration: _modalDecor(
                    label: 'Description Hint (optional)',
                    icon: Icons.notes_outlined,
                  ),
                ),
                if (_saving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(color: _primary),
                ],
              ],
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
                  final label = _labelCtrl.text.trim();
                  if (label.isEmpty || _categoryId == null) return;
                  setState(() => _saving = true);
                  try {
                    await _svc.createType(
                      typeId: '${_categoryId!}_${_slug(label)}',
                      categoryId: _categoryId!,
                      concern: _concern,
                      label: label,
                      descriptionHint: _descCtrl.text.trim(),
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
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

class _AddReviewTypeDialog extends StatefulWidget {
  const _AddReviewTypeDialog();

  @override
  State<_AddReviewTypeDialog> createState() => _AddReviewTypeDialogState();
}

class _AddReviewTypeDialogState extends State<_AddReviewTypeDialog> {
  final _svc = ViolationTypesService();
  final _labelCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _orderCtrl = TextEditingController(text: '1');
  bool _meetingRequired = false;
  bool _saving = false;

  String _slug(String value) {
    final base = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return base.isEmpty ? 'review_type' : base;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descriptionCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Add Review Type',
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
                'REVIEW TYPE DETAILS',
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
                  icon: Icons.label_outline_rounded,
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
              TextField(
                controller: _orderCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                keyboardType: TextInputType.number,
                decoration: _modalDecor(
                  label: 'Order',
                  icon: Icons.format_list_numbered_rounded,
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
                    : (value) => setState(() => _meetingRequired = value),
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
                  final label = _labelCtrl.text.trim();
                  if (label.isEmpty) return;
                  setState(() => _saving = true);
                  try {
                    await _svc.createReviewType(
                      reviewTypeId: _slug(label),
                      label: label,
                      description: _descriptionCtrl.text.trim(),
                      meetingRequired: _meetingRequired,
                      order: int.tryParse(_orderCtrl.text.trim()) ?? 1,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
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

class _AddSanctionTypeDialog extends StatefulWidget {
  const _AddSanctionTypeDialog();

  @override
  State<_AddSanctionTypeDialog> createState() => _AddSanctionTypeDialogState();
}

class _AddSanctionTypeDialogState extends State<_AddSanctionTypeDialog> {
  final _svc = ViolationTypesService();
  final _labelCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _severityCtrl = TextEditingController();
  final _orderCtrl = TextEditingController(text: '1');
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
    _labelCtrl.dispose();
    _descriptionCtrl.dispose();
    _severityCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
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
                controller: _severityCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Severity (optional)',
                  icon: Icons.priority_high_rounded,
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
              TextField(
                controller: _orderCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                keyboardType: TextInputType.number,
                decoration: _modalDecor(
                  label: 'Order',
                  icon: Icons.format_list_numbered_rounded,
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
                  final label = _labelCtrl.text.trim();
                  if (label.isEmpty) return;
                  setState(() => _saving = true);
                  try {
                    await _svc.createSanctionType(
                      sanctionTypeId: _slug(label),
                      label: label,
                      description: _descriptionCtrl.text.trim(),
                      severity: _severityCtrl.text.trim(),
                      order: int.tryParse(_orderCtrl.text.trim()) ?? 1,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
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

class _AddSetActionDialog extends StatefulWidget {
  const _AddSetActionDialog();

  @override
  State<_AddSetActionDialog> createState() => _AddSetActionDialogState();
}

class _AddSetActionDialogState extends State<_AddSetActionDialog> {
  final _svc = ViolationTypesService();
  final _labelCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _orderCtrl = TextEditingController(text: '1');
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

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descriptionCtrl.dispose();
    _orderCtrl.dispose();
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
              TextField(
                controller: _orderCtrl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                keyboardType: TextInputType.number,
                decoration: _modalDecor(
                  label: 'Order',
                  icon: Icons.format_list_numbered_rounded,
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
                    : (value) => setState(() => _meetingRequired = value),
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
                  final label = _labelCtrl.text.trim();
                  if (label.isEmpty) return;
                  setState(() => _saving = true);
                  try {
                    await _svc.createSetAction(
                      setActionId: _slug(label),
                      label: label,
                      description: _descriptionCtrl.text.trim(),
                      meetingRequired: _meetingRequired,
                      order: int.tryParse(_orderCtrl.text.trim()) ?? 1,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
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
