import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/violation_case_service.dart';
import '../professor/violation_report_page.dart';
import '../shared/widgets/app_layout_tokens.dart';
import '../shared/widgets/modern_table_layout.dart';

class DepartmentViolationAlertsPage extends StatefulWidget {
  final String? initialSelectedCaseId;

  const DepartmentViolationAlertsPage({super.key, this.initialSelectedCaseId});

  @override
  State<DepartmentViolationAlertsPage> createState() =>
      _DepartmentViolationAlertsPageState();
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
                      errorBuilder: (context, error, stackTrace) =>
                          const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white70,
                                size: 42,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Failed to load profile photo',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
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

class _EvidenceViewerDialog extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _EvidenceViewerDialog({required this.urls, required this.initialIndex});

  @override
  State<_EvidenceViewerDialog> createState() => _EvidenceViewerDialogState();
}

class _EvidenceViewerDialogState extends State<_EvidenceViewerDialog> {
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width > 980 ? 940.0 : size.width * 0.96;
    final dialogHeight = size.height > 760 ? 700.0 : size.height * 0.92;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Text(
                    'Evidence ${_current + 1}/${widget.urls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (_, i) {
                  final url = widget.urls[i];
                  return InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white70,
                                  size: 42,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.urls.length > 1)
              SizedBox(
                height: 74,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.urls.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final active = i == _current;
                    return InkWell(
                      onTap: () {
                        _controller.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 84,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: active ? Colors.white : Colors.white24,
                            width: active ? 2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          widget.urls[i],
                          fit: BoxFit.cover,
                          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white54,
                                ),
                              ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentViolationAlertsPageState
    extends State<DepartmentViolationAlertsPage> {
  static const bg = Colors.white;
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';

  String _statusFilter = 'all';
  String _allAlertsDateFilter = 'all';
  String? _selectedCaseId;
  bool _isRefreshingTable = false;

  @override
  void initState() {
    super.initState();
    _applyInitialSelectedCase(widget.initialSelectedCaseId, updateState: false);
  }

  @override
  void didUpdateWidget(covariant DepartmentViolationAlertsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prev = (oldWidget.initialSelectedCaseId ?? '').trim();
    final next = (widget.initialSelectedCaseId ?? '').trim();
    if (prev == next) return;
    _applyInitialSelectedCase(next, updateState: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyInitialSelectedCase(
    String? rawCaseId, {
    required bool updateState,
  }) {
    final caseId = (rawCaseId ?? '').trim();
    if (updateState) {
      setState(() {
        if (caseId.isEmpty) {
          _selectedCaseId = null;
          return;
        }
        _selectedCaseId = caseId;
      });
      return;
    }

    if (caseId.isEmpty) return;
    _selectedCaseId = caseId;
  }

  DateTime? _toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  String _safeStr(dynamic value) => (value ?? '').toString().trim();

  String _studentName(Map<String, dynamic> userData) {
    final display = _safeStr(userData['displayName']);
    if (display.isNotEmpty) return display;
    final first = _safeStr(userData['firstName']);
    final last = _safeStr(userData['lastName']);
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    return _safeStr(userData['email']);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '--';
    const months = <String>[
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
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  Color _statusColor(String statusRaw) {
    final status = _statusKey(statusRaw);
    if (status == 'resolved') return const Color(0xFF2E7D32);
    if (status == 'action_set') return const Color(0xFF0D47A1);
    if (status == 'submitted' || status == 'under_review') {
      return const Color(0xFFD97706);
    }
    return const Color(0xFF455A64);
  }

  String _statusLabel(String raw) {
    final s = _statusKey(raw);
    if (s.isEmpty) return 'Submitted';
    if (s == 'action_set') return 'Monitoring';
    if (s == 'under_review') return 'Under Review';
    return s
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
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
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    setState(() => _isRefreshingTable = false);
  }

  Future<void> _openViolationReportModal() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        final isDesktop = size.width >= 900;
        final maxWidth = isDesktop ? 1180.0 : size.width - 20;
        final maxHeight = size.height * 0.92;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: maxWidth,
            height: maxHeight,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Report Violation',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: textDark,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Search a student, complete incident details, and submit.',
                              style: TextStyle(
                                color: hint.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.06),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: ViolationReportPage()),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matchesSearch({
    required Map<String, dynamic> data,
    required Map<String, String> studentNameByUid,
    required String needle,
  }) {
    if (needle.isEmpty) return true;
    final studentUid = _safeStr(data['studentUid']);
    final createdAt = _toDate(data['createdAt']);
    final dateText = createdAt == null
        ? ''
        : '${_formatDate(createdAt)} ${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
    final fields = <String>[
      _safeStr(data['caseCode']),
      _safeStr(studentNameByUid[studentUid]),
      _safeStr(data['studentNo']),
      _safeStr(data['status']),
      _safeStr(data['concern'] ?? data['reportedConcernType']),
      _safeStr(
        data['violationTypeLabel'] ??
            data['violationNameSnapshot'] ??
            data['violationName'],
      ),
      _safeStr(data['categoryNameSnapshot'] ?? data['categoryName']),
      _safeStr(data['reportedByName']),
      dateText,
    ];
    return fields.any((field) => field.toLowerCase().contains(needle));
  }

  String _statusKey(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 'submitted';
    if (s == 'under review' || s == 'under_review' || s == 'review') {
      return 'under_review';
    }
    if (s == 'action set' || s == 'action_set') return 'action_set';
    if (s == 'resolved') return 'resolved';
    if (s == 'unresolved') return 'unresolved';
    if (s == 'cancelled' || s == 'canceled') return 'cancelled';
    if (s == 'submitted') return 'submitted';
    return s.replaceAll(' ', '_');
  }

  DateTime? _caseDate(Map<String, dynamic> data) {
    return _toDate(data['createdAt']);
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _startOfWeekMonday(DateTime value) {
    final dayStart = _startOfDay(value);
    final offset = dayStart.weekday - DateTime.monday;
    return dayStart.subtract(Duration(days: offset < 0 ? 6 : offset));
  }

  bool _matchesAllAlertsDateFilter(
    Map<String, dynamic> data,
    String filterKey,
  ) {
    final caseDate = _caseDate(data);
    if (caseDate == null) return filterKey == 'all';
    final now = DateTime.now();

    switch (filterKey) {
      case 'all':
        return true;
      case 'today':
        final dayStart = _startOfDay(now);
        final dayEnd = dayStart.add(const Duration(days: 1));
        return !caseDate.isBefore(dayStart) && caseDate.isBefore(dayEnd);
      case 'week':
        final weekStart = _startOfWeekMonday(now);
        final weekEnd = weekStart.add(const Duration(days: 7));
        return !caseDate.isBefore(weekStart) && caseDate.isBefore(weekEnd);
      default:
        return true;
    }
  }

  String _effectiveMeetingStatusKey(Map<String, dynamic> d) {
    final meetingStatus = _safeStr(d['meetingStatus']).toLowerCase();
    final bookingStatus = _safeStr(d['bookingStatus']).toLowerCase();
    final isMeetingRequired = d['meetingRequired'] == true;
    final hasSchedule = _toDate(d['scheduledAt']) != null;

    if (meetingStatus.contains('completed') ||
        bookingStatus.contains('completed')) {
      return 'completed';
    }
    if (meetingStatus.contains('booking_missed') ||
        meetingStatus.contains('booking missed')) {
      return 'booking_missed';
    }
    final meetingMissed =
        meetingStatus.contains('meeting_missed') ||
        (meetingStatus.contains('missed') &&
            !meetingStatus.contains('booking'));
    if (meetingMissed || bookingStatus.contains('missed')) {
      return 'meeting_missed';
    }

    final scheduledHints =
        hasSchedule ||
        meetingStatus.contains('scheduled') ||
        bookingStatus.contains('booked');
    if (scheduledHints) return 'scheduled';

    final pendingBooking =
        meetingStatus.isEmpty ||
        meetingStatus.contains('pending') ||
        meetingStatus.contains('needs booking') ||
        bookingStatus.contains('pending') ||
        bookingStatus.contains('not_booked');
    if (isMeetingRequired && pendingBooking) return 'needs_booking';

    return 'none';
  }

  bool _matchesMainFilter(Map<String, dynamic> data, String filterKey) {
    final status = _statusKey(_safeStr(data['status']));
    final meetingFlow = _effectiveMeetingStatusKey(data);

    switch (filterKey) {
      case 'all':
        return true;
      case 'under_review':
        if (status == 'resolved' ||
            status == 'unresolved' ||
            status == 'cancelled') {
          return false;
        }
        return meetingFlow != 'needs_booking' && meetingFlow != 'scheduled';
      case 'needs_booking':
        if (status == 'resolved' ||
            status == 'unresolved' ||
            status == 'cancelled') {
          return false;
        }
        return meetingFlow == 'needs_booking';
      case 'scheduled':
        if (status == 'resolved' ||
            status == 'unresolved' ||
            status == 'cancelled') {
          return false;
        }
        return meetingFlow == 'scheduled';
      case 'unresolved':
        return status == 'unresolved' ||
            meetingFlow == 'booking_missed' ||
            meetingFlow == 'meeting_missed';
      case 'resolved':
        return status == 'resolved';
      case 'cancelled':
        return status == 'cancelled';
      default:
        return true;
    }
  }

  Map<String, int> _statusFilterCounts({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required Map<String, String> studentNameByUid,
  }) {
    final needle = _searchQuery;

    int countFor(String key) {
      return docs.where((doc) {
        final data = doc.data();
        return _matchesMainFilter(data, key) &&
            _matchesSearch(
              data: data,
              studentNameByUid: studentNameByUid,
              needle: needle,
            );
      }).length;
    }

    return <String, int>{
      'all': countFor('all'),
      'under_review': countFor('under_review'),
      'needs_booking': countFor('needs_booking'),
      'scheduled': countFor('scheduled'),
      'unresolved': countFor('unresolved'),
      'resolved': countFor('resolved'),
      'cancelled': countFor('cancelled'),
    };
  }

  Widget _statusTabs(Map<String, int> counts) {
    const keys = <String>[
      'all',
      'under_review',
      'needs_booking',
      'scheduled',
      'unresolved',
      'resolved',
      'cancelled',
    ];
    final labels = <String>[
      'All Alerts (${counts['all'] ?? 0})',
      'Under Review (${counts['under_review'] ?? 0})',
      'Needs Booking (${counts['needs_booking'] ?? 0})',
      'Scheduled (${counts['scheduled'] ?? 0})',
      'Unresolved (${counts['unresolved'] ?? 0})',
      'Resolved (${counts['resolved'] ?? 0})',
      'Cancelled (${counts['cancelled'] ?? 0})',
    ];
    final selectedIndex = keys.indexOf(_statusFilter).clamp(0, keys.length - 1);

    return DefaultTabController(
      length: keys.length,
      initialIndex: selectedIndex,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: primary,
        unselectedLabelColor: hint,
        indicatorColor: primary,
        indicatorWeight: 2.6,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        onTap: (index) {
          final next = keys[index];
          if (_statusFilter == next) return;
          setState(() {
            _statusFilter = next;
            _selectedCaseId = null;
          });
        },
        tabs: labels.map((label) => Tab(text: label)).toList(growable: false),
      ),
    );
  }

  Widget _allAlertsDateFilterBar() {
    const options = <(String, String)>[
      ('all', 'All'),
      ('today', 'Today'),
      ('week', 'This week'),
    ];
    const filterRadius = AppRadii.md;

    Widget dateTab(String value, String label) {
      final selected = _allAlertsDateFilter == value;
      return InkWell(
        borderRadius: BorderRadius.circular(filterRadius),
        onTap: () {
          if (_allAlertsDateFilter == value) return;
          setState(() {
            _allAlertsDateFilter = value;
            _selectedCaseId = null;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(filterRadius),
            border: Border.all(
              color: selected
                  ? primary.withValues(alpha: 0.36)
                  : Colors.black.withValues(alpha: 0.10),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? primary : textDark,
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
            for (var i = 0; i < options.length; i++) ...[
              dateTab(options[i].$1, options[i].$2),
              if (i != options.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterCases({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required Map<String, String> studentNameByUid,
  }) {
    final needle = _searchQuery;

    final filtered = docs.where((doc) {
      final d = doc.data();
      if (!_matchesMainFilter(d, _statusFilter)) return false;
      if (_statusFilter == 'all' &&
          !_matchesAllAlertsDateFilter(d, _allAlertsDateFilter)) {
        return false;
      }
      return _matchesSearch(
        data: d,
        studentNameByUid: studentNameByUid,
        needle: needle,
      );
    }).toList();

    filtered.sort((a, b) {
      final ad = _toDate(a.data()['createdAt']) ?? DateTime(2000);
      final bd = _toDate(b.data()['createdAt']) ?? DateTime(2000);
      return bd.compareTo(ad);
    });
    return filtered;
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  String _titleCase(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    return value
        .split(RegExp(r'[\s_-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Widget _readOnlyKv(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            '$label:',
            style: const TextStyle(
              color: hint,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.trim().isEmpty ? '--' : value.trim(),
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _textBlock(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(
        text.trim().isEmpty ? '--' : text.trim(),
        style: const TextStyle(
          color: textDark,
          fontWeight: FontWeight.w600,
          height: 1.4,
          fontSize: 14.5,
        ),
      ),
    );
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _formatTime12(DateTime value) {
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final meridiem = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $meridiem';
  }

  String _weekdayName(int weekday) {
    const names = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final i = weekday - 1;
    if (i < 0 || i >= names.length) return '';
    return names[i];
  }

  String _formatDateTimeSmart(DateTime? value) {
    if (value == null) return '--';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final time = _formatTime12(value);

    if (day == today) {
      return 'Today, $time';
    }

    final startOfWeek = today.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    if ((day.isAtSameMomentAs(startOfWeek) || day.isAfter(startOfWeek)) &&
        day.isBefore(endOfWeek)) {
      return '${_weekdayName(value.weekday)}, $time';
    }

    return '${_formatDate(value)}, $time';
  }

  String _reporterRoleLabel(String rawRole) {
    final role = _safeStr(rawRole).toLowerCase();
    switch (role) {
      case 'professor':
      case 'teacher':
      case 'faculty':
        return 'Teacher';
      case 'guard':
        return 'Guard';
      case 'dean':
        return 'Dean';
      case 'department_admin':
        return 'Department Admin';
      case 'osa_admin':
        return 'OSA Admin';
      case 'counseling_admin':
        return 'Counseling Admin';
      default:
        return role.isEmpty ? '' : _titleCase(role.replaceAll('_', ' '));
    }
  }

  String _reportedByDisplay(Map<String, dynamic> data) {
    final name = _safeStr(data['reportedByName']);
    final role = _reporterRoleLabel(_safeStr(data['reportedByRole']));
    if (name.isEmpty && role.isEmpty) return '--';
    if (name.isEmpty) return role;
    if (role.isEmpty) return name;
    return '$name ($role)';
  }

  Future<String> _studentProfilePhotoFuture(String studentUid) async {
    final uid = studentUid.trim();
    if (uid.isEmpty) return '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      final studentProfile =
          data['studentProfile'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final employeeProfile =
          data['employeeProfile'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final source = _safeStr(
        data['photoUrl'] ??
            data['profilePhotoUrl'] ??
            data['studentProfilePhotoUrl'] ??
            studentProfile['photoUrl'] ??
            studentProfile['profilePhotoUrl'] ??
            employeeProfile['photoUrl'] ??
            employeeProfile['profilePhotoUrl'],
      );
      return _resolveImageSourceUrl(source);
    } catch (_) {
      return '';
    }
  }

  bool _isHttpImageUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  Future<String> _resolveImageSourceUrl(String source) async {
    final value = _safeStr(source);
    if (value.isEmpty) return '';
    if (_isHttpImageUrl(value)) return value;
    try {
      if (value.startsWith('gs://')) {
        return await FirebaseStorage.instance
            .refFromURL(value)
            .getDownloadURL();
      }
      return await FirebaseStorage.instance.ref(value).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  bool _isLikelyPdf(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.pdf') ||
        lower.contains('application/pdf') ||
        lower.contains('contenttype=application%2fpdf');
  }

  Future<String?> _resolveEvidenceUrl(String rawUrl) async {
    final value = rawUrl.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    try {
      if (value.startsWith('gs://')) {
        return await FirebaseStorage.instance
            .refFromURL(value)
            .getDownloadURL();
      }
      if (!value.contains('://')) {
        return await FirebaseStorage.instance.ref(value).getDownloadURL();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _openEvidenceFile(String rawUrl) async {
    final resolved = await _resolveEvidenceUrl(rawUrl);
    if (!mounted) return;
    if (resolved == null || resolved.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open file URL.')));
      return;
    }
    final uri = Uri.tryParse(resolved);
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid file URL.')));
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the file.')));
    }
  }

  Future<void> _openEvidenceViewer(
    List<String> urls, {
    int initialIndex = 0,
  }) async {
    if (urls.isEmpty) return;
    final resolved = <String>[];
    for (final raw in urls) {
      if (_isLikelyPdf(raw)) continue;
      final url = await _resolveEvidenceUrl(raw);
      if (url != null && url.isNotEmpty) {
        resolved.add(url);
      }
    }
    if (resolved.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previewable image evidence found.')),
      );
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _EvidenceViewerDialog(
        urls: resolved,
        initialIndex: initialIndex.clamp(0, resolved.length - 1),
      ),
    );
  }

  Widget _buildEvidenceSection(List<String> urls) {
    if (urls.isEmpty) {
      return const Text(
        'No evidence attached.',
        style: TextStyle(color: hint, fontWeight: FontWeight.w700),
      );
    }

    final count = urls.length;
    final show = count > 6 ? 6 : count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tap an image to view.',
          style: TextStyle(
            color: hint,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(show, (i) {
            final url = urls[i];
            final isPdf = _isLikelyPdf(url);
            final imageUrls = urls.where((u) => !_isLikelyPdf(u)).toList();
            final imageInitialIndex = imageUrls.indexOf(url);
            return InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: () async {
                if (isPdf) {
                  await _openEvidenceFile(url);
                  return;
                }
                await _openEvidenceViewer(
                  imageUrls,
                  initialIndex: imageInitialIndex < 0 ? 0 : imageInitialIndex,
                );
              },
              child: Stack(
                children: [
                  Container(
                    width: 100,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: isPdf
                        ? const Center(
                            child: Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Color(0xFFB71C1C),
                              size: 24,
                            ),
                          )
                        : FutureBuilder<String?>(
                            future: _resolveEvidenceUrl(url),
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primary,
                                    ),
                                  ),
                                );
                              }
                              final resolved = snap.data;
                              if (resolved == null || resolved.isEmpty) {
                                return const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: hint,
                                    size: 22,
                                  ),
                                );
                              }
                              return Image.network(
                                resolved,
                                fit: BoxFit.cover,
                                webHtmlElementStrategy:
                                    WebHtmlElementStrategy.prefer,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: primary,
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) =>
                                    const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: hint,
                                        size: 22,
                                      ),
                                    ),
                              );
                            },
                          ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: const Icon(
                        Icons.open_in_new_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (isPdf)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: const Text(
                          'PDF',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  if (i == show - 1 && count > show)
                    Positioned.fill(
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        child: Text(
                          '+${count - show}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Future<void> _openProfilePhotoViewer({
    required String sourceUrl,
    required String studentName,
  }) async {
    final resolvedUrl = await _resolveImageSourceUrl(sourceUrl);
    if (resolvedUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profile photo available.')),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _ProfilePhotoViewerDialog(
        photoUrl: resolvedUrl,
        studentName: studentName,
      ),
    );
  }

  Widget _detailCard({required String title, required Widget child}) {
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
          Text(
            title,
            style: const TextStyle(
              color: textDark,
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

  Widget _tableHeaderText(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        color: hint,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildConcernPill(String concernRaw) {
    final normalized = concernRaw.trim().toLowerCase();
    final isSerious = normalized.contains('serious');
    final label = normalized.isEmpty ? 'General' : _titleCase(concernRaw);
    final fill = isSerious
        ? Colors.orange.withValues(alpha: 0.10)
        : primary.withValues(alpha: 0.10);
    final border = isSerious
        ? Colors.orange.withValues(alpha: 0.30)
        : primary.withValues(alpha: 0.25);
    final textColor = isSerious ? Colors.orange.shade900 : primary;
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
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildHandbookStyleSearchBar({Widget? compactTrailingAction}) {
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
              Icon(Icons.search_rounded, color: hint, size: iconSize),
              SizedBox(width: isDesktop ? 12 : 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchInputChanged,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: textDark,
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
                      color: hint,
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
                    color: hint.withValues(alpha: 0.85),
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
                    color: hint,
                  ),
                )
              : Icon(
                  Icons.refresh_rounded,
                  color: hint.withValues(alpha: 0.9),
                  size: isDesktop ? 20 : 18,
                ),
        ),
      ),
    );

    Widget searchWithRefresh() {
      return Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 8),
          refreshButton,
          if (!isDesktop && compactTrailingAction != null) ...[
            const SizedBox(width: 8),
            compactTrailingAction,
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

  Widget? _buildFullHeaderActions({
    required bool useCompactHeaderActions,
  }) {
    if (useCompactHeaderActions) return null;
    return OutlinedButton.icon(
      onPressed: _openViolationReportModal,
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.report_rounded, size: 20),
      label: const Text(
        'Report Violation',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );
  }

  Widget? _buildCompactHeaderOptionsButton({
    required bool useCompactHeaderActions,
  }) {
    if (!useCompactHeaderActions) return null;
    return Tooltip(
      message: 'More options',
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.75),
          border: Border.all(color: Colors.black12),
        ),
        child: PopupMenuButton<String>(
          tooltip: 'More options',
          padding: EdgeInsets.zero,
          icon: const Icon(
            Icons.more_horiz_rounded,
            color: hint,
            size: 20,
          ),
          onSelected: (action) {
            if (action == 'report_violation') {
              _openViolationReportModal();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem<String>(
              value: 'report_violation',
              child: Row(
                children: [
                  Icon(Icons.report_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Report Violation'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPane({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String studentUid,
    required String studentName,
    required bool isSheet,
    VoidCallback? onClose,
  }) {
    final d = doc.data();
    final caseCode = _safeStr(d['caseCode']).isEmpty
        ? doc.id
        : _safeStr(d['caseCode']);
    final concern = _safeStr(d['concern'] ?? d['reportedConcernType']);
    final violation = _safeStr(
      d['violationTypeLabel'] ??
          d['violationNameSnapshot'] ??
          d['violationName'],
    );
    final category = _safeStr(d['categoryNameSnapshot']);
    final finalSeverity = _safeStr(
      d['finalSeverity'] ?? d['assessedSeverity'] ?? d['severityLevel'],
    );
    final actionType = _safeStr(d['actionType'] ?? d['actionSelected']);
    final sanctionType = _safeStr(d['sanctionType']);
    final actionReason = _safeStr(d['actionReason'] ?? d['actionNotes']);
    final officialRemarks = _safeStr(d['officialRemarks']);
    final facultyNote = _safeStr(d['facultyNote']);
    final meetingRequired = d['meetingRequired'] == true;
    final meetingStatus = _safeStr(d['meetingStatus']);
    final meetingLocation = _safeStr(d['meetingLocation']);
    final scheduledAt = _toDate(d['scheduledAt']);
    final createdAt = _toDate(d['createdAt']);
    final incidentAt = _toDate(d['incidentAt']);
    final dateReportedText = _formatDateTimeSmart(createdAt);
    final dateOfIncidentText = _formatDateTimeSmart(incidentAt);
    final description = _safeStr(d['description']);
    final studentNo = _safeStr(d['studentNo']);
    final studentProgram = _safeStr(d['studentProgramId'] ?? d['programId']);
    final correctionReason = _safeStr(
      (d['correction'] as Map<String, dynamic>?)?['latestReason'],
    );
    final evidenceUrls = _stringList(d['evidenceUrls']);
    final reportedByText = _reportedByDisplay(d);
    final profilePhotoUrlFromCase = _safeStr(
      d['studentProfilePhotoUrl'] ??
          d['studentPhotoUrl'] ??
          d['profilePhotoUrlSnapshot'],
    );
    final studentPhotoFuture = _studentProfilePhotoFuture(studentUid);
    final evidenceCount = evidenceUrls.length;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailCard(
          title: 'Student Information',
          child: Row(
            children: [
              FutureBuilder<String>(
                future: studentPhotoFuture,
                initialData: profilePhotoUrlFromCase,
                builder: (context, snapshot) {
                  final photoUrl = _safeStr(snapshot.data);
                  return MouseRegion(
                    cursor: photoUrl.isEmpty
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: photoUrl.isEmpty
                          ? null
                          : () => _openProfilePhotoViewer(
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
                              borderRadius: BorderRadius.circular(12),
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
                                    borderRadius: BorderRadius.circular(11),
                                    child: Image.network(
                                      photoUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(
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
                                  borderRadius: BorderRadius.circular(999),
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
                        color: textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Student No: ${studentNo.isEmpty ? '--' : studentNo}',
                      style: const TextStyle(
                        color: hint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Program: ${studentProgram.isEmpty ? '--' : studentProgram}',
                      style: const TextStyle(
                        color: hint,
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
        _detailCard(
          title: 'Incident Summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _readOnlyKv(
                'Concern',
                concern.isEmpty ? '--' : _titleCase(concern),
              ),
              const SizedBox(height: 8),
              _readOnlyKv('Category', category),
              const SizedBox(height: 8),
              _readOnlyKv('Violation Type', violation),
              const SizedBox(height: 8),
              _readOnlyKv('Date Reported', dateReportedText),
              const SizedBox(height: 8),
              _readOnlyKv('Date of Incident', dateOfIncidentText),
              const SizedBox(height: 8),
              _readOnlyKv('Reported By', reportedByText),
              const SizedBox(height: 8),
              _readOnlyKv('Case Code', caseCode),
              if (correctionReason.isNotEmpty ||
                  d['wasCorrectedByOsa'] == true) ...[
                const SizedBox(height: 8),
                _readOnlyKv(
                  'OSA Correction',
                  correctionReason.isNotEmpty
                      ? correctionReason
                      : 'Corrected by OSA (see Case Logs).',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _detailCard(
          title: 'Incident Description',
          child: _textBlock(description),
        ),
        const SizedBox(height: 12),
        _detailCard(
          title: 'Evidence ($evidenceCount)',
          child: _buildEvidenceSection(evidenceUrls),
        ),
        if (finalSeverity.isNotEmpty ||
            actionType.isNotEmpty ||
            sanctionType.isNotEmpty ||
            actionReason.isNotEmpty ||
            officialRemarks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _detailCard(
            title: 'Assessment & Decision',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (finalSeverity.isNotEmpty) ...[
                  _readOnlyKv('Severity', _titleCase(finalSeverity)),
                  const SizedBox(height: 8),
                ],
                if (actionType.isNotEmpty) ...[
                  _readOnlyKv('Action', _titleCase(actionType)),
                  const SizedBox(height: 8),
                ],
                if (sanctionType.isNotEmpty) ...[
                  _readOnlyKv('Sanction Given', _titleCase(sanctionType)),
                  const SizedBox(height: 8),
                ],
                if (actionReason.isNotEmpty) ...[
                  _readOnlyKv('Action Reason', actionReason),
                  const SizedBox(height: 8),
                ],
                if (officialRemarks.isNotEmpty)
                  _readOnlyKv('Official Remarks', officialRemarks),
              ],
            ),
          ),
        ],
        if (meetingRequired ||
            meetingStatus.isNotEmpty ||
            scheduledAt != null ||
            meetingLocation.isNotEmpty) ...[
          const SizedBox(height: 12),
          _detailCard(
            title: 'Meeting Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _readOnlyKv(
                  'Meeting Status',
                  meetingStatus.isEmpty ? 'Not set' : _titleCase(meetingStatus),
                ),
                if (scheduledAt != null) ...[
                  const SizedBox(height: 8),
                  _readOnlyKv('Scheduled At', _formatDate(scheduledAt)),
                ],
                if (meetingLocation.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _readOnlyKv('Meeting Location', meetingLocation),
                ],
              ],
            ),
          ),
        ],
        if (facultyNote.isNotEmpty) ...[
          const SizedBox(height: 12),
          _detailCard(
            title: 'OSA Note to Reporter',
            child: _textBlock(facultyNote),
          ),
        ],
      ],
    );

    if (isSheet) {
      return Container(
        color: bg,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.assignment_outlined, color: primary, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Case Details',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: hint),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                child: body,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Container(
        width: double.infinity,
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          color: primary,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Case Details',
                          style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, color: hint),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMobileDetails({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String studentUid,
    required String studentName,
  }) async {
    if (mounted) {
      setState(() => _selectedCaseId = doc.id);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final reservedTop = media.padding.top + kToolbarHeight + 8;
        final modalHeight = (media.size.height - reservedTop)
            .clamp(420.0, media.size.height * 0.92)
            .toDouble();
        return SafeArea(
          top: false,
          child: SizedBox(
            height: modalHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: _buildDetailPane(
                doc: doc,
                studentUid: studentUid,
                studentName: studentName,
                isSheet: false,
                onClose: () => Navigator.of(sheetContext).pop(),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (_selectedCaseId == doc.id) {
      setState(() => _selectedCaseId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, adminSnap) {
        if (!adminSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final adminData = adminSnap.data!.data() ?? <String, dynamic>{};
        final department = _safeStr(
          adminData['employeeProfile']?['department'],
        );

        if (department.isEmpty) {
          return Center(
            child: Text(
              'No department is assigned to your account.',
              style: TextStyle(color: hint, fontWeight: FontWeight.w700),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'student')
              .where('studentProfile.collegeId', isEqualTo: department)
              .snapshots(),
          builder: (context, studentsSnap) {
            if (!studentsSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final studentsByUid = <String, String>{};
            for (final doc in studentsSnap.data!.docs) {
              final d = doc.data();
              studentsByUid[doc.id] = _studentName(d);
            }

            if (studentsByUid.isEmpty) {
              return Center(
                child: Text(
                  'No students found for department $department.',
                  style: TextStyle(color: hint, fontWeight: FontWeight.w700),
                ),
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ViolationCaseService().streamDepartmentCases(
                studentCollegeId: department,
              ),
              builder: (context, caseSnap) {
                if (!caseSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allCases = caseSnap.data!.docs.where((doc) {
                  final studentUid = _safeStr(doc.data()['studentUid']);
                  return studentsByUid.containsKey(studentUid);
                }).toList();

                final filtered = _filterCases(
                  docs: allCases,
                  studentNameByUid: studentsByUid,
                );
                final statusFilterCounts = _statusFilterCounts(
                  docs: allCases,
                  studentNameByUid: studentsByUid,
                );

                QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
                if (_selectedCaseId != null) {
                  for (final doc in filtered) {
                    if (doc.id == _selectedCaseId) {
                      selectedDoc = doc;
                      break;
                    }
                  }
                }
                if (_selectedCaseId != null && selectedDoc == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _selectedCaseId = null);
                  });
                }

                final width = MediaQuery.sizeOf(context).width;
                final useDesktopTable = width >= 900;
                final showSideDetails = width >= 900;
                final useCompactHeaderActions = width < 760;
                final detailsPaneWidth = (width * 0.33)
                    .clamp(320.0, 420.0)
                    .toDouble();
                final compactHeaderOptions = _buildCompactHeaderOptionsButton(
                  useCompactHeaderActions: useCompactHeaderActions,
                );

                return Container(
                  color: bg,
                  child: ModernTableLayout(
                    detailsWidth: detailsPaneWidth,
                    header: ModernTableHeader(
                      showTitleSection: false,
                      showTopControlsWhenTitleHidden: true,
                      searchBar: _buildHandbookStyleSearchBar(
                        compactTrailingAction: compactHeaderOptions,
                      ),
                      action: _buildFullHeaderActions(
                        useCompactHeaderActions: useCompactHeaderActions,
                      ),
                      tabs: _statusTabs(statusFilterCounts),
                    ),
                    body: _buildBodyWithFilters(
                      filtered: filtered,
                      studentsByUid: studentsByUid,
                      useDesktopTable: useDesktopTable,
                      showSideDetails: showSideDetails,
                    ),
                    showDetails: showSideDetails && selectedDoc != null,
                    details: selectedDoc == null
                        ? null
                        : _buildDetailPane(
                            doc: selectedDoc,
                            studentUid: _safeStr(
                              selectedDoc.data()['studentUid'],
                            ),
                            studentName:
                                studentsByUid[_safeStr(
                                  selectedDoc.data()['studentUid'],
                                )] ??
                                '--',
                            isSheet: false,
                            onClose: () {
                              setState(() {
                                _selectedCaseId = null;
                              });
                            },
                          ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildContent({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered,
    required Map<String, String> studentsByUid,
    required bool useDesktopTable,
    required bool showSideDetails,
  }) {
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text(
              'No cases found',
              style: TextStyle(color: hint, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    if (!useDesktopTable) {
      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final doc = filtered[index];
          final d = doc.data();
          final studentUid = _safeStr(d['studentUid']);
          final studentName = studentsByUid[studentUid] ?? '--';
          final caseCode = _safeStr(d['caseCode']).isEmpty
              ? doc.id
              : _safeStr(d['caseCode']);
          final violation = _safeStr(
            d['violationTypeLabel'] ??
                d['violationNameSnapshot'] ??
                d['violationName'],
          );
          final createdAt = _toDate(d['createdAt']);
          final isSelected = _selectedCaseId == doc.id;

          return GestureDetector(
            onTap: () => _openMobileDetails(
              doc: doc,
              studentUid: studentUid,
              studentName: studentName,
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: isSelected
                    ? primary.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(
                  color: isSelected
                      ? primary
                      : Colors.black.withValues(alpha: 0.05),
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
                                  color: primary,
                                ),
                              ),
                            ),
                            if (createdAt != null)
                              Text(
                                _formatDate(createdAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: hint,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          studentName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: textDark,
                          ),
                        ),
                        Text(
                          violation.isEmpty ? '--' : violation,
                          style: const TextStyle(color: hint, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [Icon(Icons.chevron_right, color: Colors.grey)],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = constraints.maxWidth.toDouble();
              final detailsOpen = _selectedCaseId != null;
              final compactTable = detailsOpen || tableWidth < 1120;
              final showStatusColumn = _statusFilter == 'all';
              final tableHorizontalMargin = compactTable ? 8.0 : 12.0;
              final tableColumnSpacing = compactTable ? 12.0 : 18.0;
              final columnCount = showStatusColumn ? 6 : 5;
              final totalWeight = showStatusColumn
                  ? 1.15 + 2.35 + 1.55 + 2.35 + 1.20 + 1.35
                  : 1.15 + 2.35 + 1.55 + 2.35 + 1.20;
              final usableWidth =
                  (tableWidth -
                          (tableHorizontalMargin * 2) -
                          (tableColumnSpacing * (columnCount - 1)))
                      .clamp(420.0, double.infinity)
                      .toDouble();

              double colWidth(
                double weight,
                double minWidth, {
                double? compactMinWidth,
              }) {
                final value = usableWidth * (weight / totalWeight);
                final effectiveMin = compactTable
                    ? (compactMinWidth ?? minWidth)
                    : minWidth;
                return value < effectiveMin ? effectiveMin : value;
              }

              final caseCellWidth = colWidth(1.15, 100, compactMinWidth: 82);
              final studentCellWidth = colWidth(
                2.35,
                210,
                compactMinWidth: 170,
              );
              final concernCellWidth = colWidth(
                1.55,
                138,
                compactMinWidth: 100,
              );
              final violationCellWidth = colWidth(
                2.35,
                220,
                compactMinWidth: 160,
              );
              final dateCellWidth = colWidth(1.20, 112, compactMinWidth: 92);
              final statusCellWidth = colWidth(1.35, 126, compactMinWidth: 108);
              final columns = <DataColumn>[
                DataColumn(
                  label: SizedBox(
                    width: caseCellWidth,
                    child: _tableHeaderText('CODE'),
                  ),
                ),
                DataColumn(
                  label: SizedBox(
                    width: studentCellWidth,
                    child: _tableHeaderText('STUDENT'),
                  ),
                ),
                DataColumn(
                  label: SizedBox(
                    width: concernCellWidth,
                    child: _tableHeaderText('CONCERN'),
                  ),
                ),
                DataColumn(
                  label: SizedBox(
                    width: violationCellWidth,
                    child: _tableHeaderText('VIOLATION'),
                  ),
                ),
                DataColumn(
                  label: SizedBox(
                    width: dateCellWidth,
                    child: _tableHeaderText('DATE'),
                  ),
                ),
              ];
              if (showStatusColumn) {
                columns.add(
                  DataColumn(
                    label: SizedBox(
                      width: statusCellWidth,
                      child: _tableHeaderText('STATUS'),
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStateProperty.all(bg),
                    horizontalMargin: tableHorizontalMargin,
                    columnSpacing: tableColumnSpacing,
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 56,
                    columns: columns,
                    rows: filtered.map((doc) {
                      final d = doc.data();
                      final selected = _selectedCaseId == doc.id;
                      final studentUid = _safeStr(d['studentUid']);
                      final studentName = studentsByUid[studentUid] ?? '--';
                      final caseCode = _safeStr(d['caseCode']).isEmpty
                          ? doc.id
                          : _safeStr(d['caseCode']);
                      final studentNo = _safeStr(d['studentNo']);
                      final concern = _safeStr(
                        d['concern'] ??
                            d['concernType'] ??
                            d['reportedConcernType'],
                      );
                      final violation = _safeStr(
                        d['violationTypeLabel'] ??
                            d['violationNameSnapshot'] ??
                            d['violationName'],
                      );
                      final statusRaw = _safeStr(d['status']);
                      final createdAt = _toDate(d['createdAt']);
                      final cells = <DataCell>[
                        DataCell(
                          SizedBox(
                            width: caseCellWidth,
                            child: Text(
                              caseCode,
                              style: const TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                                    fontWeight: FontWeight.w700,
                                    color: textDark,
                                  ),
                                ),
                                if (studentNo.isNotEmpty)
                                  Text(
                                    studentNo,
                                    style: const TextStyle(
                                      color: hint,
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
                              child: _buildConcernPill(concern),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: violationCellWidth,
                            child: Text(
                              violation.isEmpty ? '--' : violation,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: dateCellWidth,
                            child: Text(
                              _formatDate(createdAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: hint,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ];
                      if (showStatusColumn) {
                        cells.add(
                          DataCell(
                            SizedBox(
                              width: statusCellWidth,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _chip(
                                  _statusLabel(statusRaw),
                                  _statusColor(statusRaw),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return DataRow(
                        selected: selected,
                        color: WidgetStateProperty.resolveWith((states) {
                          if (selected) return primary.withValues(alpha: 0.08);
                          return null;
                        }),
                        onSelectChanged: (_) {
                          if (showSideDetails) {
                            setState(() {
                              if (_selectedCaseId == doc.id) {
                                _selectedCaseId = null;
                              } else {
                                _selectedCaseId = doc.id;
                              }
                            });
                            return;
                          }

                          _openMobileDetails(
                            doc: doc,
                            studentUid: studentUid,
                            studentName: studentName,
                          );
                        },
                        cells: cells,
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBodyWithFilters({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered,
    required Map<String, String> studentsByUid,
    required bool useDesktopTable,
    required bool showSideDetails,
  }) {
    if (_statusFilter != 'all') {
      return _buildContent(
        filtered: filtered,
        studentsByUid: studentsByUid,
        useDesktopTable: useDesktopTable,
        showSideDetails: showSideDetails,
      );
    }

    final horizontal = useDesktopTable ? 20.0 : 14.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
          child: _allAlertsDateFilterBar(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _buildContent(
            filtered: filtered,
            studentsByUid: studentsByUid,
            useDesktopTable: useDesktopTable,
            showSideDetails: showSideDetails,
          ),
        ),
      ],
    );
  }
}
