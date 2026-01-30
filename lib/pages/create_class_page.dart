import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter/services.dart'; // Untuk clipboard
import 'dart:math';

class CreateClassPage extends StatefulWidget {
  const CreateClassPage({super.key});

  @override
  State<CreateClassPage> createState() => _CreateClassPageState();
}

class _CreateClassPageState extends State<CreateClassPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  String _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(5, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  @override
  void initState() {
    super.initState();
    _codeController.text = _generateRandomCode();
  }

  Future<void> _createClass() async {
    if (_nameController.text.trim().isEmpty) {
      EasyLoading.showError("Nama kelas wajib diisi");
      return;
    }

    EasyLoading.show(status: 'Membuat ruang kelas...');
    final user = Supabase.instance.client.auth.currentUser;
    
    final userName = user!.userMetadata?['name'] ?? 'Admin';
    final userNim = user.userMetadata?['nim'] ?? '-';

    try {
      final classData = await Supabase.instance.client.from('kelas').insert({
        'nama_kelas': _nameController.text.trim(),
        'kode_kelas': _codeController.text,
        'kode_wakil': 'W-${_generateRandomCode()}', // Tambahkan kode wakil default
        'is_open': true,
      }).select().single();

      await Supabase.instance.client.from('anggota_kelas').insert({
        'kelas_id': classData['id'],
        'user_email': user.email,
        'role': 'admin',
        'user_name': userName,
        'nim': userNim,
      });

      EasyLoading.showSuccess('Kelas Berhasil Dibuat!');
      if(mounted) Navigator.pop(context);
    } catch (e) {
      EasyLoading.showError('Gagal membuat kelas: $e'); 
    } finally {
      EasyLoading.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Buat Kelas Baru", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.domain_add_rounded, size: 60, color: Color(0xFF2563EB)),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              "Detail Kelas",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Nama Kelas',
                hintText: 'Contoh: Teknik Informatika A',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2)),
                prefixIcon: const Icon(Icons.school_outlined),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              ),
            ),
            
            const SizedBox(height: 32),

            const Text(
              "Kode Unik Kelas",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
                ]
              ),
              child: Column(
                children: [
                  const Text(
                    "BAGIKAN KODE INI",
                    style: TextStyle(color: Colors.white70, letterSpacing: 1.5, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _codeController.text,
                        style: const TextStyle(
                          fontSize: 48, 
                          fontWeight: FontWeight.w900, 
                          color: Colors.white, 
                          letterSpacing: 4
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => setState(() => _codeController.text = _generateRandomCode()),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text("Acak Ulang"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _codeController.text));
                          EasyLoading.showToast("Kode disalin!");
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text("Salin"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF2563EB),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
             Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Kode ini diperlukan mahasiswa untuk bergabung.",
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 50),
            
            SizedBox(
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B), // Dark Slate
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 5,
                  shadowColor: Colors.black26,
                ),
                onPressed: _createClass,
                child: const Text("Selesai & Buat Kelas", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}