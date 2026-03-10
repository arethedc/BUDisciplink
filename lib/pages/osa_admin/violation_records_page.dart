import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/widgets/modern_table_layout.dart';
import '../shared/widgets/responsive_layout_tokens.dart';

class ViolationRecordsFilterPreset {
  final bool clearExisting;
  final String? searchQuery;
  final String? concern;
  final DateTimeRange? dateRange;
  final String? category;
  final String? violationType;
  final String? reporter;
  final String? departmentProgram;
  final String? outcome;
  final String? schoolYear;
  final String? term;

  const ViolationRecordsFilterPreset({
    this.clearExisting = true,
    this.searchQuery,
    this.concern,
    this.dateRange,
    this.category,
    this.violationType,
    this.reporter,
    this.departmentProgram,
    this.outcome,
    this.schoolYear,
    this.term,
  });
}

class ViolationRecordsPage extends StatefulWidget {
  final ViolationRecordsFilterPreset? initialFilterPreset;

  const ViolationRecordsPage({super.key, this.initialFilterPreset});

  @override
  State<ViolationRecordsPage> createState() => _ViolationRecordsPageState();
}

class _ViolationRecordsPageState extends State<ViolationRecordsPage> {
  static const _bg = Color(0xFFF6FAF6);
  static const _primary = Color(0xFF1B5E20);
  static const _textDark = Color(0xFF1F2A1F);
  static const _hint = Color(0xFF6D7F62);

  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  String _searchQuery = '';
  String _concernFilter = 'All';
  DateTimeRange? _dateRange;

  String _categoryFilter = 'All';
  String _violationTypeFilter = 'All';
  String _reporterFilter = 'All';
  String _departmentProgramFilter = 'All';
  String _outcomeFilter = 'All';
  String _schoolYearFilter = 'All';
  String _termFilter = 'All';

  String _draftCategoryFilter = 'All';
  String _draftViolationTypeFilter = 'All';
  String _draftReporterFilter = 'All';
  String _draftDepartmentProgramFilter = 'All';
  String _draftOutcomeFilter = 'All';
  String _draftSchoolYearFilter = 'All';
  String _draftTermFilter = 'All';

  bool _showAdvancedFilters = false;
  final LayerLink _advancedFiltersLink = LayerLink();
  OverlayEntry? _advancedFiltersEntry;
  String? _selectedCaseId;

  @override
  void initState() {
    super.initState();
    _applyInitialPreset(widget.initialFilterPreset);
  }

