import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:intl/intl.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _days = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu'
  ];

  int _classId = 0;
  String _userRole = 'student';
  
  // -- OPTIMISASI: Cache Data Lokal --
  List<Map<String, dynamic>> _subjectsList = [];
  Map<int, Map<String, dynamic>> _tasksCache = {}; // Key: matakuliah_id
  
  bool _isDataLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _days.length, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isDataLoaded) {
      final args = ModalRoute.of(context)!.settings.arguments as Map;
      _classId = args['classId'];
      _userRole = args['role']?.toString() ?? 'student';
      
      // Panggil fungsi preload data sekali saja di awal
      _preloadData();
      _isDataLoaded = true;
    }
  }

  // -- OPTIMISASI: Ambil data Matkul & Tugas sekaligus di awal --
  Future<void> _preloadData() async {
    try {
      // 1. Ambil Semua Mata Kuliah di Kelas Ini
      final subjectsData = await Supabase.instance.client
          .from('matakuliah')
          .select()
          .eq('kelas_id', _classId)
          .order('nama', ascending: true);
      
      // 2. Ambil Tugas Deadline Terdekat (Hanya yang belum lewat)
      final now = DateTime.now().toIso8601String();
      final tasksData = await Supabase.instance.client
          .from('tasks')
          .select('id, judul, waktu_reminder, matakuliah_id')
          .eq('kelas_id', _classId)
          .gt('waktu_reminder', now)
          .order('waktu_reminder', ascending: true);

      // 3. Mapping Tugas ke Matkul ID untuk akses cepat (O(1))
      Map<int, Map<String, dynamic>> tempTaskCache = {};
      for (var t in tasksData) {
        int mkId = t['matakuliah_id'] ?? 0;
        // Kita hanya simpan 1 tugas terdekat per matkul
        if (!tempTaskCache.containsKey(mkId)) {
          tempTaskCache[mkId] = t;
        }
      }

      if (mounted) {
        setState(() {
          _subjectsList = List<Map<String, dynamic>>.from(subjectsData);
          _tasksCache = tempTaskCache;
        });
      }
    } catch (e) {
      print("Error loading data: $e");
    }
  }

  // -- OPTIMISASI: Stream ringan tanpa query database di dalamnya --
  Stream<List<Map<String, dynamic>>> _scheduleStream(String day) {
    return Supabase.instance.client
        .from('jadwal_kelas')
        .stream(primaryKey: ['id'])
        .eq('kelas_id', _classId) 
        .map((list) {
            // Filter hari di sisi aplikasi (karena realtime stream filter terbatas)
            final filtered = list.where((item) => item['hari'] == day).toList();
            
            // Sorting jam
            filtered.sort((a, b) => (a['jam_mulai'] as String).compareTo(b['jam_mulai'] as String));
            
            // JOIN DATA di Memory (Cepat & Sinkron)
            return filtered.map((item) {
              final newItem = Map<String, dynamic>.from(item);
              
              // Cari nama matkul dari List Memory
              final subject = _subjectsList.firstWhere(
                (s) => s['id'] == item['matakuliah_id'], 
                orElse: () => {'nama': 'Matkul Dihapus', 'dosen': '-'}
              );

              newItem['matkul_nama'] = subject['nama'];
              newItem['dosen'] = subject['dosen'];

              // Cari tugas dari Cache Memory
              if (_tasksCache.containsKey(item['matakuliah_id'])) {
                final task = _tasksCache[item['matakuliah_id']];
                newItem['task_title'] = task!['judul'];
                newItem['task_deadline'] = task['waktu_reminder'];
              }

              return newItem;
            }).toList();
        });
  }

  // ================= DEADLINE HELPERS =================

  String _formatDeadlineWithLabel(String deadline) {
    final dt = DateTime.parse(deadline);
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final target = DateTime(dt.year, dt.month, dt.day);

    final time = DateFormat('HH:mm').format(dt);

    if (target == today) {
      return "(Hari ini, $time)";
    } else if (target == tomorrow) {
      return "(Besok, $time)";
    } else {
      final date = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dt);
      return "($date • $time)";
    }
  }

  Color _deadlineColor(String deadline) {
    final dt = DateTime.parse(deadline);
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final target = DateTime(dt.year, dt.month, dt.day);

    if (target == today) return Colors.redAccent;
    if (target == tomorrow) return Colors.orange;
    return Colors.orange.shade900;
  }

  // ===================================================

  Future<void> _deleteSchedule(int id) async {
    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Hapus Jadwal?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Batal")),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Hapus", style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;
    if (confirm) {
      await Supabase.instance.client
          .from('jadwal_kelas')
          .delete()
          .match({'id': id});
    }
  }

  Future<void> _showScheduleForm({Map<String, dynamic>? data}) async {
    final isEdit = data != null;

    int? selectedSubjectId = isEdit ? data['matakuliah_id'] : null;
    String selectedDay = isEdit ? data['hari'] : _days[_tabController.index];
    
    TimeOfDay parseTime(String timeStr) {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    TimeOfDay startTime = isEdit
        ? parseTime(data['jam_mulai'].toString())
        : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = isEdit
        ? parseTime(data['jam_selesai'].toString())
        : const TimeOfDay(hour: 10, minute: 0);
        
    final roomController = TextEditingController(text: isEdit ? data['ruangan'] : '');

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              isEdit ? "Edit Jadwal" : "Tambah Jadwal",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedDay,
                    decoration: InputDecoration(
                      labelText: 'Hari',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: _days
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => selectedDay = val!),
                  ),
                  const SizedBox(height: 16),
                  if (_subjectsList.isEmpty)
                    const Text(
                      "Buat mata kuliah dulu di menu tugas.",
                      style: TextStyle(color: Colors.red),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: selectedSubjectId,
                      decoration: InputDecoration(
                        labelText: 'Mata Kuliah',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: _subjectsList
                          .map((s) => DropdownMenuItem(
                                value: s['id'] as int,
                                child: Text(s['nama']),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedSubjectId = v),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: startTime,
                            );
                            if (t != null) {
                              setDialogState(() => startTime = t);
                            }
                          },
                          child: Text("Mulai: ${startTime.format(context)}"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: endTime,
                            );
                            if (t != null) {
                              setDialogState(() => endTime = t);
                            }
                          },
                          child: Text("Selesai: ${endTime.format(context)}"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: roomController,
                    decoration: InputDecoration(
                      labelText: 'Ruangan',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Batal"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedSubjectId != null && roomController.text.isNotEmpty) {
                    EasyLoading.show();
                    try {
                      final startStr =
                          '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00';
                      final endStr =
                          '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00';

                      final payload = {
                        'kelas_id': _classId,
                        'matakuliah_id': selectedSubjectId,
                        'hari': selectedDay,
                        'jam_mulai': startStr,
                        'jam_selesai': endStr,
                        'ruangan': roomController.text,
                      };

                      if (isEdit) {
                        await Supabase.instance.client
                            .from('jadwal_kelas')
                            .update(payload)
                            .eq('id', data['id']);
                      } else {
                        await Supabase.instance.client
                            .from('jadwal_kelas')
                            .insert(payload);
                      }
                      
                      EasyLoading.dismiss();
                      Navigator.pop(context);
                      
                      // Refresh data agar cache sinkron jika ada matkul baru/edit
                      _preloadData(); 
                      
                    } catch (e) {
                      EasyLoading.showError("Gagal: $e");
                    }
                  }
                },
                child: Text(isEdit ? "Simpan" : "Tambah"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Jadwal Kuliah",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blueAccent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: _days.map((d) => Tab(text: d)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _days.map((day) {
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _scheduleStream(day),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && _subjectsList.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              color: Colors.grey[100], shape: BoxShape.circle),
                          child: Icon(Icons.weekend_outlined,
                              size: 50, color: Colors.grey[400])),
                      const SizedBox(height: 16),
                      Text("Tidak ada jadwal",
                          style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final item = snapshot.data![index];
                  final jamMulai = item['jam_mulai'].toString().substring(0, 5);
                  final jamSelesai =
                      item['jam_selesai'].toString().substring(0, 5);

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          children: [
                            Text(jamMulai,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(jamSelesai,
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 12)),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: 4,
                          decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(2)),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              margin: const EdgeInsets.only(top: 8),
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey[200]!),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.grey.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ]),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                        child: Text(item['matkul_nama'] ?? '',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16))),
                                    // FITUR EDIT & DELETE
                                    if (_userRole == 'Ketua Kelas')
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GestureDetector(
                                              onTap: () =>
                                                  _showScheduleForm(data: item),
                                              child: const Icon(Icons.edit,
                                                  size: 18,
                                                  color: Colors.blueGrey)),
                                          const SizedBox(width: 12),
                                          GestureDetector(
                                              onTap: () =>
                                                  _deleteSchedule(item['id']),
                                              child: const Icon(Icons.close,
                                                  size: 18,
                                                  color: Colors.redAccent)),
                                        ],
                                      )
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.person_outline,
                                      size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: Text(item['dosen'] ?? '-',
                                          style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 13)))
                                ]),
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(item['ruangan'] ?? '-',
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 13))
                                ]),
                                if (item['task_title'] != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: Colors.orange[50],
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.warning_amber_rounded,
                                            color: Colors.orange, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            "${item['task_title']} "
                                            "${_formatDeadlineWithLabel(item['task_deadline'])}",
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _deadlineColor(
                                                    item['task_deadline'])),
                                          ),
                                        )
                                      ],
                                    ),
                                  )
                                ]
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  );
                },
              );
            },
          );
        }).toList(),
      ),
      floatingActionButton: _userRole == 'Ketua Kelas'
          ? FloatingActionButton(
              onPressed: () => _showScheduleForm(), 
              backgroundColor: Colors.blueAccent,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}