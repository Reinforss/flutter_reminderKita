import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart'; 
import 'package:intl/intl.dart';
import 'package:flutter/services.dart'; // PENTING: Untuk Clipboard
import 'dart:math'; // PENTING: Untuk Random

class ClassBoardPage extends StatefulWidget {
  const ClassBoardPage({super.key});

  @override
  State<ClassBoardPage> createState() => _ClassBoardPageState();
}

class _ClassBoardPageState extends State<ClassBoardPage> {
  final _currentUserEmail = Supabase.instance.client.auth.currentUser?.email;
  
  String _userRole = 'student'; 
  int _classId = 0;
  String _className = '';
  bool _isDataLoaded = false;
  
  // -- OPTIMISASI: Inisialisasi stream sebagai variabel agar tidak rebuild --
  late Stream<List<Map<String, dynamic>>> _tasksStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isDataLoaded) {
      final args = ModalRoute.of(context)?.settings.arguments as Map?;
      if (args != null) {
        _classId = args['id'];
        _className = args['nama'];
        if (args['role'] != null) {
          _userRole = args['role'].toString();
        }
      }
      
      // -- OPTIMISASI: Init stream di sini, bukan di build --
      _tasksStream = Supabase.instance.client
          .from('tasks')
          .stream(primaryKey: ['id'])
          .eq('kelas_id', _classId)
          .order('created_at', ascending: false);
          
      _isDataLoaded = true;
    }
  }

  Future<void> _deleteTask(int taskId) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Konfirmasi Hapus"),
        content: const Text("Yakin ingin menghapus pengingat ini?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Batal")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Hapus", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      EasyLoading.show();
      await Supabase.instance.client.from('tasks').delete().match({'id': taskId});
      EasyLoading.dismiss();
    }
  }

  // --- LOGIKA KELUAR KELAS ---
  Future<void> _handleExitClass() async {
    bool isAdmin =
        _userRole == 'admin' ||
        _userRole == 'Wakil Ketua Kelas' ||
        _userRole == 'Ketua Kelas';

    // === MEMBER BIASA ===
    if (!isAdmin) {
      bool confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Keluar Kelas?"),
          content: const Text(
              "Anda tidak akan bisa mengakses tugas dan materi kelas ini lagi."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Batal")),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text("Keluar", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ) ??
          false;

      if (!confirm) return;

      EasyLoading.show(status: 'Keluar kelas...');
      await Supabase.instance.client
          .from('anggota_kelas')
          .delete()
          .match({
            'kelas_id': _classId,
            'user_email': _currentUserEmail!,
          });

      EasyLoading.showSuccess("Berhasil keluar!");
      if (mounted) {
        Navigator.popUntil(context, ModalRoute.withName('/home'));
      }
      return;
    }

    // === ADMIN / KETUA ===
    bool confirmDelete = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Hapus Kelas?"),
            content: const Text(
                "Anda adalah Ketua Kelas. Jika keluar, kelas akan dihapus permanen"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Batal")),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Hapus Kelas",
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmDelete) {
      _deleteClassPermanently();
    }
  }

  Future<void> _deleteClassPermanently() async {
    bool reallySure = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("YAKIN HAPUS KELAS?"),
        content: const Text("Tindakan ini tidak bisa dibatalkan. Semua tugas, jadwal, dan anggota akan dihapus."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Batal")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Hapus Sekarang", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    ) ?? false;

    if (reallySure) {
      EasyLoading.show(status: 'Menghapus kelas...');
      try {
        await Supabase.instance.client.from('kelas').delete().eq('id', _classId);
        EasyLoading.showSuccess("Kelas dihapus.");
        if (mounted) Navigator.popUntil(context, ModalRoute.withName('/home'));
      } catch (e) {
        EasyLoading.showError("Gagal: $e");
      }
    }
  }
  
  // --- LOGIKA ANGGOTA (KICK & REGENERATE) ---
  Future<void> _kickMember(int memberId, String name) async {
    bool confirm = await showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        title: Text("Keluarkan $name?"),
        content: const Text("User ini tidak akan bisa mengakses kelas lagi."),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text("Batal")),
          TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text("Keluarkan", style: TextStyle(color: Colors.red))),
        ],
      )
    ) ?? false;

    if (confirm) {
      EasyLoading.show();
      await Supabase.instance.client.from('anggota_kelas').delete().eq('id', memberId);
      EasyLoading.dismiss();
      if(mounted) {
        Navigator.pop(context); // Tutup modal
        _showMemberList(); // Refresh modal
      }
    }
  }

  Future<void> _regenerateCode(String column) async {
     const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
     String newCode = String.fromCharCodes(Iterable.generate(5, (_) => chars.codeUnitAt(Random().nextInt(chars.length))));

     await Supabase.instance.client.from('kelas').update({column: newCode}).eq('id', _classId);
     setState(() {});
     if(mounted) {
        Navigator.pop(context);
        _showMemberList();
     }
  }

  // --- UI MODALS ---

  void _showTaskDetail(Map task) {
    String formattedDate = '-';
    if (task['waktu_reminder'] != null) {
      formattedDate = DateFormat('EEEE, d MMMM yyyy • HH:mm', 'id_ID').format(DateTime.parse(task['waktu_reminder']));
    }

    bool isAuthor = task['author_email'] == _currentUserEmail;
    bool isAdmin = _userRole == 'admin' || _userRole == 'vice_admin' || _userRole == 'Ketua Kelas';
    bool canEditDelete = isAuthor || isAdmin; 

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (task['gambar_url'] != null && task['gambar_url'] != '')
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(task['gambar_url'], width: double.infinity, height: 200, fit: BoxFit.cover),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.withOpacity(0.2))),
                          child: Text(task['mata_kuliah'] ?? 'Umum', style: const TextStyle(color: Color(0xFF1E40AF), fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const Spacer(),
                        if (canEditDelete) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/task-form', arguments: {'classId': _classId, 'taskData': task});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () {
                              Navigator.pop(context);
                              _deleteTask(task['id']);
                            },
                          )
                        ]
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(task['judul'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time_filled, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text("Deskripsi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(task['deskripsi'] ?? 'Tidak ada deskripsi tambahan.', style: TextStyle(fontSize: 15, height: 1.6, color: Colors.grey[800])),
                    const SizedBox(height: 24),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(backgroundColor: Colors.grey[200], child: const Icon(Icons.person, color: Colors.grey)),
                      title: Text(task['author_name'] ?? 'Pengguna', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text("Memposting pengingat ini"),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMemberList() {
    bool isAdmin = _userRole == 'admin' || _userRole == 'vice_admin' || _userRole == 'Ketua Kelas';
    bool isMainAdmin = _userRole == 'admin' || _userRole == 'Ketua Kelas';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        // PENTING: Gunakan ListView sebagai parent utama, bukan Column
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView( 
            controller: scrollController, // Controller dipasang di sini
            padding: const EdgeInsets.all(24.0),
            children: [
              // 1. HEADER (Garis Handle)
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 20),

              // 2. JUDUL
              const Text("Anggota & Pengaturan",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              // 3. ADMIN PANEL (Logic tetap sama)
              if (isAdmin)
                FutureBuilder(
                  future: Supabase.instance.client
                      .from('kelas')
                      .select()
                      .eq('id', _classId)
                      .single(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox(); // Loading state hidden
                    final kelasData = snapshot.data as Map;
                    final isOpen = kelasData['is_open'] ?? true;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Kode Akses",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue)),
                              if (isMainAdmin)
                                Switch(
                                  value: isOpen,
                                  onChanged: (val) async {
                                    await Supabase.instance.client
                                        .from('kelas')
                                        .update({'is_open': val}).eq(
                                            'id', _classId);
                                    setState(() {});
                                    if (mounted) {
                                      Navigator.pop(context);
                                      _showMemberList();
                                    }
                                  },
                                )
                            ],
                          ),
                          if (isOpen) ...[
                            _buildCodeRow("Mahasiswa",
                                kelasData['kode_kelas'] ?? '-', isMainAdmin, 'kode_kelas'),
                            const Divider(),
                            _buildCodeRow("Wakil Ketua",
                                kelasData['kode_wakil'] ?? '(Belum ada)', isMainAdmin, 'kode_wakil'),
                          ] else
                            const Text("Penerimaan anggota baru dimatikan.",
                                style: TextStyle(
                                    color: Colors.red,
                                    fontStyle: FontStyle.italic)),
                        ],
                      ),
                    );
                  },
                ),

              const Text("Daftar Anggota",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),

              // 4. DAFTAR ANGGOTA (Tanpa Expanded)
              FutureBuilder(
                future: Supabase.instance.client
                    .from('anggota_kelas')
                    .select()
                    .eq('kelas_id', _classId)
                    .order('role'),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(),
                    ));
                  }
                  final members = snapshot.data as List;

                  // PENTING: Gunakan shrinkWrap: true dan matikan scroll physics 
                  // agar menyatu dengan scroll parent
                  return ListView.separated(
                    shrinkWrap: true, 
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: members.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final m = members[index];
                      bool isTargetAdmin = m['role'] == 'admin' || m['role'] == 'Ketua Kelas';
                      bool isSelf = m['user_email'] == _currentUserEmail;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: m['role'] == 'admin' || m['role'] == 'Ketua Kelas'
                              ? Colors.orange[100]
                              : (m['role'] == 'vice_admin'
                                  ? Colors.purple[100]
                                  : Colors.blue[100]),
                              backgroundImage: m['avatar_url'] != null 
                              ? NetworkImage(m['avatar_url']) 
                              : null,
                          child: Text(
                              (m['user_name']?[0] ?? 'U').toUpperCase(),
                              style: TextStyle(
                                  color: m['role'] == 'admin' || m['role'] == 'Ketua Kelas'
                                      ? Colors.orange
                                      : (m['role'] == 'vice_admin'
                                          ? Colors.purple
                                          : Colors.blue))),
                        ),
                        title: Text(m['user_name'] ?? 'No Name',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(m['role'] == 'admin' || m['role'] == 'Ketua Kelas'
                            ? 'Ketua Kelas'
                            : (m['role'] == 'vice_admin'
                                ? 'Wakil Ketua'
                                : m['nim'] ?? '-')),
                        trailing: (isAdmin && !isTargetAdmin && !isSelf)
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Colors.red),
                                onPressed: () => _kickMember(
                                    m['id'], m['user_name'] ?? 'User'),
                              )
                            : (isTargetAdmin
                                ? const Icon(Icons.star, color: Colors.orange)
                                : null),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 24),
              const Divider(),

              // 5. TOMBOL KELUAR
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleExitClass();
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text("Keluar dari Kelas",
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.red.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeRow(String label, String code, bool canEdit, String dbColumn) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                SelectableText(code, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ],
            ),
          ),
          IconButton(
             icon: const Icon(Icons.copy, size: 20, color: Colors.blue),
             onPressed: () {
               Clipboard.setData(ClipboardData(text: code));
               EasyLoading.showToast("Disalin!");
             }
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20, color: Colors.orange),
              onPressed: () => _regenerateCode(dbColumn), 
            )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(_className, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined, color: Color(0xFF2563EB)),
            onPressed: () => Navigator.pushNamed(context, '/schedule', arguments: {'classId': _classId, 'role': _userRole}),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline, color: Colors.black54),
            onPressed: _showMemberList,
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _tasksStream, // Menggunakan variabel stream yang sudah di-init
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_turned_in_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("Tidak ada pengingat aktif", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) => _buildTaskCard(snapshot.data![index]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2563EB),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Buat Pengingat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.pushNamed(context, '/task-form', arguments: {'classId': _classId}),
      ),
    );
  }

  Widget _buildTaskCard(Map task) {
    bool isOverdue = false;
    String reminderText = '-';
    Color timeColor = Colors.grey;
      if (task['waktu_reminder'] != null) {
      final date = DateTime.parse(task['waktu_reminder']);
      reminderText = DateFormat('EEE, d MMM • HH:mm', 'id_ID').format(date);
      
      final now = DateTime.now();
      
      if (date.isBefore(now)) {
        timeColor = Colors.red[900]!; // Dark Red for Overdue
        reminderText = "Terlewat: $reminderText";
        isOverdue = true;
      } else if (date.difference(now).inDays < 2) {
        timeColor = Colors.red; // Bright Red for near deadline
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 5))
        ]
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showTaskDetail(task),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (task['gambar_url'] != null && task['gambar_url'] != '')
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  // -- OPTIMISASI: Image Cache & Error Handling --
                  child: Image.network(
                    task['gambar_url'], 
                    height: 140, 
                    width: double.infinity, 
                    fit: BoxFit.cover,
                    cacheHeight: 400, // Resize gambar di memory agar tidak berat (Lag reduction)
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 140,
                        width: double.infinity,
                        color: Colors.grey[100],
                        child: const Center(child: Icon(Icons.image, color: Colors.grey)),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 140,
                      width: double.infinity,
                      color: Colors.grey[200],
                      child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                          child: Text(task['mata_kuliah'] ?? 'Umum', style: const TextStyle(color: Color(0xFF1E40AF), fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        Row(
                          children: [
                            Icon(isOverdue ? Icons.error_outline : Icons.access_time_rounded, size: 14, color: timeColor),
                            const SizedBox(width: 4),
                            Text(reminderText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: timeColor)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(task['judul'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.3)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 10, 
                          backgroundColor: Colors.grey[200],
                          // Logika Foto Profil
                          backgroundImage: task['author_avatar_url'] != null 
                              ? NetworkImage(task['author_avatar_url']) 
                              : null,
                          child: task['author_avatar_url'] == null 
                              ? const Icon(Icons.person, size: 12, color: Colors.grey)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Text(task['author_name']?.split(' ')[0] ?? 'User', /* style text */),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}