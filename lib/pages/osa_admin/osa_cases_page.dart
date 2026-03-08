import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:apps/services/violation_case_service.dart';

class OsaCasesPage extends StatelessWidget {
  OsaCasesPage({super.key});

  final _svc = ViolationCaseService();

  // ===== THEME (match your app) =====
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 900;

        // ✅ fixed-width content (no ugly stretch)
        const double fixedWidth = 820.0;
        final double cardWidth = constraints.maxWidth < fixedWidth
            ? constraints.maxWidth
            : fixedWidth;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            foregroundColor: primary,
            title: const Text(
              'Violation Cases (Phase 1)',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: SizedBox(
                width: cardWidth,
                child: Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 0 : 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.15),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _svc.streamAllCases(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snap.error}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      if (!snap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final docs = snap.data!.docs;

                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'No cases yet.',
                            style: TextStyle(
                              color: hint,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        itemCount: docs.length,
                        separatorBuilder: (_, index) => Divider(
                          height: 14,
                          color: primary.withValues(alpha: 0.12),
                        ),
                        itemBuilder: (context, i) {
                          final d = docs[i].data();

                          final caseId = (d['caseId'] ?? docs[i].id).toString();
                          final student = (d['studentName'] ?? 'Unknown')
                              .toString();
                          final studentNo = (d['studentNo'] ?? '').toString();
                          final category = (d['misconductCategory'] ?? '')
                              .toString();
                          final status = (d['status'] ?? '').toString();

                          final statusIsSubmitted = status == 'Submitted';

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: primary.withValues(alpha: 0.12),
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: primary.withValues(
                                  alpha: 0.12,
                                ),
                                child: Icon(
                                  Icons.gavel_rounded,
                                  color: primary.withValues(alpha: 0.85),
                                ),
                              ),
                              title: Text(
                                '$student${studentNo.isEmpty ? '' : ' ($studentNo)'}',
                                style: const TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.w900,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${category.isEmpty ? '—' : category}\nCase: $caseId',
                                  style: TextStyle(
                                    color: hint,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              isThreeLine: true,
                              trailing: statusIsSubmitted
                                  ? TextButton(
                                      onPressed: () =>
                                          _svc.markUnderReview(caseId),
                                      style: TextButton.styleFrom(
                                        foregroundColor: primary,
                                        textStyle: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      child: const Text('Mark Under Review'),
                                    )
                                  : Text(
                                      status.isEmpty ? '—' : status,
                                      style: TextStyle(
                                        color: status == 'Under Review'
                                            ? primary
                                            : hint,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          );
                        },
                      );
                    },
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
