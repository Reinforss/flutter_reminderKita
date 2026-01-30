import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:image_picker/image_picker.dart';

class TaskFormPage extends StatefulWidget {
  const TaskFormPage({super.key});

  @override
  State<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> {
  final _formKey = GlobalKey<FormState>();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final _judulController = TextEditingController();
  final _deskripsiController = TextEditingController();

  // State Variables
  String _uploadedImageUrl = '';
  final ImagePicker _picker = ImagePicker();

  DateTime? _selectedDate;
  int? _classId;
  int? _taskId;

  List<Map<String, dynamic>> _subjectsList = [];
  int? _selectedSubjectId;
  String _selectedSubjectName = '';
  String _selectedLecturerName = '';

  String _userRole = 'student'; // Default role
  bool _isDataLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isDataLoaded) {
      final args = ModalRoute.of(context)?.settings.arguments as Map?;
      if (args != null) {
        _classId = args['classId'] ?? args['id'];

        // Load Data Awal
        _fetchSubjects();
        _fetchUserRole(); // Cek Role User

        // Jika Mode Edit (Ada data taskData)
        if (args.containsKey('taskData')) {
          final data = args['taskData'];
          _taskId = data['id'];
          _judulController.text = data['judul'] ?? '';
          _deskripsiController.text = data['deskripsi'] ?? '';

          _uploadedImageUrl = data['gambar_url'] ?? '';

          _selectedSubjectName = data['mata_kuliah'] ?? '';
          _selectedLecturerName = data['dosen_pengampu'] ?? '';

          if (data['matakuliah_id'] != null) {
            _selectedSubjectId = data['matakuliah_id'];
          }
          if (data['waktu_reminder'] != null) {
            _selectedDate = DateTime.parse(data['waktu_reminder']);
          }
        }
      }
      _isDataLoaded = true;
    }
  }

  // --- 1. FETCH DATA (Role & Subjects) ---

  Future<void> _fetchUserRole() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _classId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('anggota_kelas')
          .select('role')
          .eq('kelas_id', _classId!)
          .eq('user_email', user.email!)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _userRole = data['role'] ?? 'student';
        });
      }
    } catch (e) {
      debugPrint("Gagal ambil role: $e");
    }
  }

  Future<void> _fetchSubjects() async {
    if (_classId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('matakuliah')
          .select()
          .eq('kelas_id', _classId!)
          .order('nama', ascending: true);
      if (mounted)
        setState(() => _subjectsList = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      print("Error fetch subjects: $e");
    }
  }

  Future<void> _showAddSubjectDialog() async {
    final nameCtrl = TextEditingController();
    final lecturerCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Tambah Mata Kuliah"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: "Nama Matkul",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lecturerCtrl,
              decoration: InputDecoration(
                labelText: "Nama Dosen",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                EasyLoading.show();
                try {
                  await Supabase.instance.client.from('matakuliah').insert({
                    'kelas_id': _classId,
                    'nama': nameCtrl.text,
                    'dosen': lecturerCtrl.text,
                  });
                  EasyLoading.dismiss();
                  Navigator.pop(context);
                  _fetchSubjects();
                } catch (e) {
                  EasyLoading.showError("Gagal: $e");
                }
              }
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  // --- 2. IMAGE UPLOAD LOGIC ---

  Future<void> _pickTaskImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 60,
      );
      if (image == null) return;

      EasyLoading.show(status: 'Mengupload...');

      final fileName =
          'tasks/${DateTime.now().millisecondsSinceEpoch}_${image.name}';

      await Supabase.instance.client.storage
          .from('files')
          .uploadBinary(
            fileName,
            await File(image.path).readAsBytes(),
            fileOptions: const FileOptions(upsert: true),
          );

      final imageUrl = Supabase.instance.client.storage
          .from('files')
          .getPublicUrl(fileName);

      setState(() {
        _uploadedImageUrl = imageUrl;
      });
      EasyLoading.showSuccess('Gambar terupload!');
    } catch (e) {
      EasyLoading.showError('Upload gagal: $e');
    } finally {
      EasyLoading.dismiss();
    }
  }

  // --- 3. DATE & TIME PICKER (MODERN UI & 24H) ---

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final newDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: DateTime(2030),
      locale: const Locale('id', 'ID'),
    );

    if (newDate != null) {
      setState(() {
        final currentHour = _selectedDate?.hour ?? 9;
        final currentMinute = _selectedDate?.minute ?? 0;
        _selectedDate = DateTime(
          newDate.year,
          newDate.month,
          newDate.day,
          currentHour,
          currentMinute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate ?? DateTime.now()),
      builder: (BuildContext context, Widget? child) {
        // FORCE 24 HOUR FORMAT
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (newTime != null) {
      setState(() {
        final currentDate = _selectedDate ?? DateTime.now();
        _selectedDate = DateTime(
          currentDate.year,
          currentDate.month,
          currentDate.day,
          newTime.hour,
          newTime.minute,
        );
      });
    }
  }

  // --- 4. NOTIFICATION LOGIC ---

  Future<void> _scheduleNotification(
    int taskId,
    String title,
    DateTime dueDate,
  ) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(taskId * 10 + 1);
      await flutterLocalNotificationsPlugin.cancel(taskId * 10 + 2);
      await flutterLocalNotificationsPlugin.cancel(taskId * 10 + 3);

      final schedules = [
        {
          'id': 1,
          'duration': const Duration(days: 1),
          'body': 'Deadline besok!',
        },
        {
          'id': 2,
          'duration': const Duration(days: 2),
          'body': 'Deadline 2 hari lagi.',
        },
        {
          'id': 3,
          'duration': const Duration(days: 3),
          'body': 'Deadline 3 hari lagi, semangat!',
        },
      ];

      for (var item in schedules) {
        final scheduleTime = dueDate.subtract(item['duration'] as Duration);

        if (scheduleTime.isAfter(DateTime.now())) {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            taskId * 10 + (item['id'] as int),
            'Reminder: $title',
            item['body'] as String,
            tz.TZDateTime.from(scheduleTime, tz.local),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'channel_tugas',
                'Reminder Tugas',
                channelDescription: 'Notifikasi deadline tugas kuliah',
                importance: Importance.max,
                priority: Priority.high,
                color: Color(0xFF2563EB),
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        }
      }
    } catch (e) {
      print("Gagal notifikasi: $e");
    }
  }

  // --- 5. SAVE TASK ---

  Future<void> _saveTask() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedSubjectName.isEmpty) {
        EasyLoading.showInfo("Pilih Mata Kuliah dulu!");
        return;
      }
      if (_selectedDate == null) {
        EasyLoading.showError("Waktu Reminder wajib diisi!");
        return;
      }

      EasyLoading.show(status: 'Menyimpan...');
      final user = Supabase.instance.client.auth.currentUser;
      final data = {
        'kelas_id': _classId,
        'judul': _judulController.text,
        'deskripsi': _deskripsiController.text,
        'matakuliah_id': _selectedSubjectId,
        'mata_kuliah': _selectedSubjectName,
        'dosen_pengampu': _selectedLecturerName,
        'gambar_url': _uploadedImageUrl,
        'waktu_reminder': _selectedDate?.toIso8601String(),
        'author_email': user!.email,
        'author_name': user.userMetadata?['name'] ?? 'Mahasiswa',
        'author_nim': user.userMetadata?['nim'] ?? '-',
      };

      try {
        if (_taskId == null) {
          final res = await Supabase.instance.client
              .from('tasks')
              .insert(data)
              .select('id')
              .single();
          // Schedule Notification (UNCOMMENTED)
          await _scheduleNotification(
            res['id'],
            _judulController.text,
            _selectedDate!,
          );
        } else {
          data.remove('author_email');
          data.remove('author_name');
          data.remove('author_nim');
          await Supabase.instance.client.from('tasks').update(data).match({
            'id': _taskId!,
          });
          // Update notification
          await _scheduleNotification(
            _taskId!,
            _judulController.text,
            _selectedDate!,
          );
        }
        EasyLoading.showSuccess('Berhasil!');
        if (mounted) Navigator.pop(context);
      } catch (e) {
        EasyLoading.showError('Gagal: $e');
      }
    }
  }

  // --- 6. BUILD UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _taskId == null ? "Buat Reminder" : "Edit Reminder",
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("MATA KULIAH"),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value:
                                _subjectsList.any(
                                  (e) => e['id'] == _selectedSubjectId,
                                )
                                ? _selectedSubjectId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Pilih Matkul',
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                            ),
                            items: _subjectsList
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s['id'] as int,
                                    child: Text(s['nama']),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setState(() {
                                _selectedSubjectId = v;
                                final s = _subjectsList.firstWhere(
                                  (e) => e['id'] == v,
                                );
                                _selectedSubjectName = s['nama'];
                                _selectedLecturerName = s['dosen'] ?? '';
                              });
                            },
                          ),
                        ),
                        // TOMBOL ADD MATKUL: Hanya untuk Admin/Wakil
                        if (_userRole == 'admin' ||
                            _userRole == 'vice_admin' ||
                            _userRole == 'Ketua Kelas')
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle,
                              color: Colors.blue,
                            ),
                            onPressed: _showAddSubjectDialog,
                          ),
                      ],
                    ),
                    if (_selectedLecturerName.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectedLecturerName,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _buildSectionHeader("DETAIL TUGAS"),
              TextFormField(
                controller: _judulController,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                decoration: const InputDecoration(
                  hintText: 'Judul Tugas',
                  border: UnderlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? 'Judul wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deskripsiController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Tambahkan deskripsi atau catatan...',
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // --- LAMPIRAN GAMBAR ---
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Lampiran Gambar",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickTaskImage,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                        image: _uploadedImageUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(_uploadedImageUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _uploadedImageUrl.isEmpty
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_rounded,
                                  size: 40,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Ketuk untuk upload foto",
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ],
                            )
                          : Align(
                              alignment: Alignment.topRight,
                              child: IconButton(
                                icon: const CircleAvatar(
                                  backgroundColor: Colors.white,
                                  radius: 14,
                                  child: Icon(
                                    Icons.close,
                                    color: Colors.red,
                                    size: 16,
                                  ),
                                ),
                                onPressed: () =>
                                    setState(() => _uploadedImageUrl = ''),
                              ),
                            ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              _buildSectionHeader("TENGGAT WAKTU (DEADLINE)"),
              const SizedBox(height: 8),

              // --- DATE & TIME SPLIT UI ---
              Row(
                children: [
                  // KOLOM TANGGAL
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  size: 18,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "Tanggal",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedDate == null
                                  ? "Pilih Tanggal"
                                  : DateFormat(
                                      'EEE, d MMM yyyy',
                                      'id_ID',
                                    ).format(_selectedDate!),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: _selectedDate == null
                                    ? Colors.grey[400]
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // KOLOM JAM (24H Format)
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_filled_rounded,
                                  size: 18,
                                  color: Colors.orange[700],
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "Jam",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedDate == null
                                  ? "--:--"
                                  : DateFormat(
                                      'HH:mm',
                                    ).format(_selectedDate!), // Format 24H
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: _selectedDate == null
                                    ? Colors.grey[400]
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  onPressed: _saveTask,
                  child: const Text(
                    "Simpan Pengingat",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
