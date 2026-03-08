import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DepartmentAdminHomePage extends StatelessWidget {
  final VoidCallback? onOpenUserManagement;
  final VoidCallback? onOpenViolationReview;

  const DepartmentAdminHomePage({
    super.key,
    this.onOpenUserManagement,
    this.onOpenViolationReview,
  });

  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hint = Color(0xFF6D7F62);

  int _countByStatus(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Set<String> statuses,
  ) {
    return docs.where((doc) {
      final status = (doc.data()['status'] ?? '').toString().trim().toLowerCase();
      return statuses.contains(status);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(authUser.uid).snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final userData = userSnap.data!.data() ?? <String, dynamic>{};
        final dept = (userData['employeeProfile']?['department'] ?? '').toString().trim();
        if (dept.isEmpty) {
          return const Center(
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
              .snapshots(),
          builder: (context, studentsSnap) {
            if (!studentsSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final studentUids = studentsSnap.data!.docs.where((d) {
              final college = (d.data()['studentProfile']?['collegeId'] ?? '')
                  .toString()
                  .trim();
              return college == dept;
            }).map((d) => d.id).toSet();

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('violation_cases').snapshots(),
              builder: (context, casesSnap) {
                if (!casesSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final cases = casesSnap.data!.docs.where((doc) {
                  final uid = (doc.data()['studentUid'] ?? '').toString().trim();
                  return uid.isNotEmpty && studentUids.contains(uid);
                }).toList();

                final review = _countByStatus(cases, {'submitted', 'under review'});
                final monitoring = _countByStatus(cases, {'action set'});
                final resolved = _countByStatus(cases, {'resolved'});

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Department Overview',
                              style: TextStyle(
                                color: primary,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Scope: $dept',
                              style: const TextStyle(
                                color: hint,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _kpiCard('Students', studentUids.length, Icons.groups_rounded),
                          _kpiCard('For Review', review, Icons.inbox_rounded),
                          _kpiCard('Monitoring', monitoring, Icons.monitor_heart_rounded),
                          _kpiCard('Resolved', resolved, Icons.check_circle_rounded),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                        ),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: onOpenViolationReview,
                              icon: const Icon(Icons.rule_rounded),
                              label: const Text('Open Violation Alerts'),
                              style: FilledButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: onOpenUserManagement,
                              icon: const Icon(Icons.groups_rounded),
                              label: const Text('Open Student Management'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primary,
                                side: BorderSide(color: primary.withValues(alpha: 0.3)),
                              ),
                            ),
                          ],
                        ),
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

  Widget _kpiCard(String label, int value, IconData icon) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: hint,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
