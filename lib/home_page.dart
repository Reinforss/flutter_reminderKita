import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _currentUser = Supabase.instance.client.auth.currentUser;
  List myClasses = [];
  bool _isLoading = true;

  // Define Theme Colors
  final Color _primaryColor = const Color(0xFF2563EB);
  final Color _bgColor = const Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    if (_currentUser != null) {
      _fetchMyClasses();
    }
  }

  Future<void> _fetchMyClasses() async {
    try {
      final response = await Supabase.instance.client
          .from('anggota_kelas')
          .select('role, kelas(*)')
          .eq('user_email', _currentUser!.email!)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          myClasses = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching classes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

Future<void> _joinClass(String code) async {
    if (code.isEmpty) return;
    Navigator.pop(context); 
    EasyLoading.show(status: 'Mencari kelas...');
    
    try {
      final response = await Supabase.instance.client
          .from('kelas')
          .select()
          .or('kode_kelas.eq.$code,kode_wakil.eq.$code')
          .maybeSingle();

      if (response != null) {
        if (response['is_open'] == false) {
           EasyLoading.showError('Kelas ini sudah ditutup untuk anggota baru.');
           return;
        }

        final existingMember = await Supabase.instance.client
            .from('anggota_kelas')
            .select()
            .eq('kelas_id', response['id'])
            .eq('user_email', _currentUser!.email!)
            .maybeSingle();

        if (existingMember != null) {
          EasyLoading.showInfo('Kamu sudah ada di kelas ini!');
          return;
        }

        String role = 'student';
        if (code == response['kode_wakil']) {
          role = 'vice_admin';
        }

        final metadata = _currentUser.userMetadata;
        await Supabase.instance.client.from('anggota_kelas').insert({
          'user_email': _currentUser.email,
          'kelas_id': response['id'],
          'role': role,
          'user_name': metadata?['name'] ?? 'Mahasiswa',
          'nim': metadata?['nim'] ?? '-',
        });

        EasyLoading.showSuccess(role == 'vice_admin' ? 'Masuk sebagai Wakil!' : 'Berhasil masuk kelas!');
        _fetchMyClasses();
      } else {
        EasyLoading.showError('Kode kelas tidak ditemukan');
      }
    } catch (e) {
      EasyLoading.showError('Gagal bergabung: $e');
    } finally {
      EasyLoading.dismiss();
    }
  }

  void _showJoinSheet() {
    final codeController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          top: 24, left: 24, right: 24
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            Text('Gabung Kelas Baru', 
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.grey[900])
            ),
            const SizedBox(height: 8),
            Text("Masukkan kode unik yang diberikan ketua kelas", style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 24),
            TextField(
              controller: codeController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
              decoration: InputDecoration(
                hintText: 'KODE KELAS',
                filled: true,
                fillColor: Colors.grey[100],
                prefixIcon: const Icon(Icons.vpn_key_rounded, color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _primaryColor, width: 2)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => _joinClass(codeController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Gabung Sekarang', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final userName = _currentUser?.userMetadata?['name']?.split(' ')[0] ?? 'User';
    final userEmail = _currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: _bgColor,
      body: RefreshIndicator(
        onRefresh: _fetchMyClasses,
        color: _primaryColor,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildAppBar(userName, userEmail),
            if (_isLoading)
               const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (myClasses.isEmpty)
              _buildEmptyState()
            else
              _buildClassList(),
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)), 
          ],
        ),
      ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (context) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // BUAT KELAS
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.withOpacity(0.1),
                        child: const Icon(Icons.school_rounded, color: Colors.green),
                      ),
                      title: const Text(
                        'Buat Kelas',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text('Buat kelas baru sebagai ketua'),
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.pushNamed(context, '/create-class');
                        _fetchMyClasses(); // refresh
                      },
                    ),

                    const SizedBox(height: 8),

                    // GABUNG KELAS
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _primaryColor.withOpacity(0.1),
                        child: Icon(Icons.vpn_key_rounded, color: _primaryColor),
                      ),
                      title: const Text(
                        'Gabung Kelas',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text('Masuk dengan kode kelas'),
                      onTap: () {
                        Navigator.pop(context);
                        _showJoinSheet();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
          backgroundColor: _primaryColor,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text(
            "Tambah",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),

    );
  }

  String _getGreeting() {
    var hour = DateTime.now().hour;
    if (hour >= 4 && hour < 11) {
      return 'Selamat Pagi,';
    } else if (hour >= 11 && hour < 15) {
      return 'Selamat Siang,';
    } else if (hour >= 15 && hour < 19) {
      return 'Selamat Sore,';
    } else {
      return 'Selamat Malam,';
    }
  }

  Widget _buildAppBar(String name, String email) {
    final avatarUrl = Supabase.instance.client.auth.currentUser?.userMetadata?['avatar_url'];
    final displayName = Supabase.instance.client.auth.currentUser?.userMetadata?['name'] ?? name;

    return SliverAppBar(
      expandedHeight: 140.0,
      floating: false,
      pinned: true,
      backgroundColor: _bgColor,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        titlePadding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
        centerTitle: false,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getGreeting(), 
                    style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500)
                  ),
                  const SizedBox(height: 2),
                  Text(displayName,
                    style: TextStyle(color: Colors.grey[900], fontWeight: FontWeight.w800, fontSize: 20)
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () async {
                await Navigator.pushNamed(context, '/profile');
                setState(() {}); 
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                          style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold))
                      : null,
                ),
              ),
            )
            // ------------------------------
          ],
        ),
        background: Container(color: _bgColor),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.grey),
          onPressed: _handleLogout,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))
                ]
              ),
              child: Icon(Icons.school_rounded, size: 60, color: Colors.blue[300]),
            ),
            const SizedBox(height: 32),
            const Text("Belum ada kelas", 
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 12),
            Text(
              "Mulai perjalanan akademismu dengan bergabung ke kelas pertamamu.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], height: 1.5),
            ),
            const SizedBox(height: 32),
             OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/create-class').then((_) => _fetchMyClasses()),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text("Buat Kelas"),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: BorderSide(color: _primaryColor.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildClassList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = myClasses[index];
            return _ClassCard(item: item, primaryColor: _primaryColor);
          },
          childCount: myClasses.length,
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final Map item;
  final Color primaryColor;

  const _ClassCard({required this.item, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final kelas = item['kelas'];
    final role = item['role'];
    final bool isAdmin = role == 'admin' || role == 'Ketua Kelas' || role == 'Wakil Ketua Kelas';
    final String className = kelas['nama_kelas'] ?? 'Tanpa Nama';
    final String firstChar = className.isNotEmpty ? className[0].toUpperCase() : 'C';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.pushNamed(context, '/class-board', arguments: {
              'id': kelas['id'],
              'nama': kelas['nama_kelas'],
              'role': role,
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon Box
                Container(
                  width: 65, height: 65,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isAdmin
                          ? [const Color(0xFFFF9800), const Color(0xFFF57C00)]
                          : [const Color(0xFF60A5FA), primaryColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      firstChar,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Text Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(className,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _buildTag(
                            label: isAdmin ? "Ketua Kelas" : "Mahasiswa", 
                            color: isAdmin ? Colors.orange : Colors.blue
                          ),
                          if (isAdmin) ...[
                            const SizedBox(width: 6),
                            const SizedBox(width: 6)
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey[300]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color.withOpacity(0.9), fontWeight: FontWeight.w700),
      ),
    );
  }
}