import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:apps/pages/shared/widgets/modern_table_layout.dart';
import 'package:apps/pages/shared/widgets/app_empty_state.dart';
import 'package:apps/services/app_firestore.dart';
import 'package:apps/services/counseling_case_workflow_service.dart';

class CounselingAnalyticsPage extends StatefulWidget {
  const CounselingAnalyticsPage({super.key});

  @override
  State<CounselingAnalyticsPage> createState() =>
      _CounselingAnalyticsPageState();
}

enum _CounselingAnalyticsTab { overview, referrals, students, trends }

enum _DistributionChartKind { vertical, horizontal, table, donut }

class _CounselingAnalyticsPageState extends State<CounselingAnalyticsPage> {
  static const _bg = Colors.white;
  static const _primary = Color(0xFF1B5E20);
  static const _textDark = Color(0xFF1F2A1F);
  static const _hint = Color(0xFF6D7F62);

  final bool _useDummyData = false;
  final bool _useEmptyData = false;
  _CounselingAnalyticsTab _tab = _CounselingAnalyticsTab.overview;
  _DistributionChartKind _sourceChartKind = _DistributionChartKind.donut;
  _DistributionChartKind _typeChartKind = _DistributionChartKind.vertical;

  @override
  Widget build(BuildContext context) {
    final body = _useDummyData || _useEmptyData
        ? _buildBody(
            _useEmptyData ? const <_CounselingCase>[] : _buildDummyCases(),
          )
        : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: AppFirestore.instance
                .collection('counseling_cases')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final cases = snap.data!.docs
                  .map(_CounselingCase.fromDoc)
                  .toList(growable: false);
              return _buildBody(cases);
            },
          );

    return Scaffold(
      backgroundColor: _bg,
      body: KeyedSubtree(
        key: ValueKey(
          'counseling-analytics-${_useDummyData ? 'dummy' : 'live'}-'
          '${_useEmptyData ? 'empty' : 'data'}-${_tab.index}',
        ),
        child: body,
      ),
    );
  }

  Widget _buildBody(List<_CounselingCase> allCases) {
    final completedCases = allCases
        .where((caseItem) => CounselingCaseState.isCompleted(caseItem.data))
        .toList(growable: false);

    final tabBar = _buildAnalyticsTabBar(
      completedCount: completedCases.length,
      totalCount: allCases.length,
    );

    return ModernTableLayout(
      header: ModernTableHeader(
        showTitleSection: false,
        showTopControlsWhenTitleHidden: true,
        showSearchBar: false,
        searchBar: const SizedBox.shrink(),
        tabs: tabBar,
        filters: const [],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: _tabContent(allCases, completedCases),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabContent(
    List<_CounselingCase> allCases,
    List<_CounselingCase> completedCases,
  ) {
    final metrics = _CounselingMetrics.from(allCases, completedCases);
    switch (_tab) {
      case _CounselingAnalyticsTab.overview:
        return _overview(metrics);
      case _CounselingAnalyticsTab.referrals:
        return _referralTab(metrics);
      case _CounselingAnalyticsTab.students:
        return _studentTab(metrics);
      case _CounselingAnalyticsTab.trends:
        return _trendTab(metrics);
    }
  }

  Widget _overview(_CounselingMetrics m) {
    final isWide = MediaQuery.sizeOf(context).width >= 1120;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (m.total == 0)
          AppEmptyState(
            icon: Icons.insights_outlined,
            title: 'No counseling analytics yet',
            subtitle:
                'Completed counseling referrals will appear here once records exist.',
          )
        else ...[
          _metricGrid(m),
          const SizedBox(height: 12),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _card(
                    'Referral Source Distribution',
                    _buildDistributionContent(
                      data: m.sourceCounts,
                      kind: _sourceChartKind,
                      onTap: (_) {},
                      barColor: const Color(0xFF43A047),
                    ),
                    trailing: _distributionKindSelector(
                      value: _sourceChartKind,
                      onChanged: (next) =>
                          setState(() => _sourceChartKind = next),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _card(
                    'Counseling Type Distribution',
                    _buildDistributionContent(
                      data: m.typeCounts,
                      kind: _typeChartKind,
                      onTap: (_) {},
                      barColor: const Color(0xFF1B5E20),
                    ),
                    trailing: _distributionKindSelector(
                      value: _typeChartKind,
                      onChanged: (next) =>
                          setState(() => _typeChartKind = next),
                    ),
                  ),
                ),
              ],
            )
          else ...[
            _card(
              'Referral Source Distribution',
              _buildDistributionContent(
                data: m.sourceCounts,
                kind: _sourceChartKind,
                onTap: (_) {},
                barColor: const Color(0xFF43A047),
              ),
              trailing: _distributionKindSelector(
                value: _sourceChartKind,
                onChanged: (next) => setState(() => _sourceChartKind = next),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Counseling Type Distribution',
              _buildDistributionContent(
                data: m.typeCounts,
                kind: _typeChartKind,
                onTap: (_) {},
                barColor: const Color(0xFF1B5E20),
              ),
              trailing: _distributionKindSelector(
                value: _typeChartKind,
                onChanged: (next) => setState(() => _typeChartKind = next),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _card('Completed Referral Trend', _verticalBarChart(m.monthCounts)),
          const SizedBox(height: 12),
          _card(
            'Completed vs Ongoing',
            _statusDonut(
              completed: m.completed,
              ongoing: m.total - m.completed,
            ),
          ),
        ],
      ],
    );
  }

  Widget _referralTab(_CounselingMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metricGrid(m),
        const SizedBox(height: 12),
        _card(
          'Referral Source Breakdown',
          _buildDistributionContent(
            data: m.sourceCounts,
            kind: _sourceChartKind,
            onTap: (_) {},
            barColor: const Color(0xFF43A047),
          ),
          trailing: _distributionKindSelector(
            value: _sourceChartKind,
            onChanged: (next) => setState(() => _sourceChartKind = next),
          ),
        ),
        const SizedBox(height: 12),
        _card(
          'Counseling Type Breakdown',
          _buildDistributionContent(
            data: m.typeCounts,
            kind: _typeChartKind,
            onTap: (_) {},
            barColor: const Color(0xFF1B5E20),
          ),
          trailing: _distributionKindSelector(
            value: _typeChartKind,
            onChanged: (next) => setState(() => _typeChartKind = next),
          ),
        ),
        const SizedBox(height: 12),
        _card(
          'Completed vs Ongoing',
          _statusDonut(completed: m.completed, ongoing: m.total - m.completed),
        ),
      ],
    );
  }

  Widget _studentTab(_CounselingMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metricGrid(m),
        const SizedBox(height: 12),
        _card(
          'Top Students by Completed Referrals',
          _table(
            const ['Student', 'Total'],
            m.studentCounts.entries
                .take(10)
                .map((e) => [e.key, '${e.value}'])
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _trendTab(_CounselingMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metricGrid(m),
        const SizedBox(height: 12),
        _card('Completed Referral Trend', _verticalBarChart(m.monthCounts)),
        const SizedBox(height: 12),
        _card(
          'Top Counseling Students',
          _table(
            const ['Student', 'Total'],
            m.studentCounts.entries
                .take(10)
                .map((e) => [e.key, '${e.value}'])
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _metricGrid(_CounselingMetrics m) {
    final cards = [
      _metricCard('Total Cases', m.total.toString()),
      _metricCard('Completed', m.completed.toString()),
      _metricCard('Awaiting Call Slip', m.awaitingCallSlip.toString()),
      _metricCard('Scheduled', m.scheduled.toString()),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              cards[i],
              if (i < cards.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _metricCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _hint,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: _textDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, Widget child, {Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 22,
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _distributionKindSelector({
    required _DistributionChartKind value,
    required ValueChanged<_DistributionChartKind> onChanged,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<_DistributionChartKind>(
        value: value,
        isDense: true,
        borderRadius: BorderRadius.circular(10),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        style: const TextStyle(
          color: _hint,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        items: _DistributionChartKind.values
            .map(
              (kind) => DropdownMenuItem<_DistributionChartKind>(
                value: kind,
                child: Text(_distributionKindLabel(kind)),
              ),
            )
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  String _distributionKindLabel(_DistributionChartKind kind) {
    switch (kind) {
      case _DistributionChartKind.vertical:
        return 'Vertical';
      case _DistributionChartKind.horizontal:
        return 'Horizontal';
      case _DistributionChartKind.table:
        return 'Table';
      case _DistributionChartKind.donut:
        return 'Donut';
    }
  }

  Widget _buildDistributionContent({
    required Map<String, int> data,
    required _DistributionChartKind kind,
    required ValueChanged<String> onTap,
    required Color barColor,
    int maxItems = 12,
  }) {
    final limited = Map<String, int>.fromEntries(data.entries.take(maxItems));
    switch (kind) {
      case _DistributionChartKind.vertical:
        return _verticalBarChart(limited);
      case _DistributionChartKind.horizontal:
        return _bars(limited);
      case _DistributionChartKind.table:
        return _table(const [
          'Label',
          'Total',
        ], limited.entries.map((e) => [e.key, '${e.value}']).toList());
      case _DistributionChartKind.donut:
        return _distributionDonut(limited, accent: barColor);
    }
  }

  Widget _distributionDonut(Map<String, int> data, {required Color accent}) {
    final isNoData = data.isEmpty || data.values.every((v) => v == 0);
    final working = isNoData ? const {'No data': 1} : data;
    final sorted = working.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();
    final otherTotal = sorted.skip(5).fold<int>(0, (sum, e) => sum + e.value);

    final palette = <Color>[
      isNoData ? const Color(0xFFB7BDB7) : accent,
      isNoData ? const Color(0xFFB7BDB7) : const Color(0xFF43A047),
      isNoData ? const Color(0xFFB7BDB7) : const Color(0xFF66BB6A),
      isNoData ? const Color(0xFFB7BDB7) : const Color(0xFF8BC34A),
      const Color(0xFF26A69A),
      const Color(0xFF90A4AE),
    ];

    final slices = <_DonutSlice>[
      for (var i = 0; i < top.length; i++)
        _DonutSlice(top[i].key, top[i].value, palette[i % palette.length]),
      if (otherTotal > 0)
        _DonutSlice('Others', otherTotal, palette.last.withValues(alpha: 0.9)),
    ];
    final total = isNoData ? 0 : slices.fold<int>(0, (sum, s) => sum + s.value);

    return SizedBox(
      height: 230,
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 154,
                    height: 154,
                    child: CustomPaint(
                      painter: _DonutDistributionPainter(slices: slices),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isNoData ? '0' : '$total',
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        isNoData ? 'No data' : 'Total',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: slices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final s = slices[index];
                final pct = total == 0 ? 0 : ((s.value / total) * 100);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isNoData ? const Color(0xFFB7BDB7) : s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isNoData ? 'No data' : s.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isNoData
                            ? '0'
                            : '${s.value} (${pct.toStringAsFixed(0)}%)',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.8,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bars(Map<String, int> counts) {
    if (counts.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No data',
            style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    final maxValue = counts.values.fold<int>(
      0,
      (prev, next) => next > prev ? next : prev,
    );
    final entries = counts.entries.toList(growable: false);
    return Column(
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.value}',
                      style: const TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: maxValue == 0 ? 0 : entry.value / maxValue,
                    color: _primary,
                    backgroundColor: const Color(0xFFE8F0E7),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _verticalBarChart(Map<String, int> data) {
    final isNoData = data.isEmpty || data.values.every((v) => v == 0);
    final entries = isNoData
        ? const [MapEntry<String, int>('No data', 0)]
        : data.entries.toList(growable: false);
    final maxVal = entries.fold<int>(1, (p, e) => math.max(p, e.value));
    final axisMax = maxVal <= 0 ? 1 : maxVal;

    return SizedBox(
      height: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$axisMax',
                  style: const TextStyle(
                    color: _hint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${(axisMax / 2).round()}',
                  style: const TextStyle(
                    color: _hint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  '0',
                  style: TextStyle(
                    color: _hint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final e = entries[i];
                final ratio = isNoData
                    ? 0.28
                    : (e.value / axisMax).clamp(0.0, 1.0);
                final color = isNoData ? const Color(0xFFB7BDB7) : _primary;
                return SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        isNoData ? '0' : '${e.value}',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 34,
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.bottomCenter,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          width: 34,
                          height: 150 * ratio,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isNoData ? 'No data' : e.key,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDonut({required int completed, required int ongoing}) {
    final total = completed + ongoing;
    final isNoData = total == 0;
    return _distributionDonut(
      isNoData
          ? const <String, int>{}
          : <String, int>{'Completed': completed, 'Ongoing': ongoing},
      accent: const Color(0xFF43A047),
    );
  }

  Widget _table(List<String> columns, List<List<String>> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.white),
        columns: [
          for (final col in columns)
            DataColumn(
              label: Text(
                col,
                style: const TextStyle(
                  color: _hint,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
        rows: [
          for (final row in rows)
            DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTabBar({
    required int completedCount,
    required int totalCount,
  }) {
    final tabs = _CounselingAnalyticsTab.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _analyticsTabButton(
            label: 'Overview ($totalCount)',
            selected: _tab == _CounselingAnalyticsTab.overview,
            onTap: () =>
                setState(() => _tab = _CounselingAnalyticsTab.overview),
          ),
          const SizedBox(width: 10),
          _analyticsTabButton(
            label: 'Referrals ($completedCount)',
            selected: _tab == _CounselingAnalyticsTab.referrals,
            onTap: () =>
                setState(() => _tab = _CounselingAnalyticsTab.referrals),
          ),
          const SizedBox(width: 10),
          _analyticsTabButton(
            label: 'Students',
            selected: _tab == _CounselingAnalyticsTab.students,
            onTap: () =>
                setState(() => _tab = _CounselingAnalyticsTab.students),
          ),
          const SizedBox(width: 10),
          _analyticsTabButton(
            label: 'Trends',
            selected: _tab == _CounselingAnalyticsTab.trends,
            onTap: () => setState(() => _tab = _CounselingAnalyticsTab.trends),
          ),
        ],
      ),
    );
  }

  Widget _analyticsTabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _primary.withValues(alpha: 0.10) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _primary.withValues(alpha: 0.30)
                : Colors.black.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _primary : _hint,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  List<_CounselingCase> _buildDummyCases() {
    const sources = ['student', 'professor'];
    const types = ['academic', 'personal'];
    final now = DateTime.now();
    final cases = <_CounselingCase>[];
    for (var i = 0; i < 18; i++) {
      final date = DateTime(now.year, now.month - (i ~/ 2), 1 + (i % 26));
      cases.add(
        _CounselingCase('case-$i', {
          'studentName': 'Student $i',
          'studentNo': '19-${(1000 + i).toString()}',
          'referralSource': sources[i % sources.length],
          'counselingType': types[i % types.length],
          'createdAt': date,
          'status': i % 3 == 0 ? 'completed' : 'scheduled',
          'meetingStatus': i % 3 == 0
              ? CounselingCaseWorkflow.meetingCompleted
              : CounselingCaseWorkflow.meetingScheduled,
        }),
      );
    }
    return cases;
  }
}

class _DonutSlice {
  final String label;
  final int value;
  final Color color;

  const _DonutSlice(this.label, this.value, this.color);
}

class _DonutDistributionPainter extends CustomPainter {
  final List<_DonutSlice> slices;

  const _DonutDistributionPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, s) => sum + s.value);
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round;
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final start = -math.pi / 2;
    var sweepStart = start;

    if (total <= 0) {
      paint.color = const Color(0xFFB7BDB7);
      canvas.drawArc(
        rect.deflate(size.width * 0.07),
        0,
        math.pi * 2,
        false,
        paint,
      );
      return;
    }

    for (final slice in slices) {
      final sweep = (slice.value / total) * math.pi * 2;
      paint.color = slice.color;
      canvas.drawArc(
        rect.deflate(size.width * 0.07),
        sweepStart,
        sweep,
        false,
        paint,
      );
      sweepStart += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutDistributionPainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}

class _CounselingCase {
  final String id;
  final Map<String, dynamic> data;

  const _CounselingCase(this.id, this.data);

  factory _CounselingCase.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return _CounselingCase(doc.id, doc.data());
  }
}

class _CounselingMetrics {
  final int total;
  final int completed;
  final int awaitingCallSlip;
  final int scheduled;
  final Map<String, int> sourceCounts;
  final Map<String, int> typeCounts;
  final Map<String, int> studentCounts;
  final Map<String, int> monthCounts;

  const _CounselingMetrics({
    required this.total,
    required this.completed,
    required this.awaitingCallSlip,
    required this.scheduled,
    required this.sourceCounts,
    required this.typeCounts,
    required this.studentCounts,
    required this.monthCounts,
  });

  factory _CounselingMetrics.from(
    List<_CounselingCase> allCases,
    List<_CounselingCase> completedCases,
  ) {
    String safe(dynamic value) => (value ?? '').toString().trim();
    String prettySource(String source) {
      final s = source.toLowerCase().trim();
      if (s == 'student') return 'Self-referral';
      if (s == 'professor') return 'Professor referral';
      return s.isEmpty ? 'Unknown' : source;
    }

    String prettyType(String type) {
      final t = type.toLowerCase().trim();
      if (t == 'academic') return 'Academic';
      if (t == 'personal') return 'Personal';
      return t.isEmpty ? 'Unknown' : type;
    }

    final sourceCounts = <String, int>{};
    final typeCounts = <String, int>{};
    final studentCounts = <String, int>{};
    final monthCounts = <String, int>{};

    for (final c in completedCases) {
      final source = prettySource(safe(c.data['referralSource']));
      final type = prettyType(safe(c.data['counselingType']));
      final student = safe(c.data['studentName']).isEmpty
          ? 'Unknown Student'
          : safe(c.data['studentName']);
      final createdAt = c.data['createdAt'];
      final date = createdAt is Timestamp
          ? createdAt.toDate()
          : createdAt is DateTime
          ? createdAt
          : null;
      final month = date == null
          ? 'Unknown'
          : DateFormat('MMM yyyy').format(date);

      sourceCounts[source] = (sourceCounts[source] ?? 0) + 1;
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      studentCounts[student] = (studentCounts[student] ?? 0) + 1;
      monthCounts[month] = (monthCounts[month] ?? 0) + 1;
    }

    return _CounselingMetrics(
      total: allCases.length,
      completed: completedCases.length,
      awaitingCallSlip: allCases
          .where((c) => CounselingCaseState.isAwaitingCallSlip(c.data))
          .length,
      scheduled: allCases
          .where((c) => CounselingCaseState.isScheduled(c.data))
          .length,
      sourceCounts: _sortCounts(sourceCounts),
      typeCounts: _sortCounts(typeCounts),
      studentCounts: _sortCounts(studentCounts),
      monthCounts: _sortCounts(monthCounts),
    );
  }

  static Map<String, int> _sortCounts(Map<String, int> input) {
    final entries = input.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, int>.fromEntries(entries);
  }
}