  @override
  void didUpdateWidget(covariant ViolationRecordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initialFilterPreset, widget.initialFilterPreset)) {
      _applyInitialPreset(widget.initialFilterPreset);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _advancedFiltersEntry?.remove();
    _advancedFiltersEntry = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyInitialPreset(ViolationRecordsFilterPreset? preset) {
    if (preset == null) return;

    if (preset.clearExisting) {
      _selectedCaseId = null;
      _searchCtrl.clear();
      _searchQuery = '';
      _concernFilter = 'All';
      _dateRange = null;
      _categoryFilter = 'All';
      _violationTypeFilter = 'All';
      _reporterFilter = 'All';
      _departmentProgramFilter = 'All';
      _outcomeFilter = 'All';
      _schoolYearFilter = 'All';
      _termFilter = 'All';
      _showAdvancedFilters = false;
      _removeAdvancedFiltersOverlay(updateState: false);
    }

    if (preset.searchQuery != null) {
      _searchCtrl.text = preset.searchQuery!.trim();
      _searchQuery = _searchCtrl.text.trim().toLowerCase();
    }
    if (preset.concern != null && preset.concern!.trim().isNotEmpty) {
      _concernFilter = preset.concern!.trim();
    }
    if (preset.dateRange != null) {
      _dateRange = preset.dateRange;
    }
    if (preset.category != null && preset.category!.trim().isNotEmpty) {
      _categoryFilter = preset.category!.trim();
    }
    if (preset.violationType != null &&
        preset.violationType!.trim().isNotEmpty) {
      _violationTypeFilter = preset.violationType!.trim();
    }
    if (preset.reporter != null && preset.reporter!.trim().isNotEmpty) {
      _reporterFilter = preset.reporter!.trim();
    }
    if (preset.departmentProgram != null &&
        preset.departmentProgram!.trim().isNotEmpty) {
      _departmentProgramFilter = preset.departmentProgram!.trim();
    }
    if (preset.outcome != null && preset.outcome!.trim().isNotEmpty) {
      _outcomeFilter = preset.outcome!.trim();
    }
    if (preset.schoolYear != null && preset.schoolYear!.trim().isNotEmpty) {
      _schoolYearFilter = preset.schoolYear!.trim();
    }
    if (preset.term != null && preset.term!.trim().isNotEmpty) {
      _termFilter = preset.term!.trim();
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim().toLowerCase());
    });
  }

  void _syncDraftFromApplied() {
    _draftCategoryFilter = _categoryFilter;
    _draftViolationTypeFilter = _violationTypeFilter;
    _draftReporterFilter = _reporterFilter;
    _draftDepartmentProgramFilter = _departmentProgramFilter;
    _draftOutcomeFilter = _outcomeFilter;
    _draftSchoolYearFilter = _schoolYearFilter;
    _draftTermFilter = _termFilter;
  }

  void _removeAdvancedFiltersOverlay({bool updateState = true}) {
    _advancedFiltersEntry?.remove();
    _advancedFiltersEntry = null;
    if (updateState && mounted && _showAdvancedFilters) {
      setState(() => _showAdvancedFilters = false);
    }
  }

  // ignore: unused_element
  void _toggleAdvancedFiltersOverlay({
    required List<String> categoryOptions,
    required List<String> violationOptions,
    required List<String> reporterOptions,
    required List<String> departmentProgramOptions,
    required List<String> outcomeOptions,
    required List<String> schoolYearOptions,
    required List<String> termOptions,
  }) {
    if (_advancedFiltersEntry != null) {
      _removeAdvancedFiltersOverlay();
      return;
    }

    _syncDraftFromApplied();
    final overlay = Overlay.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = (screenWidth * 0.74).clamp(720.0, 980.0);

    _advancedFiltersEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeAdvancedFiltersOverlay,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _advancedFiltersLink,
              showWhenUnlinked: false,
              offset: const Offset(-10, 56),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: panelWidth,
                    minWidth: 680,
                  ),
                  child: _buildAdvancedFiltersPanel(
                    categoryOptions: categoryOptions,
                    violationOptions: violationOptions,
                    reporterOptions: reporterOptions,
                    departmentProgramOptions: departmentProgramOptions,
                    outcomeOptions: outcomeOptions,
                    schoolYearOptions: schoolYearOptions,
                    termOptions: termOptions,
                    floating: true,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_advancedFiltersEntry!);
    setState(() => _showAdvancedFilters = true);
  }

  void _applyAdvancedFilters() {
    setState(() {
      _categoryFilter = _draftCategoryFilter;
      _violationTypeFilter = _draftViolationTypeFilter;
      _reporterFilter = _draftReporterFilter;
      _departmentProgramFilter = _draftDepartmentProgramFilter;
      _outcomeFilter = _draftOutcomeFilter;
      _schoolYearFilter = _draftSchoolYearFilter;
      _termFilter = _draftTermFilter;
    });
  }

  void _clearAllFilters() {
    _removeAdvancedFiltersOverlay(updateState: false);
    setState(() {
      _searchCtrl.clear();
      _searchQuery = '';
      _concernFilter = 'All';
      _dateRange = null;
      _categoryFilter = 'All';
      _violationTypeFilter = 'All';
      _reporterFilter = 'All';
      _departmentProgramFilter = 'All';
      _outcomeFilter = 'All';
      _schoolYearFilter = 'All';
      _termFilter = 'All';
      _showAdvancedFilters = false;
    });
  }

  bool _hasActiveFilters() {
    return _searchQuery.isNotEmpty ||
        _concernFilter != 'All' ||
        _dateRange != null ||
        _categoryFilter != 'All' ||
        _violationTypeFilter != 'All' ||
        _reporterFilter != 'All' ||
        _departmentProgramFilter != 'All' ||
        _outcomeFilter != 'All' ||
        _schoolYearFilter != 'All' ||
        _termFilter != 'All';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('violation_cases')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snap.data!.docs;
          final resolvedDocs =
              allDocs
                  .where(
                    (doc) => _isResolvedStatus(_value(doc.data()['status'])),
                  )
                  .toList()
                ..sort((a, b) {
                  final ad = _bestDate(a.data());
                  final bd = _bestDate(b.data());
                  if (ad == null && bd == null) return 0;
                  if (ad == null) return 1;
                  if (bd == null) return -1;
                  return bd.compareTo(ad);
                });

          final categoryOptions = _collectOptions(resolvedDocs, _categoryValue);
          final violationOptions = _collectOptions(
            resolvedDocs,
            _violationTypeValue,
          );
          final reporterOptions = _collectOptions(resolvedDocs, _reporterValue);
          final departmentProgramOptions = _collectOptions(
            resolvedDocs,
            _departmentProgramValue,
          );
          final outcomeOptions = _collectOptions(resolvedDocs, _outcomeValue);
          final schoolYearOptions = _collectOptions(
            resolvedDocs,
            _schoolYearValue,
          );
          final termOptions = _collectOptions(resolvedDocs, _termValue);

          final filtered = resolvedDocs.where((doc) {
            final data = doc.data();
            if (!_matchesSearch(data, doc.id)) return false;
            if (!_matchesConcern(data)) return false;
            if (!_matchesDate(data)) return false;
            if (!_matchesAdvancedFilters(data)) return false;
            return true;
          }).toList();

          QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
          if (_selectedCaseId != null) {
            for (final doc in filtered) {
              if (doc.id == _selectedCaseId) {
                selectedDoc = doc;
                break;
              }
            }
          }

          final screenWidth = MediaQuery.sizeOf(context).width;
          final compactFilters = screenWidth < 920;
          final pageHorizontalPadding =
              ResponsiveLayoutTokens.pageHorizontalPadding(screenWidth);
          final pageMaxWidth = ResponsiveLayoutTokens.contentMaxWidth(
            screenWidth,
          );
          final detailsWidth = screenWidth >= 1720 ? 500.0 : 460.0;
          final headerFilters = <Widget>[
            if (compactFilters)
              _buildCompactFiltersButton(
                onTap: () => _openCompactFiltersSheet(
                  categoryOptions: categoryOptions,
                  violationOptions: violationOptions,
                  reporterOptions: reporterOptions,
                  departmentProgramOptions: departmentProgramOptions,
                  outcomeOptions: outcomeOptions,
                  schoolYearOptions: schoolYearOptions,
                  termOptions: termOptions,
                ),
              ),
            ..._buildHeaderFilterChipWidgets(),
          ];

          return ModernTableLayout(
            showDetails: selectedDoc != null,
            detailsWidth: detailsWidth,
            details: selectedDoc == null
                ? null
                : _RecordDetailsPanel(
                    doc: selectedDoc,
                    onClose: () {
                      setState(() => _selectedCaseId = null);
                    },
                  ),
            header: ModernTableHeader(
              title: 'Violation Records',
              subtitle: 'Resolved cases only',
              searchBar: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search case ID, student name, or violation',
                  prefixIcon: const Icon(Icons.search, color: _primary),
                  filled: true,
                  fillColor: _bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              tabs: compactFilters
                  ? null
                  : _buildDesktopFilterToolbar(
                      categoryOptions: categoryOptions,
                      violationOptions: violationOptions,
                      reporterOptions: reporterOptions,
                      departmentProgramOptions: departmentProgramOptions,
                      outcomeOptions: outcomeOptions,
                      schoolYearOptions: schoolYearOptions,
                      termOptions: termOptions,
                    ),
              filters: headerFilters.isEmpty ? null : headerFilters,
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: pageMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    _buildResultSummary(
                      filtered.length,
                      horizontalPadding: pageHorizontalPadding,
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (filtered.isEmpty) {
                            return _buildEmptyState();
                          }
                          if (constraints.maxWidth >= 900) {
                            return _buildDesktopTable(
                              filtered,
                              horizontalPadding: pageHorizontalPadding,
                            );
                          }
                          return _buildMobileList(
                            filtered,
                            horizontalPadding: pageHorizontalPadding,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopFilterToolbar({
    required List<String> categoryOptions,
    required List<String> violationOptions,
    required List<String> reporterOptions,
    required List<String> departmentProgramOptions,
    required List<String> outcomeOptions,
    required List<String> schoolYearOptions,
    required List<String> termOptions,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildConcernFilter(),
            _buildDateRangeFilter(),
            _buildMoreFiltersButton(
              categoryOptions: categoryOptions,
              violationOptions: violationOptions,
              reporterOptions: reporterOptions,
              departmentProgramOptions: departmentProgramOptions,
              outcomeOptions: outcomeOptions,
              schoolYearOptions: schoolYearOptions,
              termOptions: termOptions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No violation records found.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try adjusting or clearing the filters.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _clearAllFilters,
              child: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConcernFilter() {
    return _toolbarFilterShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _concernFilter,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          items: const [
            DropdownMenuItem(value: 'All', child: Text('Concern: All')),
            DropdownMenuItem(value: 'Basic', child: Text('Concern: Basic')),
            DropdownMenuItem(value: 'Serious', child: Text('Concern: Serious')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _concernFilter = value);
          },
        ),
      ),
    );
  }

  Widget _buildDateRangeFilter() {
    return _toolbarFilterShell(
      child: InkWell(
        onTap: _pickDateRange,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month_rounded, size: 16),
            const SizedBox(width: 8),
            Text(
              'Date: ${_dateRangeLabel(_dateRange)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            if (_dateRange != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: () {
                  setState(() => _dateRange = null);
                },
                child: const Icon(Icons.close_rounded, size: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMoreFiltersButton({
    required List<String> categoryOptions,
    required List<String> violationOptions,
    required List<String> reporterOptions,
    required List<String> departmentProgramOptions,
    required List<String> outcomeOptions,
    required List<String> schoolYearOptions,
    required List<String> termOptions,
  }) {
    return _toolbarFilterShell(
      child: InkWell(
        onTap: () {
          _openAdvancedFiltersSidePanel(
            categoryOptions: categoryOptions,
            reporterOptions: reporterOptions,
            departmentOptions: departmentProgramOptions,
            schoolYearOptions: schoolYearOptions,
            termOptions: termOptions,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded, size: 16),
            const SizedBox(width: 8),
            Text(
              _showAdvancedFilters ? 'Hide Filters' : 'More Filters',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAdvancedFiltersSidePanel({
    required List<String> categoryOptions,
    required List<String> reporterOptions,
    required List<String> departmentOptions,
    required List<String> schoolYearOptions,
    required List<String> termOptions,
  }) async {
    if (_showAdvancedFilters) return;

    var concern = _concernFilter;
    var category = _categoryFilter;
    var reporter = _reporterFilter;
    var department = _departmentProgramFilter;
    var schoolYear = _schoolYearFilter;
    var term = _termFilter;

    setState(() => _showAdvancedFilters = true);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Advanced Filters',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Material(
                color: Colors.transparent,
                child: SafeArea(
                  child: Container(
                    width: 390,
                    margin: const EdgeInsets.fromLTRB(10, 12, 12, 12),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 28,
                          offset: const Offset(-2, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Advanced Filters',
                                style: TextStyle(
                                  color: _textDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Filter resolved records by key attributes.',
                          style: TextStyle(
                            color: _hint,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Divider(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _panelDropdown(
                                  label: 'Concern Type',
                                  value: concern,
                                  options: const ['All', 'Basic', 'Serious'],
                                  onChanged: (v) =>
                                      setModalState(() => concern = v),
                                ),
                                const SizedBox(height: 12),
                                _panelDropdown(
                                  label: 'Category',
                                  value: category,
                                  options: categoryOptions,
                                  onChanged: (v) =>
                                      setModalState(() => category = v),
                                ),
                                const SizedBox(height: 12),
                                _panelDropdown(
                                  label: 'Reporter',
                                  value: reporter,
                                  options: reporterOptions,
                                  onChanged: (v) =>
                                      setModalState(() => reporter = v),
                                ),
                                const SizedBox(height: 12),
                                _panelDropdown(
                                  label: 'Department',
                                  value: department,
                                  options: departmentOptions,
                                  onChanged: (v) =>
                                      setModalState(() => department = v),
                                ),
                                const SizedBox(height: 12),
                                _panelDropdown(
                                  label: 'School Year',
                                  value: schoolYear,
                                  options: schoolYearOptions,
                                  onChanged: (v) =>
                                      setModalState(() => schoolYear = v),
                                ),
                                const SizedBox(height: 12),
                                _panelDropdown(
                                  label: 'Term',
                                  value: term,
                                  options: termOptions,
                                  onChanged: (v) =>
                                      setModalState(() => term = v),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  setState(() {
                                    _concernFilter = concern;
                                    _categoryFilter = category;
                                    _reporterFilter = reporter;
                                    _departmentProgramFilter = department;
                                    _schoolYearFilter = schoolYear;
                                    _termFilter = term;
                                  });
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Apply Filters'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final offsetTween = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        );
        return SlideTransition(
          position: offsetTween.animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );

    if (!mounted) return;
    setState(() => _showAdvancedFilters = false);
  }

  Widget _panelDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    final normalized = _normalizeSelected(value, options);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: const TextStyle(
            color: _textDark,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: normalized,
          isExpanded: true,
          menuMaxHeight: 360,
          decoration: InputDecoration(
            isDense: false,
            filled: true,
            fillColor: _bg.withValues(alpha: 0.7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _primary, width: 1.3),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 13,
            ),
          ),
          items: options
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }

  Widget _buildCompactFiltersButton({required VoidCallback onTap}) {
    return _toolbarFilterShell(
      child: InkWell(
        onTap: onTap,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_rounded, size: 16),
            SizedBox(width: 8),
            Text(
              'Filters',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarFilterShell({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await _showThemedDateRangeDialog(initialRange: _dateRange);
    if (!mounted || picked == null) return;
    setState(() => _dateRange = picked);
  }

  Future<DateTimeRange?> _showThemedDateRangeDialog({
    required DateTimeRange? initialRange,
  }) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5, 1, 1);
    final lastDate = DateTime(now.year + 1, 12, 31);

    final normalizedInitial = initialRange == null
        ? null
        : DateTimeRange(
            start: initialRange.start.isBefore(firstDate)
                ? firstDate
                : initialRange.start,
            end: initialRange.end.isAfter(lastDate)
                ? lastDate
                : initialRange.end,
          );

    DateTime normalizeDay(DateTime date) =>
        DateTime(date.year, date.month, date.day);
    DateTime clampToBounds(DateTime date) {
      if (date.isBefore(firstDate)) return firstDate;
      if (date.isAfter(lastDate)) return lastDate;
      return date;
    }

    DateTime? selectedStart = normalizedInitial == null
        ? null
        : normalizeDay(normalizedInitial.start);
    DateTime? selectedEnd = normalizedInitial == null
        ? null
        : normalizeDay(normalizedInitial.end);
    DateTime focusedDate = clampToBounds(normalizeDay(selectedStart ?? now));
    bool selectingStart = selectedStart == null || selectedEnd != null;

    return showDialog<DateTimeRange>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final canApply = selectedStart != null && selectedEnd != null;
              final activeLabel = selectingStart
                  ? 'Select start date'
                  : 'Select end date';

              void onDatePicked(DateTime date) {
                final picked = normalizeDay(date);
                setModalState(() {
                  focusedDate = picked;
                  if (selectedStart == null ||
                      selectingStart ||
                      selectedEnd != null) {
                    selectedStart = picked;
                    selectedEnd = null;
                    selectingStart = false;
                    return;
                  }
                  if (picked.isBefore(selectedStart!)) {
                    selectedStart = picked;
                    selectedEnd = null;
                    selectingStart = false;
                    return;
                  }
                  selectedEnd = picked;
                  selectingStart = true;
                });
              }

              return Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.date_range_rounded,
                            color: _primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Date Range',
                                style: TextStyle(
                                  color: _textDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Pick a start date and end date.',
                                style: TextStyle(
                                  color: _hint,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: _hint,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.04,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _rangeDateTile(
                            label: 'Start',
                            value: selectedStart,
                            active: selectingStart,
                            onTap: () =>
                                setModalState(() => selectingStart = true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _rangeDateTile(
                            label: 'End',
                            value: selectedEnd,
                            active: !selectingStart,
                            onTap: () =>
                                setModalState(() => selectingStart = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        'Allowed range: ${DateFormat('MMM d, yyyy').format(firstDate)} - ${DateFormat('MMM d, yyyy').format(lastDate)}',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: CalendarDatePicker(
                        initialDate: focusedDate,
                        firstDate: firstDate,
                        lastDate: lastDate,
                        onDateChanged: onDatePicked,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        canApply
                            ? 'Range: ${DateFormat('MMM d, yyyy').format(selectedStart!)} - ${DateFormat('MMM d, yyyy').format(selectedEnd!)}'
                            : activeLabel,
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.black.withValues(alpha: 0.18),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: canApply
                                ? () => Navigator.of(context).pop(
                                    DateTimeRange(
                                      start: selectedStart!,
                                      end: selectedEnd!,
                                    ),
                                  )
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: _primary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Apply',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _rangeDateTile({
    required String label,
    required DateTime? value,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: active ? _primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? _primary.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _hint,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value == null
                  ? 'Not selected'
                  : DateFormat('MMM d, yyyy').format(value),
              style: TextStyle(
                color: value == null ? _hint : _textDark,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCompactFiltersSheet({
    required List<String> categoryOptions,
    required List<String> violationOptions,
    required List<String> reporterOptions,
    required List<String> departmentProgramOptions,
    required List<String> outcomeOptions,
    required List<String> schoolYearOptions,
    required List<String> termOptions,
  }) async {
    var concern = _concernFilter;
    var dateRange = _dateRange;
    var category = _categoryFilter;
    var violationType = _violationTypeFilter;
    var reporter = _reporterFilter;
    var departmentProgram = _departmentProgramFilter;
    var outcome = _outcomeFilter;
    var schoolYear = _schoolYearFilter;
    var term = _termFilter;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            Future<void> pickDate() async {
              final picked = await _showThemedDateRangeDialog(
                initialRange: dateRange,
              );
              if (picked == null) return;
              setModalState(() => dateRange = picked);
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              builder: (context, controller) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: concern,
                        decoration: _fieldDecoration('Concern'),
                        items: const [
                          DropdownMenuItem(value: 'All', child: Text('All')),
                          DropdownMenuItem(
                            value: 'Basic',
                            child: Text('Basic'),
                          ),
                          DropdownMenuItem(
                            value: 'Serious',
                            child: Text('Serious'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setModalState(() => concern = v);
                        },
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: pickDate,
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text('Date: ${_dateRangeLabel(dateRange)}'),
                      ),
                      const SizedBox(height: 14),
                      _advancedDropdownField(
                        label: 'Category',
                        value: category,
                        options: categoryOptions,
                        onChanged: (v) => setModalState(() => category = v),
                      ),
                      _advancedDropdownField(
                        label: 'Violation Type',
                        value: violationType,
                        options: violationOptions,
                        onChanged: (v) =>
                            setModalState(() => violationType = v),
                      ),
                      _advancedDropdownField(
                        label: 'Reporter',
                        value: reporter,
                        options: reporterOptions,
                        onChanged: (v) => setModalState(() => reporter = v),
                      ),
                      _advancedDropdownField(
                        label: 'Department / Program',
                        value: departmentProgram,
                        options: departmentProgramOptions,
                        onChanged: (v) =>
                            setModalState(() => departmentProgram = v),
                      ),
                      _advancedDropdownField(
                        label: 'Outcome',
                        value: outcome,
                        options: outcomeOptions,
                        onChanged: (v) => setModalState(() => outcome = v),
                      ),
                      _advancedDropdownField(
                        label: 'School Year',
                        value: schoolYear,
                        options: schoolYearOptions,
                        onChanged: (v) => setModalState(() => schoolYear = v),
                      ),
                      _advancedDropdownField(
                        label: 'Term',
                        value: term,
                        options: termOptions,
                        onChanged: (v) => setModalState(() => term = v),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _concernFilter = concern;
                                  _dateRange = dateRange;
                                  _categoryFilter = category;
                                  _violationTypeFilter = violationType;
                                  _reporterFilter = reporter;
                                  _departmentProgramFilter = departmentProgram;
                                  _outcomeFilter = outcome;
                                  _schoolYearFilter = schoolYear;
                                  _termFilter = term;
                                });
                                Navigator.of(sheetContext).pop();
                              },
                              child: const Text('Apply Filters'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAdvancedFiltersPanel({
    required List<String> categoryOptions,
    required List<String> violationOptions,
    required List<String> reporterOptions,
    required List<String> departmentProgramOptions,
    required List<String> outcomeOptions,
    required List<String> schoolYearOptions,
    required List<String> termOptions,
    bool floating = false,
  }) {
    final categoryField = _advancedDropdownField(
      label: 'Category',
      value: _draftCategoryFilter,
      options: categoryOptions,
      onChanged: (v) => setState(() => _draftCategoryFilter = v),
    );
    final violationField = _advancedDropdownField(
      label: 'Violation Type',
      value: _draftViolationTypeFilter,
      options: violationOptions,
      onChanged: (v) => setState(() => _draftViolationTypeFilter = v),
    );
    final reporterField = _advancedDropdownField(
      label: 'Reporter',
      value: _draftReporterFilter,
      options: reporterOptions,
      onChanged: (v) => setState(() => _draftReporterFilter = v),
    );
    final departmentField = _advancedDropdownField(
      label: 'Department / Program',
      value: _draftDepartmentProgramFilter,
      options: departmentProgramOptions,
      onChanged: (v) => setState(() => _draftDepartmentProgramFilter = v),
    );
    final outcomeField = _advancedDropdownField(
      label: 'Outcome',
      value: _draftOutcomeFilter,
      options: outcomeOptions,
      onChanged: (v) => setState(() => _draftOutcomeFilter = v),
    );
    final schoolYearField = _advancedDropdownField(
      label: 'School Year',
      value: _draftSchoolYearFilter,
      options: schoolYearOptions,
      onChanged: (v) => setState(() => _draftSchoolYearFilter = v),
    );
    final termField = _advancedDropdownField(
      label: 'Term',
      value: _draftTermFilter,
      options: termOptions,
      onChanged: (v) => setState(() => _draftTermFilter = v),
    );

    return Container(
      margin: floating
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(20, 8, 20, 10),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: floating
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  spreadRadius: 0,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Advanced Filters',
            style: TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w900,
              fontSize: 15.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Refine results using additional fields.',
            style: TextStyle(
              color: _hint,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.black.withValues(alpha: 0.08)),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 900) {
                return Column(
                  children: [
                    _buildAdvancedFilterRow([
                      categoryField,
                      violationField,
                      reporterField,
                    ]),
                    const SizedBox(height: 14),
                    _buildAdvancedFilterRow([
                      departmentField,
                      outcomeField,
                      schoolYearField,
                    ]),
                    const SizedBox(height: 14),
                    _buildAdvancedFilterRow([
                      termField,
                      const SizedBox.shrink(),
                      const SizedBox.shrink(),
                    ]),
                  ],
                );
              }

              if (constraints.maxWidth >= 620) {
                return Column(
                  children: [
                    _buildAdvancedFilterRow([categoryField, violationField]),
                    const SizedBox(height: 12),
                    _buildAdvancedFilterRow([reporterField, departmentField]),
                    const SizedBox(height: 12),
                    _buildAdvancedFilterRow([outcomeField, schoolYearField]),
                    const SizedBox(height: 12),
                    _buildAdvancedFilterRow([
                      termField,
                      const SizedBox.shrink(),
                    ]),
                  ],
                );
              }

              return Column(
                children: [
                  categoryField,
                  const SizedBox(height: 12),
                  violationField,
                  const SizedBox(height: 12),
                  reporterField,
                  const SizedBox(height: 12),
                  departmentField,
                  const SizedBox(height: 12),
                  outcomeField,
                  const SizedBox(height: 12),
                  schoolYearField,
                  const SizedBox(height: 12),
                  termField,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton(
                onPressed: _removeAdvancedFiltersOverlay,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 10),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  _applyAdvancedFilters();
                  _removeAdvancedFiltersOverlay();
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Apply Filters'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _advancedDropdownField({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    final normalized = _normalizeSelected(value, options);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textDark,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: normalized,
          isExpanded: true,
          menuMaxHeight: 360,
          decoration: InputDecoration(
            isDense: false,
            filled: true,
            fillColor: _bg.withValues(alpha: 0.6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _primary, width: 1.3),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 13,
            ),
          ),
          items: options
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }

  Widget _buildAdvancedFilterRow(List<Widget> cells) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          Expanded(child: cells[i]),
          if (i < cells.length - 1) const SizedBox(width: 14),
        ],
      ],
    );
  }

  InputDecoration _fieldDecoration([String? label]) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _buildResultSummary(int count, {required double horizontalPadding}) {
    final hasFilters = _hasActiveFilters();
    final title = count == 0
        ? '0 cases found'
        : 'Showing $count resolved cases';
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(width: 8),
            const Text(
              '•',
              style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            const Text(
              'Filters applied',
              style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildHeaderFilterChipWidgets() {
    final chips = _activeFilterChips();
    if (chips.isEmpty) return const [];

    return [
      ...chips.map(
        (chip) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InputChip(
            label: Text(chip.label),
            onDeleted: chip.onRemove,
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.black.withValues(alpha: 0.14)),
            labelStyle: const TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      TextButton(
        onPressed: _clearAllFilters,
        child: const Text('Clear All Filters'),
      ),
    ];
  }

  List<_FilterChipData> _activeFilterChips() {
    final chips = <_FilterChipData>[];

    if (_searchQuery.isNotEmpty) {
      chips.add(
        _FilterChipData(
          label: 'Search: ${_searchCtrl.text.trim()}',
          onRemove: () {
            setState(() {
              _searchCtrl.clear();
              _searchQuery = '';
            });
          },
        ),
      );
    }

    if (_concernFilter != 'All') {
      chips.add(
        _FilterChipData(
          label: 'Concern: $_concernFilter',
          onRemove: () => setState(() => _concernFilter = 'All'),
        ),
      );
    }

    if (_dateRange != null) {
      chips.add(
        _FilterChipData(
          label: 'Date: ${_dateRangeLabel(_dateRange)}',
          onRemove: () => setState(() => _dateRange = null),
        ),
      );
    }

    void addAdvancedChip(
      String value,
      String allValue,
      String label,
      VoidCallback remover,
    ) {
      if (value == allValue) return;
      chips.add(_FilterChipData(label: '$label: $value', onRemove: remover));
    }

    addAdvancedChip(
      _categoryFilter,
      'All',
      'Category',
      () => setState(() => _categoryFilter = 'All'),
    );
    addAdvancedChip(
      _violationTypeFilter,
      'All',
      'Violation',
      () => setState(() => _violationTypeFilter = 'All'),
    );
    addAdvancedChip(
      _reporterFilter,
      'All',
      'Reporter',
      () => setState(() => _reporterFilter = 'All'),
    );
    addAdvancedChip(
      _departmentProgramFilter,
      'All',
      'Department/Program',
      () => setState(() => _departmentProgramFilter = 'All'),
    );
    addAdvancedChip(
      _outcomeFilter,
      'All',
      'Outcome',
      () => setState(() => _outcomeFilter = 'All'),
    );
    addAdvancedChip(
      _schoolYearFilter,
      'All',
      'School Year',
      () => setState(() => _schoolYearFilter = 'All'),
    );
    addAdvancedChip(
      _termFilter,
      'All',
      'Term',
      () => setState(() => _termFilter = 'All'),
    );

    return chips;
  }

  Widget _buildDesktopTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required double horizontalPadding,
  }) {
    final tablePadding = horizontalPadding.clamp(12.0, 24.0);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(tablePadding, 0, tablePadding, 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: DataTable(
          showCheckboxColumn: false,
          headingRowColor: WidgetStateProperty.all(_bg),
          columnSpacing: 20,
          columns: const [
            DataColumn(
              label: Text(
                'CODE',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _hint,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'STUDENT',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _hint,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'CONCERN',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _hint,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'VIOLATION',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _hint,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'DATE',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _hint,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
          rows: docs.map((doc) {
            final data = doc.data();
            final isSelected = _selectedCaseId == doc.id;
            final code = _caseCode(data, doc.id);
            final studentName = _studentName(data);
            final studentNo = _studentNo(data);
            final concern = _concernValue(data);
            final violation = _violationTypeValue(data);
            final date = _bestDate(data);

            return DataRow(
              selected: isSelected,
              color: WidgetStateProperty.resolveWith<Color?>((_) {
                if (isSelected) return _primary.withValues(alpha: 0.08);
                return null;
              }),
              onSelectChanged: (_) {
                setState(() {
                  _selectedCaseId = isSelected ? null : doc.id;
                });
              },
              cells: [
                DataCell(
                  Text(
                    code,
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          studentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (studentNo != '--')
                          Text(
                            studentNo,
                            style: const TextStyle(
                              color: _hint,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                DataCell(_ConcernPill(concern: concern)),
                DataCell(
                  SizedBox(
                    width: 240,
                    child: Text(
                      violation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    date == null
                        ? '--'
                        : DateFormat('MMM d, yyyy').format(date),
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required double horizontalPadding,
  }) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 16),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data();
        final code = _caseCode(data, doc.id);
        final student = _studentName(data);
        final concern = _concernValue(data);
        final violation = _violationTypeValue(data);
        final date = _bestDate(data);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: () => _openMobileDetails(context, doc),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    student,
                    style: const TextStyle(
                      color: _textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _ConcernPill(concern: concern),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(violation, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  date == null ? '--' : DateFormat('MMM d, yyyy').format(date),
                  style: const TextStyle(
                    color: _hint,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: Text(
              code,
              style: const TextStyle(
                color: _primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMobileDetails(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            children: [
              AppBar(
                elevation: 0,
                backgroundColor: Colors.white,
                foregroundColor: _textDark,
                title: const Text('Case Details (Read-only)'),
                actions: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(14),
                  children: [_RecordDetailsContent(doc: doc)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _matchesSearch(Map<String, dynamic> data, String docId) {
    if (_searchQuery.isEmpty) return true;
    final hay = [
      docId,
      _caseCode(data, docId),
      _studentName(data),
      _studentNo(data),
      _violationTypeValue(data),
    ].join(' ').toLowerCase();
    return hay.contains(_searchQuery);
  }

  bool _matchesConcern(Map<String, dynamic> data) {
    if (_concernFilter == 'All') return true;
    final concern = _concernValue(data).toLowerCase();
    return concern == _concernFilter.toLowerCase();
  }

  bool _matchesDate(Map<String, dynamic> data) {
    if (_dateRange == null) return true;
    final dt = _bestDate(data);
    if (dt == null) return false;
    final from = DateTime(
      _dateRange!.start.year,
      _dateRange!.start.month,
      _dateRange!.start.day,
    );
    final to = DateTime(
      _dateRange!.end.year,
      _dateRange!.end.month,
      _dateRange!.end.day,
      23,
      59,
      59,
      999,
    );
    return !dt.isBefore(from) && !dt.isAfter(to);
  }

  bool _matchesAdvancedFilters(Map<String, dynamic> data) {
    bool same(String selected, String value) {
      if (selected == 'All') return true;
      return selected == value;
    }

    if (!same(_categoryFilter, _categoryValue(data))) return false;
    if (!same(_violationTypeFilter, _violationTypeValue(data))) return false;
    if (!same(_reporterFilter, _reporterValue(data))) return false;
    if (!same(_departmentProgramFilter, _departmentProgramValue(data))) {
      return false;
    }
    if (!same(_outcomeFilter, _outcomeValue(data))) return false;
    if (!same(_schoolYearFilter, _schoolYearValue(data))) return false;
    if (!same(_termFilter, _termValue(data))) return false;
    return true;
  }

  String _dateRangeLabel(DateTimeRange? range) {
    if (range == null) return 'Any';
    final fmt = DateFormat('MMM d, yyyy');
    final start = fmt.format(range.start);
    final end = fmt.format(range.end);
    if (start == end) return start;
    return '$start - $end';
  }

  static List<String> _collectOptions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String Function(Map<String, dynamic>) selector,
  ) {
    final values = <String>{'All'};
    for (final doc in docs) {
      final value = selector(doc.data());
      if (value.isNotEmpty && value != '--') values.add(value);
    }
    final sorted = values.toList();
    final hasAll = sorted.remove('All');
    sorted.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [if (hasAll) 'All', ...sorted];
  }

  static String _normalizeSelected(String value, List<String> options) {
    if (options.contains(value)) return value;
    return options.contains('All') ? 'All' : options.first;
  }

  static String _value(dynamic value) => (value ?? '').toString().trim();

  static bool _isResolvedStatus(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.contains('unresolved')) return false;
    return value.contains('resolved');
  }

  static DateTime? _bestDate(Map<String, dynamic> data) {
    final candidates = [
      data['resolvedAt'],
      data['updatedAt'],
      data['createdAt'],
      data['incidentAt'],
      data['submittedAt'],
    ];
    for (final value in candidates) {
      if (value is Timestamp) return value.toDate();
    }
    return null;
  }

  static String _caseCode(Map<String, dynamic> data, String docId) {
    final caseCode = _value(data['caseCode']);
    if (caseCode.isNotEmpty) return caseCode;
    return docId.length > 8 ? docId.substring(0, 8) : docId;
  }

  static String _studentName(Map<String, dynamic> data) {
    final value = _value(data['studentName']);
    return value.isEmpty ? 'Unknown' : value;
  }

  static String _studentNo(Map<String, dynamic> data) {
    final value = _value(data['studentNo']);
    return value.isEmpty ? '--' : value;
  }

  static String _concernValue(Map<String, dynamic> data) {
    final value = _value(
      data['concern'] ?? data['concernType'] ?? data['reportedConcernType'],
    );
    if (value.isEmpty) return '--';
    final lower = value.toLowerCase();
    if (lower.contains('serious')) return 'Serious';
    if (lower.contains('basic')) return 'Basic';
    return toTitleCase(value);
  }

  static String _categoryValue(Map<String, dynamic> data) {
    final value = _value(
      data['categoryNameSnapshot'] ??
          data['reportedCategoryNameSnapshot'] ??
          data['categoryName'],
    );
    return value.isEmpty ? '--' : value;
  }

  static String _violationTypeValue(Map<String, dynamic> data) {
    final value = _value(
      data['violationTypeLabel'] ??
          data['typeNameSnapshot'] ??
          data['violationNameSnapshot'] ??
          data['violationName'],
    );
    return value.isEmpty ? '--' : value;
  }

  static String _reporterValue(Map<String, dynamic> data) {
    final value = _value(
      data['reportedByName'] ?? data['reporterName'] ?? data['reportedByRole'],
    );
    return value.isEmpty ? '--' : value;
  }

  static String _departmentProgramValue(Map<String, dynamic> data) {
    final dept = _value(
      data['studentDepartment'] ??
          data['studentCollegeId'] ??
          data['department'],
    );
    if (dept.isNotEmpty) return dept;
    final program = _value(
      data['programId'] ??
          data['studentProgramId'] ??
          data['studentProgram'] ??
          data['program'],
    );
    return program.isEmpty ? '--' : program;
  }

  static String _outcomeValue(Map<String, dynamic> data) {
    final value = _value(
      data['outcome'] ??
          data['resolution'] ??
          data['finalAction'] ??
          data['status'],
    );
    return value.isEmpty ? '--' : toTitleCase(value);
  }

  static String _schoolYearValue(Map<String, dynamic> data) {
    final value = _value(
      data['schoolYearName'] ??
          data['schoolYearLabel'] ??
          data['schoolYearId'] ??
          data['syId'],
    );
    return value.isEmpty ? '--' : value;
  }

  static String _termValue(Map<String, dynamic> data) {
    final value = _value(
      data['termName'] ?? data['termLabel'] ?? data['termId'],
    );
    return value.isEmpty ? '--' : value;
  }
}

class _FilterChipData {
  final String label;
  final VoidCallback onRemove;

  const _FilterChipData({required this.label, required this.onRemove});
}

class _ConcernPill extends StatelessWidget {
  final String concern;

  const _ConcernPill({required this.concern});

  @override
  Widget build(BuildContext context) {
    final label = concern.isEmpty || concern == '--'
        ? 'General'
        : toTitleCase(concern);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF1B5E20).withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1B5E20),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _RecordDetailsPanel extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onClose;

  const _RecordDetailsPanel({required this.doc, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF9FBF9),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Case Details (Read-only)',
                    style: TextStyle(
                      color: Color(0xFF1F2A1F),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [_RecordDetailsContent(doc: doc)],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordDetailsContent extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _RecordDetailsContent({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final caseCode = _ViolationRecordsPageState._caseCode(data, doc.id);
    final studentName = _ViolationRecordsPageState._studentName(data);
    final studentNo = _ViolationRecordsPageState._studentNo(data);
    final program = _ViolationRecordsPageState._value(
      data['programId'] ??
          data['studentProgramId'] ??
          data['studentProgram'] ??
          data['program'],
    );
    final concern = _ViolationRecordsPageState._concernValue(data);
    final category = _ViolationRecordsPageState._categoryValue(data);
    final violation = _ViolationRecordsPageState._violationTypeValue(data);
    final reporter = _ViolationRecordsPageState._reporterValue(data);
    final outcome = _ViolationRecordsPageState._outcomeValue(data);
    final narrative = _ViolationRecordsPageState._value(
      data['narrative'] ?? data['description'],
    );
    final reportedAt = _ViolationRecordsPageState._bestDate(data);
    final dateText = reportedAt == null
        ? '--'
        : DateFormat('MMM d, yyyy â€¢ h:mm a').format(reportedAt);
    final studentUid = _ViolationRecordsPageState._value(
      data['studentUid'] ?? data['studentId'] ?? data['reportedStudentUid'],
    );
    final evidenceUrls = _evidenceUrlsFromCase(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailCard(
          title: 'Student Information',
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF1B5E20),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studentName,
                      style: const TextStyle(
                        color: Color(0xFF1F2A1F),
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Student No: $studentNo',
                      style: const TextStyle(
                        color: Color(0xFF6D7F62),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Program: ${program.isEmpty ? '--' : program}',
                      style: const TextStyle(
                        color: Color(0xFF6D7F62),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Incident Summary',
          child: Column(
            children: [
              _kv('Concern', concern),
              const SizedBox(height: 8),
              _kv('Category', category),
              const SizedBox(height: 8),
              _kv('Violation Type', violation),
              const SizedBox(height: 8),
              _kv('Reporter', reporter),
              const SizedBox(height: 8),
              _kv('Outcome', outcome),
              const SizedBox(height: 8),
              _kv('Date Reported', dateText),
              const SizedBox(height: 8),
              _kv('Case Code', caseCode),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Incident Description',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Text(
              narrative.isEmpty ? '--' : narrative,
              style: const TextStyle(
                color: Color(0xFF1F2A1F),
                fontWeight: FontWeight.w600,
                height: 1.4,
                fontSize: 14.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Evidence',
          child: _EvidencePreviewGrid(urls: evidenceUrls),
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Student Case History',
          child: _StudentCaseHistoryCard(
            studentUid: studentUid,
            currentCaseId: doc.id,
          ),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            '$label:',
            style: const TextStyle(
              color: Color(0xFF6D7F62),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1F2A1F),
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _StudentCaseHistoryCard extends StatelessWidget {
  final String studentUid;
  final String currentCaseId;

  const _StudentCaseHistoryCard({
    required this.studentUid,
    required this.currentCaseId,
  });

  @override
  Widget build(BuildContext context) {
    if (studentUid.isEmpty) {
      return const Text(
        'No student history available for this case.',
        style: TextStyle(color: Color(0xFF6D7F62), fontWeight: FontWeight.w700),
      );
    }

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('violation_cases')
          .where('studentUid', isEqualTo: studentUid)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        if (!snap.hasData) {
          return const Text(
            'No history found.',
            style: TextStyle(
              color: Color(0xFF6D7F62),
              fontWeight: FontWeight.w700,
            ),
          );
        }

        final docs =
            snap.data!.docs.where((d) => d.id != currentCaseId).toList()
              ..sort((a, b) {
                final ad = _ViolationRecordsPageState._bestDate(a.data());
                final bd = _ViolationRecordsPageState._bestDate(b.data());
                if (ad == null && bd == null) return 0;
                if (ad == null) return 1;
                if (bd == null) return -1;
                return bd.compareTo(ad);
              });

        if (docs.isEmpty) {
          return const Text(
            'No prior case history for this student.',
            style: TextStyle(
              color: Color(0xFF6D7F62),
              fontWeight: FontWeight.w700,
            ),
          );
        }

        int resolved = 0;
        int unresolved = 0;
        for (final d in docs) {
          final status = _ViolationRecordsPageState._value(d.data()['status']);
          final lower = status.toLowerCase();
          if (lower.contains('resolved') && !lower.contains('unresolved')) {
            resolved += 1;
          } else {
            unresolved += 1;
          }
        }

        final lastDate = _ViolationRecordsPageState._bestDate(
          docs.first.data(),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _info('Total prior cases', '${docs.length}'),
            const SizedBox(height: 8),
            _info('Resolved prior cases', '$resolved'),
            const SizedBox(height: 8),
            _info('Unresolved prior cases', '$unresolved'),
            const SizedBox(height: 8),
            _info(
              'Most recent prior case',
              lastDate == null
                  ? '--'
                  : DateFormat('MMM d, yyyy â€¢ h:mm a').format(lastDate),
            ),
          ],
        );
      },
    );
  }

  Widget _info(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 165,
          child: Text(
            '$label:',
            style: const TextStyle(
              color: Color(0xFF6D7F62),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1F2A1F),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1F2A1F),
              fontWeight: FontWeight.w900,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

List<String> _evidenceUrlsFromCase(Map<String, dynamic> data) {
  final urls = <String>{};

  void addCandidate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return;
    urls.add(raw);
  }

  final evidenceUrls = data['evidenceUrls'];
  if (evidenceUrls is Iterable) {
    for (final item in evidenceUrls) {
      addCandidate(item);
    }
  }

  final evidences = data['evidences'];
  if (evidences is Iterable) {
    for (final item in evidences) {
      if (item is Map) {
        addCandidate(item['url']);
        addCandidate(item['downloadUrl']);
        addCandidate(item['path']);
      } else {
        addCandidate(item);
      }
    }
  }

  final evidence = data['evidence'];
  if (evidence != null) addCandidate(evidence);

  return urls.toList();
}

Future<String?> _resolveEvidenceUrl(String rawUrl) async {
  final source = rawUrl.trim();
  if (source.isEmpty) return null;

  if (source.startsWith('http://') || source.startsWith('https://')) {
    return source;
  }

  try {
    if (source.startsWith('gs://')) {
      return await FirebaseStorage.instance.refFromURL(source).getDownloadURL();
    }
  } catch (_) {}

  try {
    return await FirebaseStorage.instance.ref(source).getDownloadURL();
  } catch (_) {
    return null;
  }
}

bool _looksLikeImageUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.png') ||
      lower.contains('.gif') ||
      lower.contains('.webp') ||
      lower.contains('.bmp') ||
      lower.contains('.svg') ||
      lower.contains('image');
}

class _EvidencePreviewGrid extends StatelessWidget {
  final List<String> urls;

  const _EvidencePreviewGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const Text(
        'No evidence attached.',
        style: TextStyle(color: Color(0xFF6D7F62), fontWeight: FontWeight.w700),
      );
    }

    final count = urls.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Evidence files ($count)',
          style: const TextStyle(
            color: Color(0xFF1F2A1F),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(urls.length, (index) {
            final source = urls[index];
            return InkWell(
              onTap: () async {
                final resolved = await _resolveEvidenceUrl(source);
                if (!context.mounted) return;
                if (resolved == null) return;
                if (_looksLikeImageUrl(resolved)) {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => _EvidenceImageDialog(imageUrl: resolved),
                  );
                  return;
                }
                final uri = Uri.tryParse(resolved);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.10),
                  ),
                ),
                child: FutureBuilder<String?>(
                  future: _resolveEvidenceUrl(source),
                  builder: (context, snap) {
                    final resolved = snap.data;
                    if (resolved != null && _looksLikeImageUrl(resolved)) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.network(
                          resolved,
                          fit: BoxFit.cover,
                          errorBuilder: (_, error, stackTrace) =>
                              _filePlaceholder(index: index),
                        ),
                      );
                    }
                    return _filePlaceholder(index: index);
                  },
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _filePlaceholder({required int index}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.attach_file_rounded,
            color: Color(0xFF1B5E20),
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            '#${index + 1}',
            style: const TextStyle(
              color: Color(0xFF6D7F62),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceImageDialog extends StatelessWidget {
  final String imageUrl;

  const _EvidenceImageDialog({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Evidence Preview',
                    style: TextStyle(
                      color: Color(0xFF1F2A1F),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, stackTrace) => const Center(
                      child: Text(
                        'Unable to preview image.',
                        style: TextStyle(
                          color: Color(0xFF6D7F62),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String toTitleCase(String raw) {
  final clean = raw.trim();
  if (clean.isEmpty) return clean;
  return clean
      .split(RegExp(r'\s+'))
      .map((word) {
        if (word.isEmpty) return word;
        return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
      })
      .join(' ');
}
