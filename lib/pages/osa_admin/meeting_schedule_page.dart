import 'package:apps/services/osa_meeting_schedule_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum _GenerateMode { cancel, resetAndGenerate }

enum _ScheduleMainTab { templateSetup, openSlots }

class MeetingSchedulePage extends StatefulWidget {
  final OsaMeetingScheduleService? service;
  final String title;

  const MeetingSchedulePage({
    super.key,
    this.service,
    this.title = 'OSA Meeting Schedule',
  });

  @override
  State<MeetingSchedulePage> createState() => _MeetingSchedulePageState();
}

class _MeetingSchedulePageState extends State<MeetingSchedulePage> {
  static const _bg = Color(0xFFF6FAF6);
  static const _primary = Color(0xFF1B5E20);
  static const _hint = Color(0xFF6D7F62);
  static const _text = Color(0xFF1F2A1F);

  late final OsaMeetingScheduleService _svc;
  String? _activeSchoolYearId;
  String? _activeSchoolYearLabel;
  String? _activeTermId;
  DateTime? _activeTermStart;
  DateTime? _activeTermEnd;
  final List<String> _blockedDateKeys = [];
  final TextEditingController _blockedHourStartCtrl = TextEditingController(
    text: '12:00',
  );
  final TextEditingController _blockedHourEndCtrl = TextEditingController(
    text: '13:00',
  );
  final Map<String, bool> _blockedHourDaySelection = {
    'mon': false,
    'tue': false,
    'wed': false,
    'thu': false,
    'fri': false,
  };
  final Map<String, List<Map<String, String>>> _weeklyBlockedWindows = {
    'mon': [],
    'tue': [],
    'wed': [],
    'thu': [],
    'fri': [],
  };
  int _contextLoadToken = 0;

  final Map<String, TextEditingController> _startCtrls = {
    'mon': TextEditingController(text: '08:00'),
    'tue': TextEditingController(text: '08:00'),
    'wed': TextEditingController(text: '08:00'),
    'thu': TextEditingController(text: '08:00'),
    'fri': TextEditingController(text: '08:00'),
  };
  final Map<String, TextEditingController> _endCtrls = {
    'mon': TextEditingController(text: '17:00'),
    'tue': TextEditingController(text: '17:00'),
    'wed': TextEditingController(text: '17:00'),
    'thu': TextEditingController(text: '17:00'),
    'fri': TextEditingController(text: '17:00'),
  };
  final Map<String, bool> _enabledDays = {
    'mon': true,
    'tue': true,
    'wed': true,
    'thu': true,
    'fri': true,
  };
  final Map<String, String?> _dayErrors = {
    'mon': null,
    'tue': null,
    'wed': null,
    'thu': null,
    'fri': null,
  };

