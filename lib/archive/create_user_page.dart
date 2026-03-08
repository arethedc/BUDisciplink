import 'package:flutter/material.dart';

class CreateUserPage extends StatefulWidget {
  const CreateUserPage({super.key});

  @override
  State<CreateUserPage> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<CreateUserPage> {
  String selectedRole = 'student';
  String selectedYearLevel = '1st Year';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create User Account'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.person_add,
              size: 80,
              color: Colors.green,
            ),
            const SizedBox(height: 16),

            const Text(
              'New User Details',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),

            const SizedBox(height: 30),

            // Full Name
            TextField(
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: const Icon(Icons.person, color: Colors.green),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Email
            TextField(
              decoration: InputDecoration(
                labelText: 'Email Address',
                prefixIcon: const Icon(Icons.email, color: Colors.green),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Role
            DropdownButtonFormField<String>(
              initialValue: selectedRole,
              decoration: InputDecoration(
                labelText: 'Role',
                prefixIcon: const Icon(Icons.security, color: Colors.green),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'student', child: Text('Student')),
                DropdownMenuItem(value: 'teacher', child: Text('Faculty')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (value) {
                setState(() {
                  selectedRole = value!;
                });
              },
            ),

            const SizedBox(height: 20),

            // STUDENT-ONLY (COLLEGE)
            if (selectedRole == 'student') ...[
              // Student Number
              TextField(
                decoration: InputDecoration(
                  labelText: 'Student Number',
                  prefixIcon:
                  const Icon(Icons.badge, color: Colors.green),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Program / Course
              TextField(
                decoration: InputDecoration(
                  labelText: 'Program / Course',
                  prefixIcon:
                  const Icon(Icons.school, color: Colors.green),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Year Level
              DropdownButtonFormField<String>(
                initialValue: selectedYearLevel,
                decoration: InputDecoration(
                  labelText: 'Year Level',
                  prefixIcon:
                  const Icon(Icons.timeline, color: Colors.green),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: '1st Year', child: Text('1st Year')),
                  DropdownMenuItem(value: '2nd Year', child: Text('2nd Year')),
                  DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
                  DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
                ],
                onChanged: (value) {
                  setState(() {
                    selectedYearLevel = value!;
                  });
                },
              ),
              const SizedBox(height: 20),
            ],

            // Temporary Password
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Temporary Password',
                prefixIcon: const Icon(Icons.lock, color: Colors.green),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: () {
                // TODO: Firebase Auth + Firestore
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'CREATE ACCOUNT',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
