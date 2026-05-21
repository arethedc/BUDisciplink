import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:apps/services/link_opener.dart';

import '../../services/violation_case_service.dart';
import '../../services/institution_label_service.dart';
import '../shared/widgets/modern_table_layout.dart';
import '../shared/widgets/app_layout_tokens.dart';
import '../shared/widgets/app_empty_state.dart';
import 'package:apps/services/app_firestore.dart';

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
  final String? initialSelectedCaseCode;

  const ViolationRecordsPage({
    super.key,
    this.initialFilterPreset,
    this.initialSelectedCaseCode,
  });

  @override
  State<ViolationRecordsPage> createState() => _ViolationRecordsPageState();
}

class _ViolationRecordsPageState extends State<ViolationRecordsPage> {
  static const _bg = Colors.white;
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
  String? _selectedCaseCode;
  bool _isRefreshingTable = false;
  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _visibleRecordDocs =
      ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        const [],
      );

  @override
  void initState() {
    super.initState();
    _applyInitialPreset(widget.initialFilterPreset);
    _applyInitialSelectedCase(
      widget.initialSelectedCaseCode,
      updateState: false,
    );
  }

  @override
  void didUpdateWidget(covariant ViolationRecordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initialFilterPreset, widget.initialFilterPreset)) {
      _applyInitialPreset(widget.initialFilterPreset);
    }
    final oldCaseCode = (oldWidget.initialSelectedCaseCode ?? '').trim();
    final newCaseCode = (widget.initialSelectedCaseCode ?? '').trim();
    if (oldCaseCode != newCaseCode) {
      _applyInitialSelectedCase(newCaseCode, updateState: true);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _advancedFiltersEntry?.remove();
    _advancedFiltersEntry = null;
    _visibleRecordDocs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyInitialPreset(ViolationRecordsFilterPreset? preset) {
    if (preset == null) return;

    if (preset.clearExisting) {
      _selectedCaseCode = null;
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

  void _applyInitialSelectedCase(
    String? rawCaseCode, {
    required bool updateState,
  }) {
    final caseCode = (rawCaseCode ?? '').trim();
    if (updateState) {
      setState(() {
        _selectedCaseCode = caseCode.isEmpty ? null : caseCode;
      });
      return;
    }
    if (caseCode.isEmpty) return;
    _selectedCaseCode = caseCode;
  }

  void _onSearchInputChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final next = value.trim().toLowerCase();
      if (_searchQuery == next) return;
      setState(() => _searchQuery = next);
    });
  }

  void _clearSearchQuery() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    if (!mounted) return;
    if (_searchQuery.isNotEmpty) {
      setState(() => _searchQuery = '');
    }
  }

  Future<void> _refreshCurrentTable() async {
    if (_isRefreshingTable || !mounted) return;
    setState(() => _isRefreshingTable = true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _isRefreshingTable = false);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final preferDesktopTable = screenWidth >= 900;
        final detailsWidth = (constraints.maxWidth * 0.33)
            .clamp(320.0, 420.0)
            .toDouble();

        return Scaffold(
          backgroundColor: _bg,
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ViolationCaseService().streamResolvedCases(limit: 1000),
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
                        (doc) =>
                            _isResolvedStatus(_value(doc.data()['status'])),
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

              final categoryOptions = _collectOptions(
                resolvedDocs,
                _categoryValue,
              );
              final violationOptions = _collectOptions(
                resolvedDocs,
                _violationTypeValue,
              );
              final reporterOptions = _collectOptions(
                resolvedDocs,
                _reporterValue,
              );
              final departmentProgramOptions = _collectOptions(
                resolvedDocs,
                _departmentProgramValue,
              );
              final outcomeOptions = _collectOptions(
                resolvedDocs,
                _outcomeValue,
              );
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
              if (_selectedCaseCode != null &&
                  _selectedCaseCode!.isNotEmpty &&
                  !filtered.any(
                    (doc) => _caseCode(doc.data(), doc.id) == _selectedCaseCode,
                  )) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _selectedCaseCode = null);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Invalid or unsupported key. Use a valid violation caseCode.',
                      ),
                    ),
                  );
                });
              }
              _visibleRecordDocs.value = filtered;

              final headerFilters = <Widget>[
                ..._buildHeaderFilterChipWidgets(),
              ];

              return ModernTableLayout(
                detailsWidth: detailsWidth,
                showDetails: _selectedCaseCode != null,
                details: _selectedCaseCode != null
                    ? ValueListenableBuilder<
                        List<QueryDocumentSnapshot<Map<String, dynamic>>>
                      >(
                        valueListenable: _visibleRecordDocs,
                        builder: (context, docs, _) {
                          QueryDocumentSnapshot<Map<String, dynamic>>?
                          selectedDoc;
                          for (final doc in docs) {
                            if (_caseCode(doc.data(), doc.id) ==
                                _selectedCaseCode) {
                              selectedDoc = doc;
                              break;
                            }
                          }
                          if (selectedDoc == null) {
                            return const SizedBox();
                          }
                          return _RecordDetailsPanel(
                            doc: selectedDoc,
                            onClose: () {
                              setState(() => _selectedCaseCode = null);
                            },
                            onOpenCase: (nextDoc) {
                              final nextCode = _caseCode(
                                nextDoc.data(),
                                nextDoc.id,
                              );
                              if (_selectedCaseCode == nextCode) return;
                              setState(() => _selectedCaseCode = nextCode);
                            },
                          );
                        },
                      )
                    : null,
                header: ModernTableHeader(
                  showTitleSection: false,
                  showTopControlsWhenTitleHidden: true,
                  showSearchBar: true,
                  searchBar: _buildHandbookStyleSearchBar(
                    filterAction: _buildMoreFiltersButton(
                      categoryOptions: categoryOptions,
                      violationOptions: violationOptions,
                      reporterOptions: reporterOptions,
                      departmentProgramOptions: departmentProgramOptions,
                      outcomeOptions: outcomeOptions,
                      schoolYearOptions: schoolYearOptions,
                      termOptions: termOptions,
                    ),
                  ),
                  tabs: null,
                  filters: headerFilters.isEmpty ? null : headerFilters,
                ),
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildEmptyState()
                          : preferDesktopTable
                          ? _buildDesktopTable(filtered)
                          : _buildMobileList(filtered),
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

  Widget _buildHandbookStyleSearchBar({Widget? filterAction}) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1000;
    final shouldConstrainWidth = width >= 900;
    final constrainedWidth = width >= 1600
        ? 640.0
        : width >= 1300
        ? 580.0
        : 520.0;
    final height = isDesktop ? 56.0 : 48.0;
    final borderRadius = isDesktop ? 16.0 : 18.0;
    final iconSize = isDesktop ? 24.0 : 22.0;
    final fontSize = isDesktop ? 15.0 : 13.5;
    final hasFilters = _hasActiveFilters();

    final searchField = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchCtrl,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.black12),
            boxShadow: isDesktop
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: _hint, size: iconSize),
              SizedBox(width: isDesktop ? 12 : 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchInputChanged,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: _textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search case, student, violation, date...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: _clearSearchQuery,
                  icon: Icon(
                    Icons.close_rounded,
                    color: _hint.withValues(alpha: 0.85),
                    size: isDesktop ? 20 : 18,
                  ),
                ),
            ],
          ),
        );
      },
    );

    final refreshButton = Tooltip(
      message: 'Refresh table',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _isRefreshingTable ? null : _refreshCurrentTable,
        child: Container(
          width: height,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.75),
            border: Border.all(color: Colors.black12),
            boxShadow: isDesktop
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: _isRefreshingTable
              ? SizedBox(
                  width: isDesktop ? 18 : 16,
                  height: isDesktop ? 18 : 16,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _hint,
                  ),
                )
              : Icon(
                  Icons.refresh_rounded,
                  color: _hint.withValues(alpha: 0.9),
                  size: isDesktop ? 20 : 18,
                ),
        ),
      ),
    );

    Widget searchWithRefresh() {
      return Row(
        children: [
          if (filterAction != null) ...[filterAction, const SizedBox(width: 8)],
          Expanded(child: searchField),
          const SizedBox(width: 8),
          refreshButton,
          if (hasFilters) ...[
            const SizedBox(width: 8),
            _buildClearFiltersIconButton(),
          ],
        ],
      );
    }

    if (!shouldConstrainWidth) return searchWithRefresh();
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: constrainedWidth, child: searchWithRefresh()),
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
      child: _buildMoreFiltersButton(
        categoryOptions: categoryOptions,
        violationOptions: violationOptions,
        reporterOptions: reporterOptions,
        departmentProgramOptions: departmentProgramOptions,
        outcomeOptions: outcomeOptions,
        schoolYearOptions: schoolYearOptions,
        termOptions: termOptions,
      ),
    );
  }

  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.inbox_outlined,
      title: 'No cases found',
      subtitle: 'There are no violation cases for the selected filters.',
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
    return Tooltip(
      message: 'Advanced filters',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          _openAdvancedFiltersSidePanel(
            categoryOptions: categoryOptions,
            violationOptions: violationOptions,
            reporterOptions: reporterOptions,
            departmentOptions: departmentProgramOptions,
            outcomeOptions: outcomeOptions,
            schoolYearOptions: schoolYearOptions,
            termOptions: termOptions,
          );
        },
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hasActiveFilters()
                ? _primary.withValues(alpha: 0.12)
                : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: _hasActiveFilters()
                  ? _primary.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.tune_rounded,
            size: 20,
            color: _hasActiveFilters()
                ? _primary
                : _hint.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _buildClearFiltersIconButton() {
    final hasFilters = _hasActiveFilters();
    return Tooltip(
      message: 'Clear filters',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: hasFilters ? _clearAllFilters : null,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.filter_alt_off_rounded,
            size: 19,
            color: hasFilters
                ? _primary.withValues(alpha: 0.9)
                : _hint.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  Future<void> _openAdvancedFiltersSidePanel({
    required List<String> categoryOptions,
    required List<String> violationOptions,
    required List<String> reporterOptions,
    required List<String> departmentOptions,
    required List<String> outcomeOptions,
    required List<String> schoolYearOptions,
    required List<String> termOptions,
  }) async {
    if (_showAdvancedFilters) return;

    var concern = _concernFilter;
    var dateRange = _dateRange;
    var category = _categoryFilter;
    var violationType = _violationTypeFilter;
    var reporter = _reporterFilter;
    var department = _departmentProgramFilter;
    var outcome = _outcomeFilter;
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
              Future<void> pickDateFrom() async {
                final picked = await _showSingleFilterDatePicker(
                  initialDate: dateRange?.start,
                );
                if (picked == null) return;
                final currentEnd = dateRange?.end;
                setModalState(() {
                  if (currentEnd != null && currentEnd.isBefore(picked)) {
                    dateRange = DateTimeRange(start: picked, end: picked);
                  } else {
                    dateRange = DateTimeRange(
                      start: picked,
                      end: currentEnd ?? picked,
                    );
                  }
                });
              }

              Future<void> pickDateTo() async {
                final picked = await _showSingleFilterDatePicker(
                  initialDate: dateRange?.end ?? dateRange?.start,
                );
                if (picked == null) return;
                final currentStart = dateRange?.start ?? picked;
                setModalState(() {
                  if (picked.isBefore(currentStart)) {
                    dateRange = DateTimeRange(start: picked, end: picked);
                  } else {
                    dateRange = DateTimeRange(start: currentStart, end: picked);
                  }
                });
              }

              return Material(
                color: Colors.transparent,
                child: SafeArea(
                  child: Container(
                    width: 390,
                    margin: const EdgeInsets.fromLTRB(10, 12, 12, 12),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
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
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildDateBoundField(
                                        label: 'Date from',
                                        value: dateRange?.start,
                                        onTap: pickDateFrom,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildDateBoundField(
                                        label: 'Date to',
                                        value: dateRange?.end,
                                        onTap: pickDateTo,
                                      ),
                                    ),
                                  ],
                                ),
                                if (dateRange != null) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          setModalState(() => dateRange = null),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Clear dates'),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'Category',
                                  value: category,
                                  options: categoryOptions,
                                  onChanged: (v) =>
                                      setModalState(() => category = v),
                                ),
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'Violation Type',
                                  value: violationType,
                                  options: violationOptions,
                                  onChanged: (v) =>
                                      setModalState(() => violationType = v),
                                ),
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'Reporter',
                                  value: reporter,
                                  options: reporterOptions,
                                  onChanged: (v) =>
                                      setModalState(() => reporter = v),
                                ),
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'Department',
                                  value: department,
                                  options: departmentOptions,
                                  onChanged: (v) =>
                                      setModalState(() => department = v),
                                ),
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'Outcome',
                                  value: outcome,
                                  options: outcomeOptions,
                                  onChanged: (v) =>
                                      setModalState(() => outcome = v),
                                ),
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'School Year',
                                  value: schoolYear,
                                  options: schoolYearOptions,
                                  onChanged: (v) =>
                                      setModalState(() => schoolYear = v),
                                ),
                                const SizedBox(height: 14),
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
                                    _dateRange = dateRange;
                                    _categoryFilter = category;
                                    _violationTypeFilter = violationType;
                                    _reporterFilter = reporter;
                                    _departmentProgramFilter = department;
                                    _outcomeFilter = outcome;
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
    return DropdownButtonFormField<String>(
      initialValue: normalized,
      isExpanded: true,
      menuMaxHeight: 360,
      decoration: _uniformDropdownDecoration(label: label),
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
    );
  }

  Widget _buildCompactFiltersButton({required VoidCallback onTap}) {
    return Tooltip(
      message: 'Show Filters',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.75),
            border: Border.all(color: Colors.black12),
          ),
          child: Icon(
            Icons.filter_alt_rounded,
            color: _hint.withValues(alpha: 0.9),
            size: 18,
          ),
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
                        borderRadius: BorderRadius.circular(AppRadii.md),
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
            Future<void> pickDateFrom() async {
              final picked = await _showSingleFilterDatePicker(
                initialDate: dateRange?.start,
              );
              if (picked == null) return;
              final currentEnd = dateRange?.end;
              setModalState(() {
                if (currentEnd != null && currentEnd.isBefore(picked)) {
                  dateRange = DateTimeRange(start: picked, end: picked);
                } else {
                  dateRange = DateTimeRange(
                    start: picked,
                    end: currentEnd ?? picked,
                  );
                }
              });
            }

            Future<void> pickDateTo() async {
              final picked = await _showSingleFilterDatePicker(
                initialDate: dateRange?.end ?? dateRange?.start,
              );
              if (picked == null) return;
              final currentStart = dateRange?.start ?? picked;
              setModalState(() {
                if (picked.isBefore(currentStart)) {
                  dateRange = DateTimeRange(start: picked, end: picked);
                } else {
                  dateRange = DateTimeRange(start: currentStart, end: picked);
                }
              });
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
                      _advancedDropdownField(
                        label: 'Concern Type',
                        value: concern,
                        options: const ['All', 'Basic', 'Serious'],
                        onChanged: (v) => setModalState(() => concern = v),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDateBoundField(
                              label: 'Date from',
                              value: dateRange?.start,
                              onTap: pickDateFrom,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildDateBoundField(
                              label: 'Date to',
                              value: dateRange?.end,
                              onTap: pickDateTo,
                            ),
                          ),
                        ],
                      ),
                      if (dateRange != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () =>
                                setModalState(() => dateRange = null),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text('Clear dates'),
                          ),
                        ),
                      ],
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
        borderRadius: BorderRadius.circular(AppRadii.lg),
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
    return DropdownButtonFormField<String>(
      initialValue: normalized,
      isExpanded: true,
      menuMaxHeight: 360,
      decoration: _uniformDropdownDecoration(label: label),
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

  InputDecoration _uniformDropdownDecoration({String? label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
      isDense: false,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _primary.withValues(alpha: 0.20)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _primary.withValues(alpha: 0.20)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    );
  }

  Widget _buildDateBoundField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: InputDecorator(
        decoration: _uniformDropdownDecoration(label: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null
                    ? 'Select date'
                    : DateFormat('MMM d, yyyy').format(value),
                style: TextStyle(
                  color: value == null ? _hint : _textDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.8,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: _hint.withValues(alpha: 0.9),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _showSingleFilterDatePicker({DateTime? initialDate}) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5, 1, 1);
    final lastDate = DateTime(now.year + 1, 12, 31);

    final initial = initialDate == null
        ? now
        : (initialDate.isBefore(firstDate)
              ? firstDate
              : (initialDate.isAfter(lastDate) ? lastDate : initialDate));

    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primary,
              onPrimary: Colors.white,
              onSurface: _textDark,
              surface: Colors.white,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
          child: _buildActiveFilterFieldChip(chip),
        ),
      ),
    ];
  }

  Widget _buildActiveFilterFieldChip(_FilterChipData chip) {
    final raw = chip.label.trim();
    final splitIndex = raw.indexOf(':');
    final hasFieldLabel = splitIndex > 0 && splitIndex < raw.length - 1;
    final fieldLabel = hasFieldLabel ? raw.substring(0, splitIndex).trim() : '';
    final fieldValue = hasFieldLabel
        ? raw.substring(splitIndex + 1).trim()
        : raw;

    return InputChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      onDeleted: chip.onRemove,
      deleteIcon: Icon(
        Icons.close_rounded,
        size: 16,
        color: _primary.withValues(alpha: 0.9),
      ),
      deleteButtonTooltipMessage: 'Remove filter',
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      backgroundColor: const Color(0xFFF7FBF7),
      side: BorderSide(color: _primary.withValues(alpha: 0.25)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      label: RichText(
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            if (hasFieldLabel)
              TextSpan(
                text: '$fieldLabel: ',
                style: const TextStyle(
                  color: _hint,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            TextSpan(
              text: fieldValue,
              style: const TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w800,
                fontSize: 12.8,
              ),
            ),
          ],
        ),
      ),
    );
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
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = constraints.maxWidth;
            final detailsOpen = _selectedCaseCode != null;
            final compactTable = detailsOpen || tableWidth < 1120;
            final tableHorizontalMargin = compactTable ? 8.0 : 12.0;
            final tableColumnSpacing = compactTable ? 12.0 : 20.0;
            const columnCount = 5;
            const totalWeight = 8.6;
            final usableWidth =
                (tableWidth -
                        (tableHorizontalMargin * 2) -
                        (tableColumnSpacing * (columnCount - 1)))
                    .clamp(420.0, double.infinity)
                    .toDouble();
            double colWidth(
              double weight,
              double minWidth,
              double maxWidth, {
              double? compactMinWidth,
              double? compactMaxWidth,
            }) {
              final value = usableWidth * (weight / totalWeight);
              final effectiveMin = compactTable
                  ? (compactMinWidth ?? minWidth)
                  : minWidth;
              final effectiveMax = compactTable
                  ? (compactMaxWidth ?? maxWidth)
                  : maxWidth;
              if (value < effectiveMin) return effectiveMin;
              if (value > effectiveMax) return effectiveMax;
              if (value > maxWidth) return maxWidth;
              return value;
            }

            final codeCellWidth = colWidth(
              1.10,
              98,
              120,
              compactMinWidth: 82,
              compactMaxWidth: 106,
            );
            final studentCellWidth = colWidth(
              2.40,
              210,
              230,
              compactMinWidth: 170,
              compactMaxWidth: 220,
            );
            final concernCellWidth = colWidth(
              1.60,
              138,
              152,
              compactMinWidth: 102,
              compactMaxWidth: 142,
            );
            final violationCellWidth = colWidth(
              2.50,
              220,
              250,
              compactMinWidth: 165,
              compactMaxWidth: 225,
            );
            final dateCellWidth = colWidth(
              1.00,
              126,
              136,
              compactMinWidth: 92,
              compactMaxWidth: 120,
            );

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(_bg),
                  horizontalMargin: tableHorizontalMargin,
                  columnSpacing: tableColumnSpacing,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: codeCellWidth,
                        child: const Text(
                          'CODE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: studentCellWidth,
                        child: const Text(
                          'STUDENT',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: concernCellWidth,
                        child: const Text(
                          'CONCERN',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: violationCellWidth,
                        child: const Text(
                          'VIOLATION',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: dateCellWidth,
                        child: const Text(
                          'DATE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                  rows: docs.map((doc) {
                    final data = doc.data();
                    final code = _caseCode(data, doc.id);
                    final isSelected = _selectedCaseCode == code;
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
                          _selectedCaseCode = isSelected ? null : code;
                        });
                      },
                      cells: [
                        DataCell(
                          SizedBox(
                            width: codeCellWidth,
                            child: Text(
                              code,
                              style: const TextStyle(
                                color: _primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: studentCellWidth,
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
                        DataCell(
                          SizedBox(
                            width: concernCellWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _ConcernPill(concern: concern),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: violationCellWidth,
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
                          SizedBox(
                            width: dateCellWidth,
                            child: Text(
                              date == null
                                  ? '--'
                                  : DateFormat('MMM d, yyyy').format(date),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _hint,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMobileList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final code = _caseCode(doc.data(), doc.id);
        final isSelected = _selectedCaseCode == code;
        return _buildCaseCard(doc.id, doc.data(), isSelected, () {
          setState(() => _selectedCaseCode = code);
          _openMobileDetails(context, doc);
        });
      },
    );
  }

  Widget _buildCaseCard(
    String id,
    Map<String, dynamic> data,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final caseCode = _caseCode(data, id);
    final studentName = _studentName(data);
    final violation = _violationTypeValue(data);
    final concern = _concernValue(data);
    final date = _bestDate(data);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected ? _primary.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(
            color: isSelected ? _primary : Colors.black.withValues(alpha: 0.05),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
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
                          caseCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _primary,
                          ),
                        ),
                      ),
                      if (date != null)
                        Text(
                          DateFormat('MMM d, yyyy').format(date),
                          style: const TextStyle(fontSize: 12, color: _hint),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    studentName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _ConcernPill(concern: concern),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          violation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _hint, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _openMobileDetails(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _RecordDetailsPanel(
              doc: doc,
              onClose: () => Navigator.of(sheetContext).pop(),
              onOpenCase: (nextDoc) async {
                Navigator.of(sheetContext).pop();
                await Future<void>.delayed(const Duration(milliseconds: 120));
                if (!context.mounted) return;
                setState(
                  () =>
                      _selectedCaseCode = _caseCode(nextDoc.data(), nextDoc.id),
                );
                await _openMobileDetails(context, nextDoc);
              },
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (_selectedCaseCode == _caseCode(doc.data(), doc.id)) {
      setState(() => _selectedCaseCode = null);
    }
  }

  bool _matchesSearch(Map<String, dynamic> data, String docId) {
    if (_searchQuery.isEmpty) return true;
    final hay = [
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
      data['incidentAt'],
      data['incidentDate'],
      data['dateOfIncident'],
    ];
    for (final value in candidates) {
      if (value is Timestamp) return value.toDate();
    }
    return null;
  }

  static String _caseCode(Map<String, dynamic> data, String docId) {
    final caseCode = _value(data['caseCode']);
    if (caseCode.isNotEmpty) return caseCode;
    return '';
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
    final normalized = label.toLowerCase().trim();
    final isSerious = normalized.contains('serious');
    final isBasic = normalized.contains('basic');

    final Color fill = isSerious
        ? Colors.orange.withValues(alpha: 0.10)
        : isBasic
        ? const Color(0xFF1B5E20).withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.04);
    final Color border = isSerious
        ? Colors.orange.withValues(alpha: 0.30)
        : isBasic
        ? const Color(0xFF1B5E20).withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.12);
    final Color text = isSerious
        ? Colors.orange.shade900
        : isBasic
        ? const Color(0xFF1B5E20)
        : const Color(0xFF6D7F62);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
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
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>>? onOpenCase;

  const _RecordDetailsPanel({
    required this.doc,
    required this.onClose,
    this.onOpenCase,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        color: Color(0xFF1B5E20),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Violation Details',
                        style: TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF6D7F62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _RecordDetailsContent(doc: doc, onOpenCase: onOpenCase),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordDetailsContent extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>>? onOpenCase;

  const _RecordDetailsContent({required this.doc, this.onOpenCase});

  String _safeStr(dynamic value) => (value ?? '').toString().trim();

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
    final status = _ViolationRecordsPageState._value(data['status']);
    final narrative = _ViolationRecordsPageState._value(
      data['narrative'] ?? data['description'],
    );
    final reportedAt = _tsToDate(data['createdAt']);
    final dateReportedText = reportedAt == null
        ? '--'
        : DateFormat('MMM d, yyyy - h:mm a').format(reportedAt);
    final incidentAt =
        _tsToDate(data['incidentAt']) ??
        _tsToDate(data['incidentDate']) ??
        _tsToDate(data['dateOfIncident']);
    final dateOfIncidentText = incidentAt == null
        ? '--'
        : DateFormat('MMM d, yyyy - h:mm a').format(incidentAt);
    final studentUid = _ViolationRecordsPageState._value(
      data['studentUid'] ?? data['studentId'] ?? data['reportedStudentUid'],
    );
    final studentPhotoFuture = _resolveStudentProfilePhotoUrl(
      studentUid: studentUid,
      caseData: data,
    );
    final evidenceUrls = _evidenceUrlsFromCase(data);
    final offenseFuture = _resolveRecordOffenseIndicator(
      studentUid: studentUid,
      currentCaseId: doc.id,
      currentCategory: category,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailCard(
          title: 'Student Information',
          child: Row(
            children: [
              FutureBuilder<String>(
                key: ValueKey('violation-record-photo-${doc.id}-$studentUid'),
                future: studentPhotoFuture,
                initialData: '',
                builder: (context, snapshot) {
                  final photoUrl = (snapshot.data ?? '').trim();
                  return MouseRegion(
                    cursor: photoUrl.isEmpty
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: photoUrl.isEmpty
                          ? null
                          : () => _openProfilePhotoViewer(
                              context,
                              sourceUrl: photoUrl,
                              studentName: studentName,
                            ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1B5E20,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadii.md),
                              border: Border.all(
                                color: const Color(
                                  0xFF1B5E20,
                                ).withValues(alpha: 0.25),
                              ),
                            ),
                            child: photoUrl.isEmpty
                                ? const Icon(
                                    Icons.person_rounded,
                                    color: Color(0xFF1B5E20),
                                    size: 24,
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.md - 1,
                                    ),
                                    child: Image.network(
                                      photoUrl,
                                      key: ValueKey(photoUrl),
                                      fit: BoxFit.cover,
                                      webHtmlElementStrategy:
                                          WebHtmlElementStrategy.prefer,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.person_rounded,
                                        color: Color(0xFF1B5E20),
                                        size: 24,
                                      ),
                                    ),
                                  ),
                          ),
                          if (photoUrl.isNotEmpty)
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: Container(
                                width: 17,
                                height: 17,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1B5E20),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.pill,
                                  ),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.3,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.open_in_full_rounded,
                                  color: Colors.white,
                                  size: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
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
                    FutureBuilder<String>(
                      future: InstitutionLabelService.resolveProgramLabel(
                        program,
                      ),
                      initialData: '--',
                      builder: (context, snapshot) {
                        final resolvedProgram = _safeStr(snapshot.data).isEmpty
                            ? '--'
                            : _safeStr(snapshot.data);
                        return Text(
                          'Program: $resolvedProgram',
                          style: const TextStyle(
                            color: Color(0xFF6D7F62),
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Violation Summary',
          titleTrailing: FutureBuilder<_RecordOffenseIndicator>(
            future: offenseFuture,
            initialData: const _RecordOffenseIndicator(
              label: '--',
              subtitle: '',
              offenseNumber: 0,
            ),
            builder: (context, snapshot) {
              final indicator =
                  snapshot.data ??
                  const _RecordOffenseIndicator(
                    label: '--',
                    subtitle: '',
                    offenseNumber: 0,
                  );
              final isRepeat = indicator.offenseNumber >= 2;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isRepeat
                      ? Colors.orange.withValues(alpha: 0.12)
                      : const Color(0xFF1B5E20).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: isRepeat
                        ? Colors.orange.withValues(alpha: 0.35)
                        : const Color(0xFF1B5E20).withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  indicator.label,
                  style: TextStyle(
                    color: isRepeat
                        ? Colors.orange.shade800
                        : const Color(0xFF1B5E20),
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
              );
            },
          ),
          child: Column(
            children: [
              _kv('Case Code', caseCode),
              const SizedBox(height: 8),
              _kv('Status', status.isEmpty ? '--' : toTitleCase(status)),
              const SizedBox(height: 8),
              _kv('Concern', concern),
              const SizedBox(height: 8),
              _kv('Category', category),
              const SizedBox(height: 8),
              _kv('Violation Type', violation),
              const SizedBox(height: 8),
              _kv('Date of Incident', dateOfIncidentText),
              const SizedBox(height: 8),
              _kv('Date Reported', dateReportedText),
              const SizedBox(height: 8),
              _kv('Reported By', reporter),
              const SizedBox(height: 8),
              _kv('Description', narrative.isEmpty ? '--' : narrative),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Evidence (${evidenceUrls.length})',
          child: _EvidencePreviewGrid(urls: evidenceUrls),
        ),
        const SizedBox(height: 12),
        _DetailCard(
          title: 'Student Case History',
          child: _StudentCaseHistoryCard(
            studentUid: studentUid,
            currentCaseId: doc.id,
            currentCategory: category,
            onOpenCase: onOpenCase,
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

class _StudentCaseHistoryCard extends StatefulWidget {
  final String studentUid;
  final String currentCaseId;
  final String currentCategory;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>>? onOpenCase;

  const _StudentCaseHistoryCard({
    required this.studentUid,
    required this.currentCaseId,
    required this.currentCategory,
    this.onOpenCase,
  });

  @override
  State<_StudentCaseHistoryCard> createState() =>
      _StudentCaseHistoryCardState();
}

class _StudentCaseHistoryCardState extends State<_StudentCaseHistoryCard> {
  final Set<String> _expandedCategories = <String>{};
  bool _initializedDefaultExpanded = false;

  String _normalizeCategoryKey(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == '--') return 'uncategorized';
    return value;
  }

  String _displayCategoryLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '--') return 'Uncategorized';
    return value;
  }

  DateTime? _historyDate(Map<String, dynamic> data) {
    return _offenseSortDate(data);
  }

  Widget _buildCategoryCard({
    required String categoryKey,
    required String categoryLabel,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> priorCases,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>>
    allCasesInCategory,
    required bool isCurrentCategory,
  }) {
    final isExpanded = _expandedCategories.contains(categoryKey);
    final sortedAll = [...allCasesInCategory]
      ..sort((a, b) {
        final da = _historyDate(a.data()) ?? DateTime(2000);
        final db = _historyDate(b.data()) ?? DateTime(2000);
        final byDate = da.compareTo(db);
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
      });
    final sortedPrior = [...priorCases]
      ..sort((a, b) {
        final da = _historyDate(a.data()) ?? DateTime(2000);
        final db = _historyDate(b.data()) ?? DateTime(2000);
        final byDate = da.compareTo(db);
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
      });

    final totalInCategory = sortedAll.length;
    final currentIndexInCategory = isCurrentCategory
        ? sortedAll.indexWhere((doc) => doc.id == widget.currentCaseId) + 1
        : 0;
    final subtitle = isCurrentCategory
        ? (currentIndexInCategory <= 1
              ? 'Current case appears to be the 1st offense in this category.'
              : 'Current case is the ${_ordinal(currentIndexInCategory)} offense in this category.')
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrentCategory
              ? const Color(0xFF1B5E20).withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove(categoryKey);
                } else {
                  _expandedCategories.add(categoryKey);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$categoryLabel ($totalInCategory)',
                          style: TextStyle(
                            color: isCurrentCategory
                                ? const Color(0xFF1B5E20)
                                : const Color(0xFF1F2A1F),
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFF6D7F62),
                              fontWeight: FontWeight.w700,
                              fontSize: 11.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF1B5E20),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            if (sortedPrior.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No prior offense records yet for this category.',
                  style: TextStyle(
                    color: Color(0xFF6D7F62),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.8,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: sortedPrior
                      .map((caseDoc) {
                        final data = caseDoc.data();
                        final offenseIndex =
                            sortedAll.indexWhere(
                              (doc) => doc.id == caseDoc.id,
                            ) +
                            1;
                        final type =
                            _ViolationRecordsPageState._violationTypeValue(
                              data,
                            );
                        final status = _ViolationRecordsPageState._value(
                          data['status'],
                        );
                        final severity = _ViolationRecordsPageState._value(
                          data['finalSeverity'] ?? data['concern'],
                        );
                        final date = _historyDate(data);
                        final dateText = date == null
                            ? '--'
                            : DateFormat('MMM d, yyyy').format(date);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () {
                              showDialog<void>(
                                context: context,
                                builder: (_) => _HistoryCaseDetailsDialogRecord(
                                  caseDoc: caseDoc,
                                  offenseLabel:
                                      '${_ordinal(offenseIndex)} Offense',
                                  categoryLabel: categoryLabel,
                                  onOpenCase: widget.onOpenCase,
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_ordinal(offenseIndex)} Offense',
                                          style: const TextStyle(
                                            color: Color(0xFF1F2A1F),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          type.isEmpty ? '--' : type,
                                          style: const TextStyle(
                                            color: Color(0xFF1F2A1F),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12.2,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$dateText - ${status.isEmpty ? '--' : toTitleCase(status)}${severity.isEmpty ? '' : ' - ${toTitleCase(severity)}'}',
                                          style: const TextStyle(
                                            color: Color(0xFF6D7F62),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11.1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.onOpenCase != null) ...[
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.open_in_new_rounded,
                                      color: Color(0xFF1B5E20),
                                      size: 16,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.studentUid.isEmpty) {
      return const Text(
        'No student history available for this case.',
        style: TextStyle(color: Color(0xFF6D7F62), fontWeight: FontWeight.w700),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AppFirestore.instance
          .collection('violation_cases')
          .where('studentUid', isEqualTo: widget.studentUid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          );
        }
        final allDocs = snap.data!.docs;
        final activeDocs = allDocs
            .where((doc) => !_isCancelledCase(doc.data()))
            .toList(growable: false);
        final priorDocs = activeDocs
            .where((d) => d.id != widget.currentCaseId)
            .toList(growable: false);

        final groupedByKey =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        final groupedAllByKey =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        final labelsByKey = <String, String>{};

        for (final doc in activeDocs) {
          final rawCategory = _ViolationRecordsPageState._categoryValue(
            doc.data(),
          );
          final categoryKey = _normalizeCategoryKey(rawCategory);
          groupedAllByKey.putIfAbsent(categoryKey, () => []).add(doc);
        }
        for (final doc in priorDocs) {
          final rawCategory = _ViolationRecordsPageState._categoryValue(
            doc.data(),
          );
          final categoryKey = _normalizeCategoryKey(rawCategory);
          final categoryLabel = _displayCategoryLabel(rawCategory);
          groupedByKey.putIfAbsent(categoryKey, () => []).add(doc);
          labelsByKey.putIfAbsent(categoryKey, () => categoryLabel);
        }

        final currentCategoryKey = _normalizeCategoryKey(
          widget.currentCategory,
        );
        final currentCategoryLabel = _displayCategoryLabel(
          widget.currentCategory,
        );
        groupedByKey.putIfAbsent(
          currentCategoryKey,
          () => <QueryDocumentSnapshot<Map<String, dynamic>>>[],
        );
        groupedAllByKey.putIfAbsent(
          currentCategoryKey,
          () => <QueryDocumentSnapshot<Map<String, dynamic>>>[],
        );
        labelsByKey[currentCategoryKey] = currentCategoryLabel;

        if (priorDocs.isEmpty && groupedByKey.length <= 1) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No prior history for this student.',
                style: TextStyle(
                  color: Color(0xFF6D7F62),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        final entries = groupedByKey.entries.toList()
          ..sort((a, b) {
            final aIsCurrent = a.key == currentCategoryKey;
            final bIsCurrent = b.key == currentCategoryKey;
            if (aIsCurrent && !bIsCurrent) return -1;
            if (!aIsCurrent && bIsCurrent) return 1;
            final byCount = b.value.length.compareTo(a.value.length);
            if (byCount != 0) return byCount;
            return a.key.toLowerCase().compareTo(b.key.toLowerCase());
          });

        if (!_initializedDefaultExpanded) {
          _initializedDefaultExpanded = true;
          _expandedCategories.add(currentCategoryKey);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Offense history is grouped by category and excludes cancelled cases.',
                style: TextStyle(
                  color: Color(0xFF6D7F62),
                  fontWeight: FontWeight.w700,
                  fontSize: 11.8,
                ),
              ),
            ),
            ...entries.map((entry) {
              final categoryKey = entry.key;
              final priorCases = entry.value;
              final allCasesInCategory =
                  groupedAllByKey[categoryKey] ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final categoryLabel =
                  labelsByKey[categoryKey] ??
                  _displayCategoryLabel(categoryKey);
              return _buildCategoryCard(
                categoryKey: categoryKey,
                categoryLabel: categoryLabel,
                priorCases: priorCases,
                allCasesInCategory: allCasesInCategory,
                isCurrentCategory: categoryKey == currentCategoryKey,
              );
            }),
          ],
        );
      },
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final Widget? titleTrailing;
  final Widget child;

  const _DetailCard({
    required this.title,
    this.titleTrailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF8),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
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
                    color: Color(0xFF1F2A1F),
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ),
              if (titleTrailing != null) ...[
                const SizedBox(width: 8),
                titleTrailing!,
              ],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _HistoryCaseDetailsDialogRecord extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> caseDoc;
  final String offenseLabel;
  final String categoryLabel;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>>? onOpenCase;

  const _HistoryCaseDetailsDialogRecord({
    required this.caseDoc,
    required this.offenseLabel,
    required this.categoryLabel,
    this.onOpenCase,
  });

  static Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 122,
          child: Text(
            '$k:',
            style: const TextStyle(
              color: Color(0xFF6D7F62),
              fontWeight: FontWeight.w900,
              fontSize: 12.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              color: Color(0xFF1F2A1F),
              fontWeight: FontWeight.w700,
              fontSize: 12.4,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = caseDoc.data();
    final caseCode = _ViolationRecordsPageState._caseCode(d, caseDoc.id);
    final violation = _ViolationRecordsPageState._violationTypeValue(d);
    final status = _ViolationRecordsPageState._value(d['status']);
    final severity = _ViolationRecordsPageState._value(
      d['finalSeverity'] ?? d['concern'],
    );
    final reportedAt = _tsToDate(d['createdAt']);
    final incidentAt =
        _tsToDate(d['incidentAt']) ??
        _tsToDate(d['incidentDate']) ??
        _tsToDate(d['dateOfIncident']);
    final reportedBy = _ViolationRecordsPageState._reporterValue(d);
    final narrative = _ViolationRecordsPageState._value(
      d['narrative'] ?? d['description'],
    );

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              offenseLabel,
              style: const TextStyle(
                color: Color(0xFF1B5E20),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: Color(0xFF6D7F62)),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Case Code', caseCode),
              const SizedBox(height: 8),
              _kv('Category', categoryLabel),
              const SizedBox(height: 8),
              _kv('Violation Type', violation.isEmpty ? '--' : violation),
              const SizedBox(height: 8),
              _kv('Status', status.isEmpty ? '--' : toTitleCase(status)),
              const SizedBox(height: 8),
              _kv('Severity', severity.isEmpty ? '--' : toTitleCase(severity)),
              const SizedBox(height: 8),
              _kv(
                'Date Reported',
                reportedAt == null
                    ? '--'
                    : DateFormat('MMM d, yyyy - h:mm a').format(reportedAt),
              ),
              const SizedBox(height: 8),
              _kv(
                'Date of Incident',
                incidentAt == null
                    ? '--'
                    : DateFormat('MMM d, yyyy - h:mm a').format(incidentAt),
              ),
              const SizedBox(height: 8),
              _kv('Reported By', reportedBy),
              if (narrative.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Incident Summary',
                  style: TextStyle(
                    color: Color(0xFF6D7F62),
                    fontWeight: FontWeight.w900,
                    fontSize: 12.2,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    narrative,
                    style: const TextStyle(
                      color: Color(0xFF1F2A1F),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.4,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        if (onOpenCase != null)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onOpenCase?.call(caseDoc);
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open Case'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1B5E20),
              side: BorderSide(
                color: const Color(0xFF1B5E20).withValues(alpha: 0.35),
              ),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _RecordOffenseIndicator {
  final String label;
  final String subtitle;
  final int offenseNumber;

  const _RecordOffenseIndicator({
    required this.label,
    required this.subtitle,
    required this.offenseNumber,
  });
}

Future<_RecordOffenseIndicator> _resolveRecordOffenseIndicator({
  required String studentUid,
  required String currentCaseId,
  required String currentCategory,
}) async {
  if (studentUid.isEmpty ||
      currentCategory.trim().isEmpty ||
      currentCategory == '--') {
    return const _RecordOffenseIndicator(
      label: '--',
      subtitle: 'No category available for offense progression.',
      offenseNumber: 0,
    );
  }

  final snap = await AppFirestore.instance
      .collection('violation_cases')
      .where('studentUid', isEqualTo: studentUid)
      .get();

  final activeCases = snap.docs
      .where((d) => !_isCancelledCase(d.data()))
      .toList();
  final key = currentCategory.trim().toLowerCase();
  final sameCategory =
      activeCases.where((d) {
        final category = _ViolationRecordsPageState._categoryValue(
          d.data(),
        ).trim().toLowerCase();
        return category == key;
      }).toList()..sort((a, b) {
        final ad = _offenseSortDate(a.data()) ?? DateTime(2000);
        final bd = _offenseSortDate(b.data()) ?? DateTime(2000);
        return ad.compareTo(bd);
      });

  if (sameCategory.isEmpty) {
    return const _RecordOffenseIndicator(
      label: '--',
      subtitle: 'No prior offense records in this category.',
      offenseNumber: 0,
    );
  }

  final idx = sameCategory.indexWhere((d) => d.id == currentCaseId);
  final offenseNumber = idx >= 0 ? idx + 1 : sameCategory.length;
  final label = '${_ordinal(offenseNumber)} Offense';
  final subtitle = offenseNumber <= 1
      ? 'This appears to be the first recorded offense in this category.'
      : 'Current case is the $label in this category.';

  return _RecordOffenseIndicator(
    label: label,
    subtitle: subtitle,
    offenseNumber: offenseNumber,
  );
}

bool _isCancelledCase(Map<String, dynamic> data) {
  final status = _ViolationRecordsPageState._value(
    data['status'],
  ).toLowerCase();
  return status.contains('cancel');
}

DateTime? _offenseSortDate(Map<String, dynamic> data) {
  return _tsToDate(data['incidentAt']) ??
      _tsToDate(data['incidentDate']) ??
      _tsToDate(data['dateOfIncident']);
}

DateTime? _tsToDate(dynamic value) =>
    value is Timestamp ? value.toDate() : null;

String _ordinal(int value) {
  final v = value.abs();
  final mod100 = v % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${value}th';
  switch (v % 10) {
    case 1:
      return '${value}st';
    case 2:
      return '${value}nd';
    case 3:
      return '${value}rd';
    default:
      return '${value}th';
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

Future<String> _resolveImageSourceUrl(String source) async {
  final raw = source.trim();
  if (raw.isEmpty) return '';
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    if (raw.contains('firebasestorage.googleapis.com') ||
        raw.contains('firebasestorage.app')) {
      try {
        return await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }
  final resolved = await _resolveEvidenceUrl(raw);
  return resolved ?? '';
}

Future<String> _resolveStudentProfilePhotoUrl({
  required String studentUid,
  required Map<String, dynamic> caseData,
}) async {
  String pickCaseValue() {
    final candidates = [
      caseData['studentPhotoUrl'],
      caseData['studentProfilePhotoUrl'],
      caseData['photoUrl'],
      caseData['profilePhotoUrl'],
      caseData['reportedStudentPhotoUrl'],
    ];
    for (final value in candidates) {
      final v = (value ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  final fromCase = pickCaseValue();
  if (fromCase.isNotEmpty) {
    final resolved = await _resolveImageSourceUrl(fromCase);
    if (resolved.isNotEmpty) return resolved;
  }

  final uid = studentUid.trim();
  if (uid.isEmpty) return '';

  try {
    final userDoc = await AppFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final userData = userDoc.data() ?? const <String, dynamic>{};
    final studentProfile =
        userData['studentProfile'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final employeeProfile =
        userData['employeeProfile'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final source =
        (userData['photoUrl'] ??
                userData['profilePhotoUrl'] ??
                studentProfile['photoUrl'] ??
                studentProfile['profilePhotoUrl'] ??
                employeeProfile['photoUrl'] ??
                employeeProfile['profilePhotoUrl'] ??
                '')
            .toString()
            .trim();
    if (source.isEmpty) return '';
    return _resolveImageSourceUrl(source);
  } catch (_) {
    return '';
  }
}

Future<void> _openProfilePhotoViewer(
  BuildContext context, {
  required String sourceUrl,
  required String studentName,
}) async {
  final resolvedUrl = await _resolveImageSourceUrl(sourceUrl);
  if (resolvedUrl.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _ProfilePhotoViewerDialog(
      photoUrl: resolvedUrl,
      studentName: studentName,
    ),
  );
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
                  await LinkOpener.openExternal(uri);
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
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

class _ProfilePhotoViewerDialog extends StatelessWidget {
  final String photoUrl;
  final String studentName;

  const _ProfilePhotoViewerDialog({
    required this.photoUrl,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width > 760 ? 640.0 : size.width * 0.94;
    final dialogHeight = size.height > 620 ? 560.0 : size.height * 0.88;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      studentName.isEmpty ? 'Profile Photo' : studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.contain,
                      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 42,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Unable to load profile photo.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
