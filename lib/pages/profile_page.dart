import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _nimController = TextEditingController(); // Read only
  String? _avatarUrl;
  
  final _currentUser = Supabase.instance.client.auth.currentUser;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    if (_currentUser != null) {
      final meta = _currentUser.userMetadata;
      _nameController.text = meta?['name'] ?? '';
      _nimController.text = meta?['nim'] ?? '';
      setState(() {
        _avatarUrl = meta?['avatar_url'];
      });
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;

      EasyLoading.show(status: 'Mengupload foto...');
      
      final fileExt = image.path.split('.').last;
      final fileName = '${_currentUser!.id}_profile.$fileExt';
      final filePath = 'avatars/$fileName';

      // Upload ke Supabase Storage bucket 'files'
      await Supabase.instance.client.storage
          .from('files')
          .uploadBinary(
            filePath,
            await File(image.path).readAsBytes(),
            fileOptions: const FileOptions(upsert: true),
          );

      // Ambil Public URL
      final imageUrl = Supabase.instance.client.storage
          .from('files')
          .getPublicUrl(filePath);

      // Update URL ke User Metadata (tanpa tekan tombol simpan)
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'avatar_url': imageUrl}),
      );

      await Supabase.instance.client
          .from('anggota_kelas')
          .update({'avatar_url': imageUrl})
          .eq('user_email', _currentUser.email!);

      await Supabase.instance.client
          .from('tasks')
          .update({'author_avatar_url': imageUrl})
          .eq('author_email', _currentUser.email!);

      setState(() {
        _avatarUrl = imageUrl;
      });
      
      EasyLoading.showSuccess('Foto diperbarui!');
    } catch (e) {
      EasyLoading.showError('Gagal upload: $e');
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.isEmpty) {
      EasyLoading.showError("Nama tidak boleh kosong");
      return;
    }

    EasyLoading.show(status: 'Menyimpan...');
    try {
      // 1. Update User Metadata (Auth)
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'name': _nameController.text}),
      );

      // 2. Update Nama di tabel anggota_kelas (Agar data sinkron di kelas lain)
      await Supabase.instance.client
          .from('anggota_kelas')
          .update({'user_name': _nameController.text})
          .eq('user_email', _currentUser!.email!);

      EasyLoading.showSuccess('Profil disimpan!');
      if(mounted) Navigator.pop(context, true); // Return true to refresh prev page
    } catch (e) {
      EasyLoading.showError('Gagal menyimpan: $e');
    } finally {
      EasyLoading.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Edit Profil", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar Section
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _avatarUrl != null 
                        ? NetworkImage(_avatarUrl!) 
                        : null,
                    child: _avatarUrl == null 
                        ? const Icon(Icons.person, size: 60, color: Colors.grey) 
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickAndUploadImage,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                      ),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Form Fields
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nama Lengkap',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nimController,
              readOnly: true, // Kunci NIM
              style: TextStyle(color: Colors.grey[600]),
              decoration: InputDecoration(
                labelText: 'NIM (Tidak dapat diubah)',
                prefixIcon: const Icon(Icons.badge_outlined),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Simpan Perubahan", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}