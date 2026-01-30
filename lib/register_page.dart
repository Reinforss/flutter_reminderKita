import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  // Controller
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _nimController = TextEditingController(); // Input NIM Baru
  final _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text("Daftar Akun")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Buat Akun Mahasiswa", 
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
                    ),
                    const SizedBox(height: 20),

                    // Input Nama
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Nama Lengkap', prefixIcon: Icon(Icons.person)),
                      validator: (v) => v!.isEmpty ? 'Nama wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),

                    // Input NIM
                    TextFormField(
                      controller: _nimController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'NIM', prefixIcon: Icon(Icons.badge)),
                      validator: (v) => v!.isEmpty ? 'NIM wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),

                    // Input Email
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                      validator: (v) => v!.isEmpty ? 'Email wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),

                    // Input Password
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                      validator: (v) => v!.isEmpty ? 'Password wajib diisi' : null,
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            EasyLoading.show(status: 'Mendaftar...');
                            try {
                              // Simpan Nama dan NIM ke User Metadata Supabase
                              await Supabase.instance.client.auth.signUp(
                                email: _emailController.text,
                                password: _passwordController.text,
                                data: {
                                  'name': _nameController.text,
                                  'nim': _nimController.text,
                                },
                              );
                              EasyLoading.showSuccess("Registrasi Berhasil!");
                              if (mounted) Navigator.pop(context);
                            } catch (e) {
                              EasyLoading.showError('Gagal: ${e.toString()}');
                            } finally {
                              EasyLoading.dismiss();
                            }
                          }
                        },
                        child: const Text("Daftar Sekarang", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}