  bool _saving = false;
  bool _generating = false;
  int? _lastGeneratedCount;
  _ScheduleMainTab _mainTab = _ScheduleMainTab.templateSetup;
  bool _slotSelectionMode = false;
  final Set<String> _selectedOpenSlotIds = <String>{};
  bool _closingSelectedSlots = false;

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? OsaMeetingScheduleService();
    _loadActiveAcademicContext();
  }

  @override
  void dispose() {
    for (final ctrl in _startCtrls.values) {
      ctrl.dispose();
    }
    for (final ctrl in _endCtrls.values) {
      ctrl.dispose();
    }
    _blockedHourStartCtrl.dispose();
    _blockedHourEndCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadActiveAcademicContext() async {
    final token = ++_contextLoadToken;
    final snap = await FirebaseFirestore.instance
        .collection('academic_years')
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (!mounted || token != _contextLoadToken) return;
    final activeDoc = snap.docs.isEmpty ? null : snap.docs.first;
    await _applyActiveAcademicDoc(activeDoc);
  }

  Future<void> _applyActiveAcademicDoc(
    QueryDocumentSnapshot<Map<String, dynamic>>? activeDoc,
  ) async {
    final token = ++_contextLoadToken;
    if (!mounted || token != _contextLoadToken) return;

    if (activeDoc == null) {
      setState(() {
        _activeSchoolYearId = null;
        _activeSchoolYearLabel = null;
        _activeTermId = null;
        _activeTermStart = null;
        _activeTermEnd = null;
        _blockedDateKeys.clear();
        _selectedOpenSlotIds.clear();
        for (final day in _weeklyBlockedWindows.keys) {
          _weeklyBlockedWindows[day] = [];
          _blockedHourDaySelection[day] = false;
        }
      });
      return;
    }

    final data = activeDoc.data();
    final activeSchoolYearId = activeDoc.id;
    final activeSchoolYearLabel = (data['label'] ?? activeDoc.id)
        .toString()
        .trim();
    final activeTermId = (data['activeTermId'] ?? 'term1').toString().trim();

    final template = await _svc.getTermScheduleTemplate(
      schoolYearId: activeSchoolYearId,
      termId: activeTermId,
    );
    final termDoc = await activeDoc.reference
        .collection('terms')
        .doc(activeTermId)
        .get();
    if (!mounted || token != _contextLoadToken) return;

    _setBlockedDatesFromList(
      template?['blockedDates'] as List<dynamic>? ?? const [],
    );
    _setRecurringBlockedWindowsFromMap(
      template?['recurringBlockedWindows'] as Map<String, dynamic>? ?? const {},
    );

    final hasTemplate = template != null;
    final weekly = template?['weeklyWindows'] as Map<String, dynamic>? ?? {};
    for (final day in _enabledDays.keys) {
      if (!hasTemplate) {
        _enabledDays[day] = true;
        _startCtrls[day]!.text = '08:00';
        _endCtrls[day]!.text = '17:00';
        continue;
      }
      final windows = (weekly[day] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      if (windows.isEmpty) {
        _enabledDays[day] = false;
        _startCtrls[day]!.text = '08:00';
        _endCtrls[day]!.text = '17:00';
      } else {
        _enabledDays[day] = true;
        final first = windows.first;
        _startCtrls[day]!.text = (first['start'] ?? '08:00').toString();
        _endCtrls[day]!.text = (first['end'] ?? '17:00').toString();
      }
    }

    setState(() {
      _activeSchoolYearId = activeSchoolYearId;
      _activeSchoolYearLabel = activeSchoolYearLabel;
      _activeTermId = activeTermId;
      final termData = termDoc.data() ?? {};
      _activeTermStart = _toDate(termData['startAt']);
      _activeTermEnd = _toDate(termData['endAt']);
      _constrainBlockedDatesToActiveTerm();
      _revalidateAllDays();
      _selectedOpenSlotIds.clear();
    });
  }

  TimeOfDay? _parse24(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _to24(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _toReadable(String value) {
    final t = _parse24(value);
    if (t == null) return '--';
    final dt = DateTime(2000, 1, 1, t.hour, t.minute);
    return DateFormat('h:mm a').format(dt);
  }

  String? _validateDay(String dayKey) {
    if (_enabledDays[dayKey] != true) return null;
    final start = _parse24(_startCtrls[dayKey]!.text);
    final end = _parse24(_endCtrls[dayKey]!.text);
    if (start == null || end == null) {
      return 'Invalid time format.';
    }
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      return 'End time must be after start time.';
    }
    return null;
  }

  void _revalidateAllDays() {
    for (final day in _enabledDays.keys) {
      _dayErrors[day] = _validateDay(day);
    }
  }

  bool _validateAllDaysWithFeedback() {
    _revalidateAllDays();
    final hasError = _dayErrors.values.any((v) => v != null && v.isNotEmpty);
    if (hasError && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix invalid day schedules before saving.'),
        ),
      );
      return false;
    }
    setState(() {});
    return true;
  }

  Future<void> _pickTime({
    required String dayKey,
    required bool isStart,
  }) async {
    if (_enabledDays[dayKey] != true) return;
    final ctrl = isStart ? _startCtrls[dayKey]! : _endCtrls[dayKey]!;
    final initial =
        _parse24(ctrl.text) ?? TimeOfDay(hour: isStart ? 8 : 17, minute: 0);
    final selected = await _showModernTimePicker(
      initialTime: initial,
      helpText: isStart ? 'Select Start Time' : 'Select End Time',
    );
    if (selected == null) return;
    setState(() {
      ctrl.text = _to24(selected);
      _dayErrors[dayKey] = _validateDay(dayKey);
    });
  }

  Map<String, List<Map<String, String>>> _buildWeeklyWindows() {
    final out = <String, List<Map<String, String>>>{};
    for (final day in _enabledDays.keys) {
      if (_enabledDays[day] != true) continue;
      final start = _startCtrls[day]!.text.trim();
      final end = _endCtrls[day]!.text.trim();
      final startParsed = _parse24(start);
      final endParsed = _parse24(end);
      if (startParsed == null || endParsed == null) continue;
      final sMinutes = startParsed.hour * 60 + startParsed.minute;
      final eMinutes = endParsed.hour * 60 + endParsed.minute;
      if (eMinutes <= sMinutes) continue;
      out[day] = [
        {'start': start, 'end': end},
      ];
    }
    return out;
  }

  List<String> _blockedDates() => List<String>.from(_blockedDateKeys);

  void _setRecurringBlockedWindowsFromMap(Map<String, dynamic> raw) {
    for (final day in _weeklyBlockedWindows.keys) {
      final windows = (raw[day] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((v) => Map<String, String>.from(v))
          .where(
            (window) =>
                _parse24((window['start'] ?? '').toString()) != null &&
                _parse24((window['end'] ?? '').toString()) != null,
          )
          .toList();
      windows.sort((a, b) => a['start']!.compareTo(b['start']!));
      _weeklyBlockedWindows[day] = windows;
      _blockedHourDaySelection[day] = false;
    }
  }

  Map<String, List<Map<String, String>>> _buildRecurringBlockedWindows() {
    final out = <String, List<Map<String, String>>>{};
    for (final day in _weeklyBlockedWindows.keys) {
      final windows = _weeklyBlockedWindows[day] ?? const [];
      if (windows.isEmpty) continue;
      out[day] = windows
          .map(
            (window) => {
              'start': (window['start'] ?? '').trim(),
              'end': (window['end'] ?? '').trim(),
            },
          )
          .where(
            (window) =>
                _parse24(window['start'] ?? '') != null &&
                _parse24(window['end'] ?? '') != null,
          )
          .toList();
    }
    return out;
  }

  String? _validateBlockedHourRange(String start, String end) {
    final parsedStart = _parse24(start);
    final parsedEnd = _parse24(end);
    if (parsedStart == null || parsedEnd == null) {
      return 'Invalid blocked hour format.';
    }
    final startMinutes = parsedStart.hour * 60 + parsedStart.minute;
    final endMinutes = parsedEnd.hour * 60 + parsedEnd.minute;
    if (endMinutes <= startMinutes) {
      return 'Blocked end time must be after start time.';
    }
    return null;
  }

  Future<void> _showRecurringBlockedHoursDialog() async {
    String start = '12:00';
    String end = '13:00';

    final selectedDays = <String, bool>{
      for (final day in _blockedHourDaySelection.keys) day: false,
    };
    String? modalError;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> pickTime(bool isStart) async {
                final current = isStart ? start : end;
                final initial =
                    _parse24(current) ??
                    TimeOfDay(hour: isStart ? 12 : 13, minute: 0);
                final picked = await _showModernTimePicker(
                  initialTime: initial,
                  helpText: isStart ? 'Select Block Start' : 'Select Block End',
                );
                if (picked == null) return;
                setModalState(() {
                  if (isStart) {
                    start = _to24(picked);
                  } else {
                    end = _to24(picked);
                  }
                  modalError = _validateBlockedHourRange(start, end);
                });
              }

              final dayKeys = selectedDays.entries
                  .where((entry) => entry.value)
                  .map((entry) => entry.key)
                  .toList();

              return Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
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
                            Icons.access_time_filled_rounded,
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
                                'Add Recurring Blocked Hour',
                                style: TextStyle(
                                  color: _text,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Select time range and day(s) to exclude from generated slots.',
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
                            backgroundColor: Colors.black.withValues(alpha: 0.04),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 420;
                        if (stacked) {
                          return Column(
                            children: [
                              _buildTimePickerField(
                                label: 'Blocked Start',
                                value: _toReadable(start),
                                onTap: () => pickTime(true),
                                enabled: true,
                              ),
                              const SizedBox(height: 8),
                              _buildTimePickerField(
                                label: 'Blocked End',
                                value: _toReadable(end),
                                onTap: () => pickTime(false),
                                enabled: true,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(
                              child: _buildTimePickerField(
                                label: 'Blocked Start',
                                value: _toReadable(start),
                                onTap: () => pickTime(true),
                                enabled: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTimePickerField(
                                label: 'Blocked End',
                                value: _toReadable(end),
                                onTap: () => pickTime(false),
                                enabled: true,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _blockedHourDaySelection.keys.map((day) {
                        return FilterChip(
                          label: Text(_dayLabel(day)),
                          selected: selectedDays[day] == true,
                          onSelected: (selected) {
                            setModalState(() {
                              selectedDays[day] = selected;
                              modalError = null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        modalError!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
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
                        dayKeys.isEmpty
                            ? 'Select at least one day.'
                            : '${dayKeys.length} day(s) selected',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                            onPressed: () {
                              final validationError = _validateBlockedHourRange(
                                start,
                                end,
                              );
                              if (validationError != null) {
                                setModalState(() => modalError = validationError);
                                return;
                              }

                              final selected = selectedDays.entries
                                  .where((entry) => entry.value)
                                  .map((entry) => entry.key)
                                  .toList();
                              if (selected.isEmpty) {
                                setModalState(
                                  () => modalError = 'Select at least one day.',
                                );
                                return;
                              }

                              setState(() {
                                for (final day in selected) {
                                  final list =
                                      _weeklyBlockedWindows[day] ??
                                      <Map<String, String>>[];
                                  final duplicate = list.any(
                                    (window) =>
                                        window['start'] == start &&
                                        window['end'] == end,
                                  );
                                  if (!duplicate) {
                                    list.add({'start': start, 'end': end});
                                    list.sort(
                                      (a, b) => a['start']!.compareTo(b['start']!),
                                    );
                                    _weeklyBlockedWindows[day] = list;
                                  }
                                }
                                _blockedHourStartCtrl.text = '12:00';
                                _blockedHourEndCtrl.text = '13:00';
                                for (final day in _blockedHourDaySelection.keys) {
                                  _blockedHourDaySelection[day] = false;
                                }
                              });

                              if (mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Recurring blocked hour added to ${selected.length} day(s).',
                                    ),
                                  ),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: _primary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Add Blocked Hour',
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

  void _removeRecurringBlockedHourRange({
    required String start,
    required String end,
  }) {
    setState(() {
      for (final day in _weeklyBlockedWindows.keys) {
        final list = _weeklyBlockedWindows[day];
        if (list == null || list.isEmpty) continue;
        list.removeWhere(
          (window) => window['start'] == start && window['end'] == end,
        );
      }
    });
  }

  int _timeToMinutes(String value) {
    final parsed = _parse24(value);
    if (parsed == null) return 24 * 60 + 1;
    return parsed.hour * 60 + parsed.minute;
  }

  List<({String start, String end, String label, List<String> days})>
  _buildRecurringBlockedHourGroups() {
    final grouped = <String, Map<String, dynamic>>{};
    for (final day in _blockedHourDaySelection.keys) {
      final windows = _weeklyBlockedWindows[day] ?? const <Map<String, String>>[];
      for (final window in windows) {
        final start = (window['start'] ?? '').toString().trim();
        final end = (window['end'] ?? '').toString().trim();
        if (_parse24(start) == null || _parse24(end) == null) continue;
        final key = '$start|$end';
        final entry = grouped.putIfAbsent(
          key,
          () => <String, dynamic>{
            'start': start,
            'end': end,
            'days': <String>[],
          },
        );
        final days = entry['days'] as List<String>;
        if (!days.contains(day)) days.add(day);
      }
    }

    final out = grouped.values.map((entry) {
      final start = entry['start'] as String;
      final end = entry['end'] as String;
      final days = List<String>.from(entry['days'] as List);
      return (
        start: start,
        end: end,
        label: '${_toReadable(start)} - ${_toReadable(end)}',
        days: days,
      );
    }).toList();

    out.sort((a, b) {
      final startCmp = _timeToMinutes(a.start).compareTo(_timeToMinutes(b.start));
      if (startCmp != 0) return startCmp;
      return _timeToMinutes(a.end).compareTo(_timeToMinutes(b.end));
    });
    return out;
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DateTime? _parseDateKey(String key) {
    try {
      final parts = key.split('-');
      if (parts.length != 3) return null;
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final d = int.parse(parts[2]);
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _setBlockedDatesFromList(List<dynamic> raw) {
    _blockedDateKeys
      ..clear()
      ..addAll(raw.map((v) => v.toString().trim()).where((v) => v.isNotEmpty));
    _blockedDateKeys.sort();
  }

  void _constrainBlockedDatesToActiveTerm() {
    if (_activeTermStart == null || _activeTermEnd == null) return;
    final start = DateTime(
      _activeTermStart!.year,
      _activeTermStart!.month,
      _activeTermStart!.day,
    );
    final todayStart = _todayStart();
    final effectiveStart = start.isBefore(todayStart) ? todayStart : start;
    final end = DateTime(
      _activeTermEnd!.year,
      _activeTermEnd!.month,
      _activeTermEnd!.day,
    );

    _blockedDateKeys.removeWhere((key) {
      final date = _parseDateKey(key);
      if (date == null) return true;
      final normalized = DateTime(date.year, date.month, date.day);
      return normalized.isBefore(effectiveStart) || normalized.isAfter(end);
    });
    _blockedDateKeys.sort();
  }

  Future<void> _pickBlockedDate() async {
    if (_activeTermStart == null || _activeTermEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set start/end date for active term in Academic Settings first.',
          ),
        ),
      );
      return;
    }

    final firstDate = DateTime(
      _activeTermStart!.year,
      _activeTermStart!.month,
      _activeTermStart!.day,
    );
    final todayStart = _todayStart();
    final effectiveFirstDate = firstDate.isBefore(todayStart)
        ? todayStart
        : firstDate;
    final lastDate = DateTime(
      _activeTermEnd!.year,
      _activeTermEnd!.month,
      _activeTermEnd!.day,
    );
    if (lastDate.isBefore(effectiveFirstDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Active term has no remaining future dates to block.'),
        ),
      );
      return;
    }

    final initial = DateTime.now().isBefore(effectiveFirstDate)
        ? effectiveFirstDate
        : DateTime.now().isAfter(lastDate)
        ? lastDate
        : DateTime.now();

    final initialAvailable = _findNearestSelectableBlockedDate(
      initialDate: initial,
      firstDate: effectiveFirstDate,
      lastDate: lastDate,
    );
    if (initialAvailable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All remaining dates are already blocked.'),
        ),
      );
      return;
    }

    final pickedDates = await _showBlockedDateDialog(
      firstDate: effectiveFirstDate,
      lastDate: lastDate,
      initialDate: initialAvailable,
    );
    if (pickedDates == null || pickedDates.isEmpty || !mounted) return;

    setState(() {
      for (final picked in pickedDates) {
        final key = _dateKey(picked);
        if (!_blockedDateKeys.contains(key)) {
          _blockedDateKeys.add(key);
        }
      }
      _blockedDateKeys.sort();
    });
  }

  Future<TimeOfDay?> _showModernTimePicker({
    required TimeOfDay initialTime,
    required String helpText,
  }) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: helpText,
      cancelText: 'Cancel',
      confirmText: 'Apply',
      builder: (context, child) {
        final base = Theme.of(context);
        final dayPeriodColor = WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _primary;
          return _bg;
        });
        final dayPeriodTextColor = WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return _text;
        });
        final colorScheme = base.colorScheme.copyWith(
          primary: _primary,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: _text,
        );
        final pickerTheme = base.timePickerTheme.copyWith(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
          hourMinuteShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _primary.withValues(alpha: 0.20)),
          ),
          hourMinuteColor: _bg,
          hourMinuteTextColor: _text,
          dayPeriodColor: dayPeriodColor,
          dayPeriodTextColor: dayPeriodTextColor,
          dayPeriodShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: _primary.withValues(alpha: 0.14)),
          ),
          dialBackgroundColor: _bg,
          dialHandColor: _primary,
          dialTextColor: _text,
          entryModeIconColor: _primary,
          helpTextStyle: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: _primary,
            backgroundColor: Colors.white,
            side: BorderSide(color: _primary.withValues(alpha: 0.30)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
          confirmButtonStyle: FilledButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );

        return Theme(
          data: base.copyWith(
            colorScheme: colorScheme,
            timePickerTheme: pickerTheme,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _hint,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSelectableBlockedDate({
    required DateTime date,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    final normalized = _normalizeDate(date);
    if (normalized.isBefore(firstDate) || normalized.isAfter(lastDate)) {
      return false;
    }
    return !_blockedDateKeys.contains(_dateKey(normalized));
  }

  DateTime? _findNearestSelectableBlockedDate({
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    final normalizedInitial = _normalizeDate(initialDate);

    for (
      DateTime day = normalizedInitial;
      !day.isAfter(lastDate);
      day = day.add(const Duration(days: 1))
    ) {
      if (_isSelectableBlockedDate(
        date: day,
        firstDate: firstDate,
        lastDate: lastDate,
      )) {
        return day;
      }
    }

    for (
      DateTime day = normalizedInitial.subtract(const Duration(days: 1));
      !day.isBefore(firstDate);
      day = day.subtract(const Duration(days: 1))
    ) {
      if (_isSelectableBlockedDate(
        date: day,
        firstDate: firstDate,
        lastDate: lastDate,
      )) {
        return day;
      }
    }
    return null;
  }

  Future<List<DateTime>?> _showBlockedDateDialog({
    required DateTime firstDate,
    required DateTime lastDate,
    required DateTime initialDate,
  }) async {
    DateTime selectedDate = _normalizeDate(initialDate);
    final List<DateTime> pendingDates = <DateTime>[];

    return showDialog<List<DateTime>>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final canAdd = _isSelectableBlockedDate(
                date: selectedDate,
                firstDate: firstDate,
                lastDate: lastDate,
              );
              final pendingKeys = pendingDates.map(_dateKey).toSet();
              final selectedKey = _dateKey(selectedDate);
              final canSelectDate =
                  canAdd && !pendingKeys.contains(selectedKey);
              final finalDates = <DateTime>[...pendingDates]..sort();

              return Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
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
                            Icons.event_busy_rounded,
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
                                'Add Blocked Date',
                                style: TextStyle(
                                  color: _text,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Choose a date within the active term range.',
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
                            backgroundColor: Colors.black.withValues(alpha: 0.04),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (pendingDates.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: pendingDates.map((date) {
                          final label = DateFormat('MMM d, yyyy').format(date);
                          return Chip(
                            label: Text(
                              label,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: _primary.withValues(alpha: 0.18),
                            ),
                            deleteIconColor: _primary,
                            onDeleted: () {
                              setModalState(() {
                                pendingDates.removeWhere(
                                  (item) => _dateKey(item) == _dateKey(date),
                                );
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
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
                        initialDate: selectedDate,
                        firstDate: firstDate,
                        lastDate: lastDate,
                        onDateChanged: (date) {
                          setModalState(() {
                            selectedDate = _normalizeDate(date);
                          });
                        },
                        selectableDayPredicate: (day) {
                          return _isSelectableBlockedDate(
                            date: day,
                            firstDate: firstDate,
                            lastDate: lastDate,
                          );
                        },
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
                        canSelectDate
                            ? 'Selected: ${DateFormat('EEEE, MMM d, yyyy').format(selectedDate)} (ready to select)'
                            : 'Selected: ${DateFormat('EEEE, MMM d, yyyy').format(selectedDate)}',
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pendingDates.isEmpty
                                ? 'No selected dates yet.'
                                : '${pendingDates.length} selected',
                            style: const TextStyle(
                              color: _hint,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: pendingDates.isEmpty
                              ? null
                              : () {
                                  setModalState(() {
                                    pendingDates.clear();
                                  });
                                },
                          style: TextButton.styleFrom(
                            foregroundColor: _hint,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                          ),
                          child: const Text(
                            'Clear',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: canSelectDate
                              ? () {
                                  setModalState(() {
                                    pendingDates.add(selectedDate);
                                    pendingDates.sort();
                                  });
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Select Date',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
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
                            onPressed: finalDates.isEmpty
                                ? null
                                : () => Navigator.of(context).pop(
                                    List<DateTime>.from(finalDates),
                                  ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _primary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              finalDates.length == 1
                                  ? 'Add 1 Date'
                                  : 'Add ${finalDates.length} Dates',
                              style: const TextStyle(fontWeight: FontWeight.w900),
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

  void _removeBlockedDate(String key) {
    setState(() => _blockedDateKeys.remove(key));
  }

  Future<void> _saveTemplate() async {
    final sy = (_activeSchoolYearId ?? '').trim();
    final term = (_activeTermId ?? '').trim();
    if (sy.isEmpty || term.isEmpty) return;
    if (!_validateAllDaysWithFeedback()) return;

    setState(() => _saving = true);
    try {
      await _svc.saveTermScheduleTemplate(
        schoolYearId: sy,
        termId: term,
        weeklyWindows: _buildWeeklyWindows(),
        recurringBlockedWindows: _buildRecurringBlockedWindows(),
        blockedDates: _blockedDates(),
        slotMinutes: 60,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Schedule template saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_GenerateMode> _askGenerateMode({
    required String sy,
    required String term,
    required DateTime fromDate,
  }) async {
    bool hasExisting = false;
    try {
      hasExisting = await _svc.hasSlotsForTerm(
        schoolYearId: sy,
        termId: term,
        fromDate: fromDate,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'failed-precondition') rethrow;
      hasExisting = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Slots check skipped due to missing index. Continuing generation.',
            ),
          ),
        );
      }
    }
    if (!hasExisting) return _GenerateMode.resetAndGenerate;

    if (!mounted) return _GenerateMode.cancel;
    final mode = await showDialog<_GenerateMode>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Slots Already Exist',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'Upcoming slots for this active term already exist. '
            'Do you want to reset upcoming open slots and generate a new schedule? '
            'Booked/completed/missed meetings will not be changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _GenerateMode.cancel),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _GenerateMode.resetAndGenerate),
              style: FilledButton.styleFrom(backgroundColor: _primary),
              child: const Text('Reset + Generate'),
            ),
          ],
        );
      },
    );

    return mode ?? _GenerateMode.cancel;
  }

  Future<void> _generateSlots() async {
    final sy = (_activeSchoolYearId ?? '').trim();
    final term = (_activeTermId ?? '').trim();
    if (sy.isEmpty || term.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No active school year/term found in Academic Settings.',
          ),
        ),
      );
      return;
    }
    if (!_validateAllDaysWithFeedback()) return;

    if (_activeTermStart == null || _activeTermEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set start/end date for the active term in Academic Settings first.',
          ),
        ),
      );
      return;
    }

    final rangeStart = DateTime(
      _activeTermStart!.year,
      _activeTermStart!.month,
      _activeTermStart!.day,
    );
    final todayStart = _todayStart();
    final effectiveRangeStart = rangeStart.isBefore(todayStart)
        ? todayStart
        : rangeStart;
    final rangeEnd = DateTime(
      _activeTermEnd!.year,
      _activeTermEnd!.month,
      _activeTermEnd!.day,
      23,
      59,
      59,
    );
    if (rangeEnd.isBefore(effectiveRangeStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No future schedule dates available in active term.'),
        ),
      );
      return;
    }

    setState(() => _generating = true);
    try {
      final template = await _svc.getTermScheduleTemplate(
        schoolYearId: sy,
        termId: term,
      );
      if (template == null) {
        await _svc.saveTermScheduleTemplate(
          schoolYearId: sy,
          termId: term,
          weeklyWindows: _buildWeeklyWindows(),
          recurringBlockedWindows: _buildRecurringBlockedWindows(),
          blockedDates: _blockedDates(),
          slotMinutes: 60,
        );
      }

      final generateMode = await _askGenerateMode(
        sy: sy,
        term: term,
        fromDate: effectiveRangeStart,
      );
      if (generateMode == _GenerateMode.cancel) return;

      final count = await _svc.generateSlotsFromTemplate(
        schoolYearId: sy,
        termId: term,
        rangeStart: effectiveRangeStart,
        rangeEnd: rangeEnd,
        replaceOpenSlots: true,
        replaceOpenFrom: effectiveRangeStart,
      );
      if (!mounted) return;
      setState(() {
        _lastGeneratedCount = count;
        _selectedOpenSlotIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'No slots generated. Check day availability and active term dates.'
                : 'Generated $count one-hour meeting slots.',
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final message = e.code == 'failed-precondition'
          ? 'Generation failed: missing Firestore index. Open the error link in logs and create the required index.'
          : 'Generation failed: ${e.message ?? e.code}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Generation failed: $e')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sy = (_activeSchoolYearId ?? '').trim();
    final term = (_activeTermId ?? '').trim();
    final canQuerySlots = sy.isNotEmpty && term.isNotEmpty;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktopSplit = constraints.maxWidth >= 1200;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(showTabs: !isDesktopSplit),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: isDesktopSplit
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _buildEditorCard()),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSlotsCard(
                                  canQuerySlots: canQuerySlots,
                                  sy: sy,
                                  term: term,
                                ),
                              ),
                            ],
                          )
                        : _mainTab == _ScheduleMainTab.templateSetup
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 980),
                              child: _buildEditorCard(),
                            ),
                          )
                        : Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 980),
                              child: _buildSlotsCard(
                                canQuerySlots: canQuerySlots,
                                sy: sy,
                                term: term,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar({required bool showTabs}) {
    final activeDays = _enabledDays.values.where((v) => v).length;
    final activeLabel = (_activeSchoolYearLabel ?? '').trim();
    final activeTerm = (_activeTermId ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _primary,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'Configure weekly availability and generate 1-hour student booking slots.',
                style: TextStyle(
                  color: _hint,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _statChip(
                  'Active SY',
                  activeLabel.isEmpty ? 'Not set' : activeLabel,
                ),
                const SizedBox(width: 8),
                _statChip(
                  'Active Term',
                  activeTerm.isEmpty ? 'Not set' : activeTerm,
                ),
                const SizedBox(width: 8),
                _statChip('Active days', '$activeDays / 5'),
                const SizedBox(width: 8),
                _statChip('Slot duration', '60 mins'),
                if (_lastGeneratedCount != null) ...[
                  const SizedBox(width: 8),
                  _statChip('Last generation', '$_lastGeneratedCount slots'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (activeLabel.isEmpty || activeTerm.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
              ),
              child: const Text(
                'No active Academic Year/Term found. Set one in Academic Settings first.',
                style: TextStyle(
                  color: Color(0xFF7A5B00),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (showTabs) ...[
            _buildMainTabBar(),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildMainTabBar() {
    final selectedIndex = _mainTab == _ScheduleMainTab.templateSetup ? 0 : 1;
    return DefaultTabController(
      key: ValueKey(_mainTab),
      length: 2,
      initialIndex: selectedIndex,
      child: Material(
        color: Colors.white,
        child: TabBar(
          labelColor: _primary,
          unselectedLabelColor: Colors.black54,
          indicatorColor: _primary,
          indicatorWeight: 2,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.black.withValues(alpha: 0.08),
          onTap: (index) {
            final next = index == 0
                ? _ScheduleMainTab.templateSetup
                : _ScheduleMainTab.openSlots;
            if (next == _mainTab) return;
            setState(() => _mainTab = next);
          },
          tabs: const [
            Tab(text: 'Template Setup'),
            Tab(text: 'Open Slots'),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _primary.withValues(alpha: 0.16)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'Roboto'),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorCard() {
    final hasActiveAcademic =
        (_activeSchoolYearId ?? '').trim().isNotEmpty &&
        (_activeTermId ?? '').trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Schedule Template',
            style: TextStyle(
              color: _text,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _buildWeeklyAvailabilitySection(),
                const SizedBox(height: 12),
                _buildBlockedDatesSection(hasActiveAcademic: hasActiveAcademic),
                const SizedBox(height: 12),
                _buildRecurringBlockedHoursSection(
                  hasActiveAcademic: hasActiveAcademic,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 420;
              if (stacked) {
                return Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _saving || !hasActiveAcademic
                            ? null
                            : _saveTemplate,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Saving...' : 'Save Template'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _generating || !hasActiveAcademic
                            ? null
                            : _generateSlots,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          _generating ? 'Generating...' : 'Generate Slots',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _primary,
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving || !hasActiveAcademic
                          ? null
                          : _saveTemplate,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save Template'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _generating || !hasActiveAcademic
                          ? null
                          : _generateSlots,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(
                        _generating ? 'Generating...' : 'Generate Slots',
                      ),
                      style: FilledButton.styleFrom(backgroundColor: _primary),
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

  Widget _buildSectionIcon(IconData icon) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: _primary, size: 16),
    );
  }

  Widget _buildSectionHeaderText({
    required String title,
    required String subtitle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
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
    );
  }

  BoxDecoration _buildSectionCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildWeeklyAvailabilitySection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _buildSectionCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionIcon(Icons.calendar_today_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSectionHeaderText(
                  title: 'Weekly Availability',
                  subtitle: 'Set weekly working hours',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildWeeklyAvailabilityTable(),
        ],
      ),
    );
  }

  Widget _buildBlockedDatesSection({required bool hasActiveAcademic}) {
    final hasTermRange = _activeTermStart != null && _activeTermEnd != null;
    final todayStart = _todayStart();
    final effectiveStart = hasTermRange
        ? _activeTermStart!.isBefore(todayStart)
              ? todayStart
              : _activeTermStart!
        : null;
    final rangeText = hasTermRange
        ? '${DateFormat('MMM d, yyyy').format(effectiveStart!)} - ${DateFormat('MMM d, yyyy').format(_activeTermEnd!)}'
        : 'No active term range found';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _buildSectionCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 640;
              final actions = Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_blockedDateKeys.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _blockedDateKeys.clear();
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: _hint,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                  FilledButton(
                    onPressed: hasActiveAcademic && hasTermRange
                        ? _pickBlockedDate
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Select Dates'),
                  ),
                ],
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildSectionIcon(Icons.event_available_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildSectionHeaderText(
                            title: 'Blocked Dates',
                            subtitle:
                                'Block out entire days for holidays or special events.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }

              return Row(
                children: [
                  _buildSectionIcon(Icons.event_available_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildSectionHeaderText(
                      title: 'Blocked Dates',
                      subtitle:
                          'Block out entire days for holidays or special events.',
                    ),
                  ),
                  const SizedBox(width: 10),
                  actions,
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Allowed range: $rangeText',
            style: const TextStyle(
              color: _hint,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          if (_blockedDateKeys.isEmpty)
            const Text(
              'No blocked dates selected.',
              style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _blockedDateKeys.map((key) {
                final date = _parseDateKey(key);
                final label = date == null
                    ? key
                    : DateFormat('MMM d, yyyy').format(date);
                return Chip(
                  label: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: _primary.withValues(alpha: 0.18)),
                  deleteIconColor: _primary,
                  onDeleted: () => _removeBlockedDate(key),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildRecurringBlockedHoursSection({required bool hasActiveAcademic}) {
    final hasRules = _weeklyBlockedWindows.values.any(
      (list) => list.isNotEmpty,
    );
    final items = _buildRecurringBlockedHourGroups();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _buildSectionCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 680;
              final actions = Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (hasRules)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          for (final day in _weeklyBlockedWindows.keys) {
                            _weeklyBlockedWindows[day] = [];
                          }
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: _hint,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                  FilledButton(
                    onPressed: hasActiveAcademic
                        ? _showRecurringBlockedHoursDialog
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Add Blocked Hours'),
                  ),
                ],
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildSectionIcon(Icons.access_time_filled_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildSectionHeaderText(
                            title: 'Recurring Blocked Hours',
                            subtitle:
                                'Block out specific times for lunches, classes, and meetings.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }

              return Row(
                children: [
                  _buildSectionIcon(Icons.access_time_filled_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildSectionHeaderText(
                      title: 'Recurring Blocked Hours',
                      subtitle:
                          'Block out specific times for lunches, classes, and meetings.',
                    ),
                  ),
                  const SizedBox(width: 10),
                  actions,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (!hasRules)
            const Text(
              'No recurring blocked hours configured.',
              style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
            )
          else
            _buildRecurringBlockedHoursTable(items),
        ],
      ),
    );
  }

  Widget _buildRecurringBlockedHoursTable(
    List<({String start, String end, String label, List<String> days})> items,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final borderColor = Colors.black.withValues(alpha: 0.08);
        final table = Table(
          border: TableBorder(horizontalInside: BorderSide(color: borderColor)),
          columnWidths: {
            0: const FlexColumnWidth(2.3),
            1: const FlexColumnWidth(2.5),
            2: FixedColumnWidth(compact ? 56 : 72),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: _bg),
              children: [
                _buildRecurringHourHeaderCell('Blocked Time'),
                _buildRecurringHourHeaderCell('Days'),
                _buildRecurringHourHeaderCell(
                  'Action',
                  align: TextAlign.right,
                ),
              ],
            ),
            ...items.map((item) {
              return TableRow(
                decoration: const BoxDecoration(color: Colors.white),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Wrap(
                      spacing: compact ? 4 : 6,
                      runSpacing: compact ? 4 : 6,
                      children: item.days.map((day) {
                        return Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 6 : 8,
                            vertical: compact ? 3 : 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            compact ? _dayShortLabel(day) : _dayLabel(day),
                            style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w800,
                              fontSize: compact ? 10.8 : 11.5,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () => _removeRecurringBlockedHourRange(
                        start: item.start,
                        end: item.end,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      color: Colors.red.shade600,
                      tooltip: 'Remove this blocked time set',
                      visualDensity: VisualDensity.compact,
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints.tightFor(
                        width: compact ? 36 : 42,
                        height: compact ? 36 : 42,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        );

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: table,
          ),
        );
      },
    );
  }

  Widget _buildRecurringHourHeaderCell(
    String text, {
    TextAlign align = TextAlign.left,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(
          color: _hint,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildWeeklyAvailabilityTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = <TableRow>[
          TableRow(
            decoration: BoxDecoration(color: _bg),
            children: [
              _buildWeeklyHeaderCell('Day'),
              _buildWeeklyHeaderCell('Start'),
              _buildWeeklyHeaderCell('End'),
              _buildWeeklyHeaderCell('On', align: TextAlign.center),
            ],
          ),
          ..._enabledDays.keys.map((dayKey) {
            final enabled = _enabledDays[dayKey] == true;
            final dayError = _dayErrors[dayKey];
            return TableRow(
              decoration: BoxDecoration(
                color: dayError != null
                    ? Colors.red.withValues(alpha: 0.04)
                    : Colors.white,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dayLabel(dayKey),
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (enabled && dayError != null)
                        Tooltip(
                          message: dayError,
                          child: const Icon(
                            Icons.error_outline_rounded,
                            size: 14,
                            color: Colors.red,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: _buildCompactTimeField(
                    value: _toReadable(_startCtrls[dayKey]!.text),
                    onTap: () => _pickTime(dayKey: dayKey, isStart: true),
                    enabled: enabled,
                    height: 32,
                    horizontalPadding: 7,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: _buildCompactTimeField(
                    value: _toReadable(_endCtrls[dayKey]!.text),
                    onTap: () => _pickTime(dayKey: dayKey, isStart: false),
                    enabled: enabled,
                    height: 32,
                    horizontalPadding: 7,
                  ),
                ),
                Center(
                  child: Transform.scale(
                    scale: 0.82,
                    child: Switch.adaptive(
                      value: enabled,
                      activeThumbColor: _primary,
                      activeTrackColor: _primary.withValues(alpha: 0.30),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (value) {
                        setState(() {
                          _enabledDays[dayKey] = value;
                          _dayErrors[dayKey] = _validateDay(dayKey);
                        });
                      },
                    ),
                  ),
                ),
              ],
            );
          }),
        ];

        const minTableWidth = 540.0;
        final borderColor = Colors.black.withValues(alpha: 0.08);
        final table = Table(
          border: TableBorder(
            top: BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
            horizontalInside: BorderSide(color: borderColor),
          ),
          columnWidths: const {
            0: FixedColumnWidth(110),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
            3: FixedColumnWidth(70),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        );

        if (constraints.maxWidth >= minTableWidth) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: table,
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: minTableWidth, child: table),
          ),
        );
      },
    );
  }

  Widget _buildWeeklyHeaderCell(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(
          color: _hint,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildCompactTimeField({
    required String value,
    required VoidCallback onTap,
    required bool enabled,
    double height = 36,
    double horizontalPadding = 10,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? Colors.black.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.access_time_rounded,
              size: 16,
              color: enabled ? _primary : _hint,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: enabled ? _text : _hint,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePickerField({
    required String label,
    required String value,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: enabled ? Colors.white : Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: _primary, width: 1.4),
          ),
          suffixIcon: Icon(
            Icons.access_time_rounded,
            color: enabled ? _primary : _hint,
            size: 18,
          ),
          isDense: true,
        ),
        child: Text(
          value,
          style: TextStyle(
            color: enabled ? _text : _hint,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSlotsCard({
    required bool canQuerySlots,
    required String sy,
    required String term,
  }) {
    return LayoutBuilder(
      builder: (context, slotLayout) {
        final isCompact = slotLayout.maxWidth < 780;
        return Container(
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: !canQuerySlots
              ? const Center(
                  child: Text(
                    'Set School Year and Term first.',
                    style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
                  ),
                )
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _svc.streamOpenSlots(
                    schoolYearId: sy,
                    termId: term,
                    limit: 150,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading slots: ${snapshot.error}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final now = DateTime.now();
                    final docs = snapshot.data!.docs.where((doc) {
                      final start = (doc.data()['startAt'] as Timestamp?)
                          ?.toDate();
                      return start != null && !start.isBefore(now);
                    }).toList();
                    const emptyMessage =
                        'No upcoming open slots. Generate or refresh term slots.';
                    final visibleSlotIds = docs.map((doc) => doc.id).toSet();
                    final selectedVisibleSlotIds = _selectedOpenSlotIds
                        .where(visibleSlotIds.contains)
                        .toSet();
                    final grouped = _groupSlotsByDate(docs);
                    final firstOpen = docs.isEmpty
                        ? null
                        : (docs.first.data()['startAt'] as Timestamp?)
                              ?.toDate();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isCompact)
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Open Meeting Slots',
                                  style: TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              ..._buildSlotActionButtons(
                                selectedVisibleSlotIds: selectedVisibleSlotIds,
                              ),
                            ],
                          )
                        else ...[
                          const Text(
                            'Open Meeting Slots',
                            style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _buildSlotActionButtons(
                              selectedVisibleSlotIds: selectedVisibleSlotIds,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          _slotSelectionMode
                              ? 'Tap slots to select, then close selected from top-right.'
                              : 'Click Select to start choosing slots to close.',
                          style: const TextStyle(
                            color: _hint,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _statChip('Open slots', '${docs.length}'),
                            if (firstOpen != null)
                              _statChip(
                                'First slot',
                                DateFormat('MMM d, h:mm a').format(firstOpen),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: docs.isEmpty
                              ? Center(
                                  child: Text(
                                    emptyMessage,
                                    style: const TextStyle(
                                      color: _hint,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: grouped.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, index) {
                                    final entry = grouped[index];
                                    return Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _bg,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.08,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.$1,
                                            style: const TextStyle(
                                              color: _text,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          ...entry.$2.map(
                                            (slot) => _slotTile(
                                              slot,
                                              selectionMode: _slotSelectionMode,
                                              selected: _selectedOpenSlotIds
                                                  .contains(slot.id),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  List<Widget> _buildSlotActionButtons({
    required Set<String> selectedVisibleSlotIds,
  }) {
    if (!_slotSelectionMode) {
      return [
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _slotSelectionMode = true;
            _selectedOpenSlotIds.clear();
          }),
          icon: const Icon(Icons.checklist_rounded, size: 16),
          label: const Text('Select'),
        ),
      ];
    }

    return [
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _slotSelectionMode = false;
          _selectedOpenSlotIds.clear();
        }),
        icon: const Icon(Icons.close_rounded, size: 16),
        label: const Text('Cancel'),
      ),
      OutlinedButton.icon(
        onPressed: selectedVisibleSlotIds.isEmpty
            ? null
            : () => setState(() => _selectedOpenSlotIds.clear()),
        icon: const Icon(Icons.clear_rounded, size: 16),
        label: const Text('Clear'),
      ),
      FilledButton.icon(
        onPressed: selectedVisibleSlotIds.isEmpty || _closingSelectedSlots
            ? null
            : () => _closeSelectedOpenSlots(selectedVisibleSlotIds),
        icon: const Icon(Icons.block_rounded, size: 16),
        label: Text(
          _closingSelectedSlots
              ? 'Closing...'
              : 'Close Selected (${selectedVisibleSlotIds.length})',
        ),
        style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
      ),
    ];
  }

  void _toggleOpenSlotSelection(String slotId) {
    if (!_slotSelectionMode) return;
    setState(() {
      if (_selectedOpenSlotIds.contains(slotId)) {
        _selectedOpenSlotIds.remove(slotId);
      } else {
        _selectedOpenSlotIds.add(slotId);
      }
    });
  }

  Future<void> _closeSelectedOpenSlots(Set<String> slotIds) async {
    if (slotIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Close Selected Slots',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Close ${slotIds.length} selected open slot(s)?\n\nStudents will not be able to book these slots anymore.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: _primary),
              child: const Text('Close Selected'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _closingSelectedSlots = true);
    try {
      var success = 0;
      var failed = 0;
      final closedIds = <String>{};

      for (final slotId in slotIds) {
        try {
          await _svc.closeOpenSlot(slotId: slotId);
          success++;
          closedIds.add(slotId);
        } catch (_) {
          failed++;
        }
      }

      if (!mounted) return;
      setState(() {
        _selectedOpenSlotIds.removeAll(closedIds);
        if (_selectedOpenSlotIds.isEmpty) {
          _slotSelectionMode = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? '$success slot(s) closed.'
                : '$success slot(s) closed, $failed failed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Close selected failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _closingSelectedSlots = false);
      }
    }
  }

  Widget _slotTile(
    QueryDocumentSnapshot<Map<String, dynamic>> slot, {
    required bool selectionMode,
    required bool selected,
  }) {
    final data = slot.data();
    final start = (data['startAt'] as Timestamp?)?.toDate();
    final end = (data['endAt'] as Timestamp?)?.toDate();
    final timeText = start == null || end == null
        ? '--'
        : '${DateFormat('h:mm a').format(start)} - ${DateFormat('h:mm a').format(end)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: selectionMode ? () => _toggleOpenSlotSelection(slot.id) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _primary.withValues(alpha: 0.10) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Colors.green.shade700
                  : _primary.withValues(alpha: 0.16),
              width: selected ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 16,
                color: selected ? Colors.green.shade700 : _primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  timeText,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Open',
                  style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<(String, List<QueryDocumentSnapshot<Map<String, dynamic>>>)>
  _groupSlotsByDate(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final map = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final start = (doc.data()['startAt'] as Timestamp?)?.toDate();
      final key = start == null
          ? 'Unknown Date'
          : DateFormat('EEEE, MMM d, yyyy').format(start);
      map.putIfAbsent(key, () => []).add(doc);
    }
    return map.entries.map((e) => (e.key, e.value)).toList();
  }

  String _dayLabel(String key) {
    switch (key) {
      case 'mon':
        return 'Monday';
      case 'tue':
        return 'Tuesday';
      case 'wed':
        return 'Wednesday';
      case 'thu':
        return 'Thursday';
      case 'fri':
        return 'Friday';
      default:
        return key.toUpperCase();
    }
  }

  String _dayShortLabel(String key) {
    switch (key) {
      case 'mon':
        return 'Mon';
      case 'tue':
        return 'Tue';
      case 'wed':
        return 'Wed';
      case 'thu':
        return 'Thu';
      case 'fri':
        return 'Fri';
      default:
        return key.toUpperCase();
    }
  }
}
