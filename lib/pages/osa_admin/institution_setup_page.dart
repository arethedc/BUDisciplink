import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';
import 'widgets/osa_common_widgets.dart';

import '../../services/college_program_seed_service.dart';
import '../../services/academic_settings_service.dart';
import 'widgets/institution_colleges_programs_pane.dart';

const _bg = Colors.white;
const _primary = Color(0xFF1B5E20);
const _hint = Color(0xFF6D7F62);

enum _InstitutionSection { academicSettings, collegesPrograms }

class InstitutionSetupPage extends StatefulWidget {
  const InstitutionSetupPage({super.key});

  @override
  State<InstitutionSetupPage> createState() => _InstitutionSetupPageState();
}

class _InstitutionSetupPageState extends State<InstitutionSetupPage>
    with TickerProviderStateMixin {
  final _academicSeedSvc = CollegeProgramSeedService();
  late final TabController _sectionController;
  _InstitutionSection _section = _InstitutionSection.academicSettings;
  bool _seedingAcademic = false;

  @override
  void initState() {
    super.initState();
    _sectionController = TabController(length: 2, vsync: this);
    _sectionController.addListener(() {
      if (_sectionController.indexIsChanging) return;
      final next = _sectionController.index == 1
          ? _InstitutionSection.collegesPrograms
          : _InstitutionSection.academicSettings;
      if (next != _section) {
        setState(() => _section = next);
      }
    });
  }

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _seedAcademicStructure() async {
    if (_seedingAcademic) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Seed Colleges & Programs?',
          style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
        ),
        content: const Text(
          'This will seed BU colleges and programs into Firestore collections: colleges and programs.',
          style: TextStyle(
            color: Color(0xFF1F2A1F),
            fontWeight: FontWeight.w700,
          ),
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
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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

    setState(() => _seedingAcademic = true);
    try {
      final result = await _academicSeedSvc.seedBuCollegesAndPrograms();
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Seeded ${result['colleges']} colleges and ${result['programs']} programs.',
          ),
          backgroundColor: _primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Academic seeding failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _seedingAcademic = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TabBar(
                      controller: _sectionController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: _primary,
                      unselectedLabelColor: _hint.withValues(alpha: 0.75),
                      indicatorColor: _primary,
                      indicatorWeight: 4,
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                      tabs: const [
                        Tab(text: 'School Year & Semesters'),
                        Tab(text: 'Colleges & Programs'),
                      ],
                      onTap: (index) {
                        setState(() {
                          _section = index == 1
                              ? _InstitutionSection.collegesPrograms
                              : _InstitutionSection.academicSettings;
                        });
                      },
                    ),
                  ),
                ),
                if (_section == _InstitutionSection.collegesPrograms) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _seedingAcademic ? null : _seedAcademicStructure,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: BorderSide(color: _primary.withValues(alpha: 0.35)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    icon: _seedingAcademic
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _primary,
                            ),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      _seedingAcademic
                          ? 'Seeding...'
                          : 'Seed Colleges & Programs',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _section == _InstitutionSection.academicSettings
                ? const _AcademicSettingsPane()
                : const CollegesProgramsPane(),
          ),
        ],
      ),
    );
  }
}

// --- Inlined Academic Settings pane (single-page settings ownership) ---

const bg = Color(0xFFF5F6FB);
const headerGreen = Color(0xFF2F6C44);
const dark = Color(0xFF243024);
const muted = Color(0xFF5B665B);
const _academicHeaderSubtitle =
    'Click a school year to open and manage semester settings.';

class _AcademicSettingsPane extends StatefulWidget {
  const _AcademicSettingsPane();

  @override
  State<_AcademicSettingsPane> createState() => _AcademicSettingsPaneState();
}

class _AcademicSettingsPaneState extends State<_AcademicSettingsPane> {
  final _svc = AcademicSettingsService();
  String? _selectedSyId;
  final Set<String> _autoSyncRequestedForDay = <String>{};
  DateTime _autoSyncDay = DateTime.now();

  DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _queueAutoSyncForActiveYears(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final today = _dayOnly(DateTime.now());
    final currentSyncDay = _dayOnly(_autoSyncDay);
    if (today != currentSyncDay) {
      _autoSyncDay = today;
      _autoSyncRequestedForDay.clear();
    }

    for (final doc in docs) {
      final status = _normalizeYearStatus(
        (doc.data()['status'] ?? 'inactive').toString(),
      );
      if (status != 'active') continue;
      if (_autoSyncRequestedForDay.contains(doc.id)) continue;
      _autoSyncRequestedForDay.add(doc.id);
      Future<void>(() async {
        try {
          await _svc.syncActiveTermByDate(doc.id);
        } catch (_) {}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1100;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _svc.streamYears(),
          builder: (context, snap) {
            if (snap.hasError) return _ErrorBox(snap.error.toString());
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!.docs.toList()
              ..sort((a, b) {
                final aStatus = _normalizeYearStatus(
                  (a.data()['status'] ?? 'inactive').toString(),
                );
                final bStatus = _normalizeYearStatus(
                  (b.data()['status'] ?? 'inactive').toString(),
                );
                final aRank = aStatus == 'active' ? 0 : 1;
                final bRank = bStatus == 'active' ? 0 : 1;
                if (aRank != bRank) return aRank.compareTo(bRank);

                final aLabel = (a.data()['label'] ?? a.id).toString();
                final bLabel = (b.data()['label'] ?? b.id).toString();
                // Keep newer/later SY labels first within the same status.
                return bLabel.compareTo(aLabel);
              });

            _queueAutoSyncForActiveYears(docs);

            if (docs.isEmpty) {
              return _buildEmptyTableCard(
                'No School Years yet. Click "Create School Year".',
              );
            }

            if (_selectedSyId != null &&
                docs.every((doc) => doc.id != _selectedSyId)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => _selectedSyId = null);
              });
            }

            if (_selectedSyId != null) {
              return _buildYearDetailsPane(
                syId: _selectedSyId!,
                isDesktop: isDesktop,
              );
            }

            if (!isDesktop) return _buildMobileList(docs);
            return _buildDesktopTable(docs);
          },
        );
      },
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

  Widget _buildTopHeader({
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
                        color: dark,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: muted,
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
                        color: dark,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: muted,
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

  Widget _buildPathHeader({
    required String title,
    required VoidCallback onBack,
    String? subtitle,
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
                    color: dark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTableCard(String message) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: SizedBox(
            width: double.infinity,
            child: OsaPanelCard(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    _buildTopHeader(
                      title: 'School Year & Semesters',
                      subtitle: _academicHeaderSubtitle,
                      action: _buildPanelHeaderActionButton(
                        onPressed: _openCreateSY,
                        icon: Icons.add_rounded,
                        label: 'Create School Year',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: muted,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: SizedBox(
            width: double.infinity,
            child: OsaPanelCard(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    _buildTopHeader(
                      title: 'School Year & Semesters',
                      subtitle: _academicHeaderSubtitle,
                      action: _buildPanelHeaderActionButton(
                        onPressed: _openCreateSY,
                        icon: Icons.add_rounded,
                        label: 'Create School Year',
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildSchoolYearCard(doc: doc),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: OsaPanelCard(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                _buildTopHeader(
                  title: 'School Year & Semesters',
                  subtitle: _academicHeaderSubtitle,
                  action: _buildPanelHeaderActionButton(
                    onPressed: _openCreateSY,
                    icon: Icons.add_rounded,
                    label: 'Create School Year',
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildSchoolYearCard(doc: doc),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildYearDetailsPane({
    required String syId,
    required bool isDesktop,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 1080 : double.infinity,
          ),
          child: SizedBox(
            width: double.infinity,
            child: OsaPanelCard(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    _buildPathHeader(
                      title: 'Semesters',
                      subtitle: syId,
                      onBack: () => setState(() => _selectedSyId = null),
                    ),
                    Expanded(
                      child: _YearDetailsPanel(
                        syId: syId,
                        service: _svc,
                        showCloseButton: false,
                        onClose: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolYearCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) {
    final d = doc.data();
    final label = (d['label'] ?? doc.id).toString();
    final status = _normalizeYearStatus((d['status'] ?? 'inactive').toString());
    final activeTermId = (d['activeTermId'] ?? '').toString().trim();

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selectedSyId = doc.id),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: dark,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      _CompactStatusIndicator(active: status == 'active'),
                    ],
                  ),
                  if (status == 'active' && activeTermId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Active Semester: ${_termLabel(activeTermId)}',
                      style: const TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _normalizeYearStatus(String status) {
    final normalized = status.toLowerCase().trim();
    if (normalized == 'archived') return 'inactive';
    if (normalized.isEmpty) return 'inactive';
    return normalized;
  }

  String _termLabel(String activeTermId) {
    if (activeTermId == 'term1') return '1st Sem';
    if (activeTermId == 'term2') return '2nd Sem';
    if (activeTermId == 'term3') return '3rd Sem';
    return 'Not set';
  }

  Future<void> _openCreateSY() async {
    Set<String> existingLabels = <String>{};
    String? currentAcademicYearLabel;

    try {
      final snap = await _svc.streamYears().first;
      final docs = snap.docs;
      existingLabels = docs
          .map((d) => (d.data()['label'] ?? d.id).toString())
          .toSet();
      currentAcademicYearLabel = _pickCurrentAcademicYearLabel(docs);
    } catch (_) {
      // Fallback: allow opening dialog even if prefetch fails.
    }

    if (!mounted) return;
    final res = await showDialog<_CreateSYResult>(
      context: context,
      builder: (_) => _CreateSYDialog(
        existingLabels: existingLabels,
        currentAcademicYearLabel: currentAcademicYearLabel,
      ),
    );
    if (res == null) return;

    try {
      await _svc.createSchoolYear(syId: res.syId, label: res.label);
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created ${res.label}. Configure semesters in the details panel.',
          ),
        ),
      );
      setState(() => _selectedSyId = res.syId);
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create failed: $e')));
    }
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

class _YearDetailsPanel extends StatefulWidget {
  final String syId;
  final AcademicSettingsService service;
  final VoidCallback onClose;
  final bool showCloseButton;

  const _YearDetailsPanel({
    required this.syId,
    required this.service,
    required this.onClose,
    this.showCloseButton = true,
  });

  @override
  State<_YearDetailsPanel> createState() => _YearDetailsPanelState();
}

class _YearDetailsPanelState extends State<_YearDetailsPanel> {
  String? _loadedSyId;
  String _activeSchoolYearLabel = '';
  bool _editing = false;

  DateTime? _t1Start;
  DateTime? _t1End;
  DateTime? _t2Start;
  DateTime? _t2End;
  DateTime? _t3Start;
  DateTime? _t3End;

  DateTime? _fsT1Start;
  DateTime? _fsT1End;
  DateTime? _fsT2Start;
  DateTime? _fsT2End;
  DateTime? _fsT3Start;
  DateTime? _fsT3End;

  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('academic_years')
            .doc(widget.syId)
            .snapshots(),
        builder: (context, yearSnap) {
          if (yearSnap.hasError) return _ErrorBox(yearSnap.error.toString());
          if (!yearSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final year = yearSnap.data!.data();
          if (year == null) return const _ErrorBox('School year not found');

          final label = (year['label'] ?? widget.syId).toString();
          _activeSchoolYearLabel = label;
          final rawStatus = (year['status'] ?? 'inactive').toString();
          final status = rawStatus.toLowerCase().trim() == 'archived'
              ? 'inactive'
              : rawStatus.toLowerCase().trim();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.service.streamTerms(widget.syId),
            builder: (context, termsSnap) {
              if (termsSnap.hasError) {
                return _ErrorBox(termsSnap.error.toString());
              }
              if (!termsSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final terms = termsSnap.data!.docs;
              _syncFromFirestore(terms);
              final hasCompleteSemesters = _hasCompleteSemesters();
              final autoActiveTermId =
                  status == 'active' && hasCompleteSemesters
                  ? _resolveActiveTermFromDraft()
                  : '';
              final syBounds = _schoolYearDateBounds(label);
              final syFirst = syBounds.$1;
              final syLast = syBounds.$2;
              final canEditTerm2 = _editing && _t1Start != null && _t1End != null;
              final canEditTerm3 = _editing && _t2Start != null && _t2End != null;

              DateTime pickFirst(List<DateTime?> values, DateTime fallback) =>
                  _maxDate(values.whereType<DateTime>().toList(), fallback: fallback);
              DateTime pickLast(List<DateTime?> values, DateTime fallback) =>
                  _minDate(values.whereType<DateTime>().toList(), fallback: fallback);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      child: Column(
                        children: [
                          _CardBlock(
                            title: 'Semesters',
                            subtitle:
                                'Set start and end dates for each semester.',
                            icon: Icons.calendar_month_rounded,
                            showHeader: false,
                            child: Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF6EE),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: headerGreen.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: const Text(
                                    'Active semester is set automatically from today and your semester date ranges.',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _TermDateRow(
                                  title: '1st Semester',
                                  start: _t1Start,
                                  end: _t1End,
                                  enabled: _editing,
                                  isActive: autoActiveTermId == 'term1',
                                  onPickStart: () => _pickDate(
                                    initialDate: _t1Start,
                                    firstDate: syFirst,
                                    lastDate: pickLast([
                                      _dayBefore(_t1End),
                                      _dayBefore(_t2Start),
                                      _dayBefore(_t3Start),
                                      syLast,
                                    ], syLast),
                                    onPicked: (d) =>
                                        setState(() => _t1Start = d),
                                  ),
                                  onPickEnd: () => _pickDate(
                                    initialDate: _t1End,
                                    firstDate: pickFirst([
                                      _dayAfter(_t1Start),
                                      syFirst,
                                    ], syFirst),
                                    lastDate: pickLast([
                                      _dayBefore(_t2Start),
                                      _dayBefore(_t3Start),
                                      syLast,
                                    ], syLast),
                                    onPicked: (d) => setState(() => _t1End = d),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _TermDateRow(
                                  title: '2nd Semester',
                                  start: _t2Start,
                                  end: _t2End,
                                  enabled: canEditTerm2,
                                  isActive: autoActiveTermId == 'term2',
                                  onPickStart: () => _pickDate(
                                    initialDate: _t2Start,
                                    firstDate: pickFirst([
                                      _dayAfter(_t1End),
                                      syFirst,
                                    ], syFirst),
                                    lastDate: pickLast([
                                      _dayBefore(_t2End),
                                      _dayBefore(_t3Start),
                                      syLast,
                                    ], syLast),
                                    onPicked: (d) =>
                                        setState(() => _t2Start = d),
                                  ),
                                  onPickEnd: () => _pickDate(
                                    initialDate: _t2End,
                                    firstDate: pickFirst([
                                      _dayAfter(_t2Start),
                                      _dayAfter(_t1End),
                                      syFirst,
                                    ], syFirst),
                                    lastDate: pickLast([
                                      _dayBefore(_t3Start),
                                      syLast,
                                    ], syLast),
                                    onPicked: (d) => setState(() => _t2End = d),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _TermDateRow(
                                  title: '3rd Semester',
                                  start: _t3Start,
                                  end: _t3End,
                                  enabled: canEditTerm3,
                                  isActive: autoActiveTermId == 'term3',
                                  onPickStart: () => _pickDate(
                                    initialDate: _t3Start,
                                    firstDate: pickFirst([
                                      _dayAfter(_t2End),
                                      syFirst,
                                    ], syFirst),
                                    lastDate: pickLast([
                                      _dayBefore(_t3End),
                                      syLast,
                                    ], syLast),
                                    onPicked: (d) =>
                                        setState(() => _t3Start = d),
                                  ),
                                  onPickEnd: () => _pickDate(
                                    initialDate: _t3End,
                                    firstDate: pickFirst([
                                      _dayAfter(_t3Start),
                                      _dayAfter(_t2End),
                                      syFirst,
                                    ], syFirst),
                                    lastDate: syLast,
                                    onPicked: (d) => setState(() => _t3End = d),
                                  ),
                                ),
                                if (!_editing) ...[
                                  const SizedBox(height: 8),
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Edit to update semester dates.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!_editing) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _editing = true),
                              child: const Text(
                                'Edit',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          if (status != 'active') ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: _saving
                                    ? null
                                    : () => _confirmAndSetSchoolYearActive(
                                        label: label,
                                      ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: headerGreen,
                                ),
                                child: const Text(
                                  'Set Active',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ],
                        ] else ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : _discardChanges,
                              child: const Text(
                                'Discard Changes',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving
                                  ? null
                                  : () => _save(widget.syId),
                              style: FilledButton.styleFrom(
                                backgroundColor: headerGreen,
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Save Changes',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _syncFromFirestore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> terms,
  ) {
    final syChanged = _loadedSyId != widget.syId;
    _fsT1Start = null;
    _fsT1End = null;
    _fsT2Start = null;
    _fsT2End = null;
    _fsT3Start = null;
    _fsT3End = null;

    for (final t in terms) {
      final d = t.data();
      final slot = _resolveTermSlot(t.id, d);
      final s = _readDate(d, const ['startAt', 'startDate', 'start']);
      final e = _readDate(d, const ['endAt', 'endDate', 'end']);
      if (slot == 'term1') {
        _fsT1Start = s;
        _fsT1End = e;
      } else if (slot == 'term2') {
        _fsT2Start = s;
        _fsT2End = e;
      } else if (slot == 'term3') {
        _fsT3Start = s;
        _fsT3End = e;
      }
    }

    if (syChanged) {
      _loadedSyId = widget.syId;
      _editing = false;
    }

    if (!_editing && !_saving) _loadDraftFromFirestore();
  }

  String _resolveActiveTermFromDraft() {
    DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

    final ranges = <({String id, DateTime start, DateTime end})>[];
    void addRange(String id, DateTime? start, DateTime? end) {
      if (start == null || end == null) return;
      final s = dayOnly(start);
      final e = dayOnly(end);
      if (e.isBefore(s)) return;
      ranges.add((id: id, start: s, end: e));
    }

    addRange('term1', _t1Start, _t1End);
    addRange('term2', _t2Start, _t2End);
    addRange('term3', _t3Start, _t3End);

    if (ranges.isEmpty) return 'term1';

    ranges.sort((a, b) => a.start.compareTo(b.start));
    final today = dayOnly(DateTime.now());

    for (final range in ranges) {
      final withinStart =
          today.isAtSameMomentAs(range.start) || today.isAfter(range.start);
      final withinEnd =
          today.isAtSameMomentAs(range.end) || today.isBefore(range.end);
      if (withinStart && withinEnd) return range.id;
    }

    if (today.isBefore(ranges.first.start)) return ranges.first.id;
    if (today.isAfter(ranges.last.end)) return ranges.last.id;

    for (final range in ranges) {
      if (today.isBefore(range.start)) return range.id;
    }

    return 'term1';
  }

  String _resolveTermSlot(String termDocId, Map<String, dynamic> d) {
    final id = termDocId.toLowerCase().trim();
    if (id == 'term1' || id == '1' || id.contains('1st')) return 'term1';
    if (id == 'term2' || id == '2' || id.contains('2nd')) return 'term2';
    if (id == 'term3' || id == '3' || id.contains('3rd')) return 'term3';

    final order = d['order'];
    if (order == 1 || order == '1') return 'term1';
    if (order == 2 || order == '2') return 'term2';
    if (order == 3 || order == '3') return 'term3';

    final name = (d['name'] ?? '').toString().toLowerCase();
    if (name.contains('1st') || name.contains('first')) return 'term1';
    if (name.contains('2nd') || name.contains('second')) return 'term2';
    if (name.contains('3rd') ||
        name.contains('third') ||
        name.contains('short')) {
      return 'term3';
    }
    return '';
  }

  DateTime? _readDate(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final value = d[k];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  void _loadDraftFromFirestore() {
    _t1Start = _fsT1Start;
    _t1End = _fsT1End;
    _t2Start = _fsT2Start;
    _t2End = _fsT2End;
    _t3Start = _fsT3Start;
    _t3End = _fsT3End;
  }

  void _discardChanges() {
    setState(() {
      _editing = false;
      _loadDraftFromFirestore();
    });
  }

  bool _hasCompleteSemesters() {
    if (_t1Start == null ||
        _t1End == null ||
        _t2Start == null ||
        _t2End == null ||
        _t3Start == null ||
        _t3End == null) {
      return false;
    }
    return _validateDates() == null;
  }

  Future<void> _confirmAndSetSchoolYearActive({required String label}) async {
    final err = _validateDates();
    if (err != null) {
      _toast('Set dates first. $err');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Activate School Year?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Are you sure you want to activate $label?\n\n'
          'All other school years will be set to inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Activate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final autoTermId = _resolveActiveTermFromDraft();
      await widget.service.saveTermsAndActiveTerm(
        syId: widget.syId,
        activeTermId: autoTermId,
        termDates: _termMap(),
      );
      await widget.service.setActiveSchoolYear(widget.syId);
      _toast('$label is now ACTIVE.');
    } catch (e) {
      _toast('Set active failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate({
    required ValueChanged<DateTime> onPicked,
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    final init = initialDate ?? now;
    final first = firstDate ?? DateTime(now.year - 2);
    final last = lastDate ?? DateTime(now.year + 5);
    if (last.isBefore(first)) {
      _toast('No selectable dates in this range. Adjust adjacent semester dates.');
      return;
    }
    final safeInitial = init.isBefore(first)
        ? first
        : init.isAfter(last)
        ? last
        : init;
    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) onPicked(picked);
  }

  String? _validateDates() {
    final syBounds = _schoolYearDateBounds(_activeSchoolYearLabel);
    final syFirst = syBounds.$1;
    final syLast = syBounds.$2;
    final pairs = [
      ('1st Sem', _t1Start, _t1End),
      ('2nd Sem', _t2Start, _t2End),
      ('3rd Sem', _t3Start, _t3End),
    ];
    for (final p in pairs) {
      final name = p.$1;
      final s = p.$2;
      final e = p.$3;
      if (s == null || e == null) {
        return '$name: start and end dates are required.';
      }
      if (!s.isBefore(e)) return '$name: start date must be before end date.';
      if (s.isBefore(syFirst) || e.isAfter(syLast)) {
        return '$name must be within school year ${_activeSchoolYearLabel.isEmpty ? widget.syId : _activeSchoolYearLabel}.';
      }
    }
    if (!_t1End!.isBefore(_t2Start!)) {
      return '2nd Sem must start after 1st Sem ends.';
    }
    if (!_t2End!.isBefore(_t3Start!)) {
      return '3rd Sem must start after 2nd Sem ends.';
    }
    if (!_sameDay(_dayAfter(_t1End!)!, _t2Start!)) {
      return '2nd Sem must start the day after 1st Sem ends (no gap).';
    }
    if (!_sameDay(_dayAfter(_t2End!)!, _t3Start!)) {
      return '3rd Sem must start the day after 2nd Sem ends (no gap).';
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  (DateTime, DateTime) _schoolYearDateBounds(String label) {
    final normalized = label
        .trim()
        .replaceAll('–', '-')
        .replaceAll('—', '-');
    final m = RegExp(r'(\d{4})\s*-\s*(\d{4})').firstMatch(normalized);
    if (m != null) {
      final startYear = int.tryParse(m.group(1) ?? '');
      final endYear = int.tryParse(m.group(2) ?? '');
      if (startYear != null &&
          endYear != null &&
          endYear >= startYear &&
          endYear - startYear <= 2) {
        return (
          DateTime(startYear, 1, 1),
          DateTime(endYear, 12, 31, 23, 59, 59),
        );
      }
    }
    final now = DateTime.now();
    return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31, 23, 59, 59));
  }

  DateTime? _dayAfter(DateTime? d) {
    if (d == null) return null;
    final base = DateTime(d.year, d.month, d.day);
    return base.add(const Duration(days: 1));
  }

  DateTime? _dayBefore(DateTime? d) {
    if (d == null) return null;
    final base = DateTime(d.year, d.month, d.day);
    return base.subtract(const Duration(days: 1));
  }

  DateTime _minDate(List<DateTime> values, {required DateTime fallback}) {
    if (values.isEmpty) return fallback;
    values.sort((a, b) => a.compareTo(b));
    return values.first;
  }

  DateTime _maxDate(List<DateTime> values, {required DateTime fallback}) {
    if (values.isEmpty) return fallback;
    values.sort((a, b) => a.compareTo(b));
    return values.last;
  }

  Map<String, TermDates> _termMap() {
    return {
      'term1': TermDates(
        startAt: Timestamp.fromDate(_t1Start!),
        endAt: Timestamp.fromDate(_t1End!),
      ),
      'term2': TermDates(
        startAt: Timestamp.fromDate(_t2Start!),
        endAt: Timestamp.fromDate(_t2End!),
      ),
      'term3': TermDates(
        startAt: Timestamp.fromDate(_t3Start!),
        endAt: Timestamp.fromDate(_t3End!),
      ),
    };
  }

  Future<void> _save(String syId) async {
    final err = _validateDates();
    if (err != null) {
      _toast(err);
      return;
    }

    setState(() => _saving = true);
    try {
      final autoTermId = _resolveActiveTermFromDraft();
      await widget.service.saveTermsAndActiveTerm(
        syId: syId,
        activeTermId: autoTermId,
        termDates: _termMap(),
      );
      if (mounted) {
        setState(() => _editing = false);
      }
      _toast('Saved semester dates. Active semester updated automatically.');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    AppScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _TermDateRow extends StatelessWidget {
  final String title;
  final DateTime? start;
  final DateTime? end;
  final bool enabled;
  final bool isActive;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _TermDateRow({
    required this.title,
    required this.start,
    required this.end,
    required this.enabled,
    required this.isActive,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: dark,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              _CompactStatusIndicator(active: isActive),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 680;
              if (stacked) {
                return Column(
                  children: [
                    _DatePickField(
                      label: 'Start Date',
                      value: start == null ? null : _fmtDate(start!),
                      icon: Icons.event_outlined,
                      enabled: enabled,
                      onTap: onPickStart,
                    ),
                    const SizedBox(height: 8),
                    _DatePickField(
                      label: 'End Date',
                      value: end == null ? null : _fmtDate(end!),
                      icon: Icons.event_available_outlined,
                      enabled: enabled,
                      onTap: onPickEnd,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: _DatePickField(
                      label: 'Start Date',
                      value: start == null ? null : _fmtDate(start!),
                      icon: Icons.event_outlined,
                      enabled: enabled,
                      onTap: onPickStart,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DatePickField(
                      label: 'End Date',
                      value: end == null ? null : _fmtDate(end!),
                      icon: Icons.event_available_outlined,
                      enabled: enabled,
                      onTap: onPickEnd,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _DatePickField extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _DatePickField({
    required this.label,
    required this.value,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF0F3F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: enabled ? headerGreen : muted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ?? 'Select date',
                    style: TextStyle(
                      color: value == null ? muted : dark,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: enabled ? headerGreen : muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBlock extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool showHeader;
  final Widget child;

  const _CardBlock({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: headerGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: headerGreen, size: 16),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: dark,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String msg;
  const _ErrorBox(this.msg);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Error: $msg',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
      ),
    );
  }
}

String? _pickCurrentAcademicYearLabel(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  if (docs.isEmpty) return null;

  for (final doc in docs) {
    final data = doc.data();
    final status = (data['status'] ?? '').toString().toLowerCase();
    if (status == 'active') {
      return (data['label'] ?? doc.id).toString();
    }
  }

  String? latestLabel;
  int? latestStart;
  final reg = RegExp(r'^(\d{4})-(\d{4})$');
  for (final doc in docs) {
    final label = (doc.data()['label'] ?? doc.id).toString().trim();
    final m = reg.firstMatch(label);
    if (m == null) continue;
    final start = int.tryParse(m.group(1)!);
    if (start == null) continue;
    if (latestStart == null || start > latestStart) {
      latestStart = start;
      latestLabel = label;
    }
  }
  return latestLabel;
}

class _CreateSYResult {
  final String syId;
  final String label;
  const _CreateSYResult({required this.syId, required this.label});
}

class _CreateSYDialog extends StatefulWidget {
  final Set<String> existingLabels;
  final String? currentAcademicYearLabel;

  const _CreateSYDialog({
    required this.existingLabels,
    required this.currentAcademicYearLabel,
  });

  @override
  State<_CreateSYDialog> createState() => _CreateSYDialogState();
}

class _CreateSYDialogState extends State<_CreateSYDialog> {
  late final List<int> _availableStartYears;
  int? _selectedStartYear;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().year;
    final current = _parseSy(widget.currentAcademicYearLabel);
    const yearsAhead = 10;
    final minBase = now;
    final maxBase = now + yearsAhead;

    _availableStartYears = [
      for (int y = minBase; y <= maxBase; y++)
        if (!widget.existingLabels.contains('$y-${y + 1}')) y,
    ]..sort((a, b) => b.compareTo(a));

    final expectedStart = current?.end;
    if (expectedStart != null && _availableStartYears.contains(expectedStart)) {
      _selectedStartYear = expectedStart;
    } else if (_availableStartYears.isNotEmpty) {
      _selectedStartYear = _availableStartYears.first;
    }
  }

  ({int start, int end})? _parseSy(String? label) {
    if (label == null) return null;
    final normalized = label.trim().replaceAll('–', '-').replaceAll('—', '-');
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(normalized);
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    if (start == null || end == null || end != start + 1) return null;
    return (start: start, end: end);
  }

  Future<bool> _confirmNonConsecutiveYear({
    required String currentLabel,
    required String expectedLabel,
    required String selectedLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Create Non-Consecutive Year?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'This year is not the following year of the current academic year.\n\n'
          'Current: $currentLabel\n'
          'Expected next: $expectedLabel\n'
          'Selected: $selectedLabel\n\n'
          'Are you sure you want to create it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create Anyway'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    final hasOptions = _availableStartYears.isNotEmpty;
    final selectedStart = _selectedStartYear;
    final selectedEnd = selectedStart == null ? null : selectedStart + 1;
    final selectedLabel = (selectedStart == null || selectedEnd == null)
        ? ''
        : '$selectedStart-$selectedEnd';

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      title: const Text(
        'Create School Year',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: dark,
          fontSize: 19,
        ),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set the school year range for a new academic cycle.',
              style: TextStyle(
                color: muted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'AVAILABLE YEARS (BASED ON CURRENT YEAR: $now)',
              style: const TextStyle(
                color: muted,
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select academic year range',
                    style: TextStyle(
                      color: dark,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedStart,
                          decoration: const InputDecoration(
                            labelText: 'Start Year',
                            border: OutlineInputBorder(),
                          ),
                          items: _availableStartYears
                              .map(
                                (year) => DropdownMenuItem<int>(
                                  value: year,
                                  child: Text('$year'),
                                ),
                              )
                              .toList(),
                          onChanged: hasOptions
                              ? (v) => setState(() {
                                  _selectedStartYear = v;
                                  _error = null;
                                })
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedEnd,
                          decoration: const InputDecoration(
                            labelText: 'End Year',
                            border: OutlineInputBorder(),
                          ),
                          items: selectedEnd == null
                              ? const []
                              : [
                                  DropdownMenuItem<int>(
                                    value: selectedEnd,
                                    child: Text('$selectedEnd'),
                                  ),
                                ],
                          onChanged: null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hasOptions
                  ? 'School Year ID: $selectedLabel'
                  : 'No available school year from $now to ${now + 10}.',
              style: TextStyle(
                color: hasOptions ? headerGreen : Colors.red.shade700,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !hasOptions
              ? null
              : () async {
                  if (selectedStart == null || selectedEnd == null) {
                    setState(() => _error = 'Please select a school year.');
                    return;
                  }

                  final syLabel = '$selectedStart-$selectedEnd';
                  if (widget.existingLabels.contains(syLabel)) {
                    setState(() => _error = 'School year already exists.');
                    return;
                  }

                  final current = _parseSy(widget.currentAcademicYearLabel);
                  if (current != null && selectedStart != current.end) {
                    final shouldProceed = await _confirmNonConsecutiveYear(
                      currentLabel: '${current.start}-${current.end}',
                      expectedLabel: '${current.end}-${current.end + 1}',
                      selectedLabel: syLabel,
                    );
                    if (!shouldProceed) return;
                  }

                  if (!context.mounted) return;
                  Navigator.of(
                    context,
                  ).pop(_CreateSYResult(syId: syLabel, label: syLabel));
                },
          child: const Text(
            'Create',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
