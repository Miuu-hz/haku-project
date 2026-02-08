import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';

/// 🪪 Profile Editor Widget - แก้ไข Identity Card
///
/// ผู้ใช้สามารถดูและแก้ไขข้อมูลที่ AI จำได้
/// AI ก็สามารถอัปเดตข้อมูลนี้ได้เช่นกัน

class ProfileEditorWidget extends StatefulWidget {
  const ProfileEditorWidget({super.key});

  @override
  State<ProfileEditorWidget> createState() => _ProfileEditorWidgetState();
}

class _ProfileEditorWidgetState extends State<ProfileEditorWidget> {
  final _formKey = GlobalKey<FormState>();
  final _userProfileService = UserProfileService();

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _nicknameController;
  late TextEditingController _roleController;
  late TextEditingController _likesController;
  late TextEditingController _dislikesController;
  late TextEditingController _goalsController;

  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadProfile();
  }

  void _initControllers() {
    _nameController = TextEditingController();
    _nicknameController = TextEditingController();
    _roleController = TextEditingController();
    _likesController = TextEditingController();
    _dislikesController = TextEditingController();
    _goalsController = TextEditingController();

    // Listen for changes
    for (final controller in [
      _nameController,
      _nicknameController,
      _roleController,
      _likesController,
      _dislikesController,
      _goalsController,
    ]) {
      controller.addListener(() => setState(() => _hasChanges = true));
    }
  }

  Future<void> _loadProfile() async {
    await _userProfileService.initialize();

    final profile = _userProfileService.profile;

    setState(() {
      _nameController.text = profile.name;
      _nicknameController.text = profile.nickname;
      _roleController.text = profile.role;
      _likesController.text = profile.likes.join(', ');
      _dislikesController.text = profile.dislikes.join(', ');
      _goalsController.text = profile.goals.join('\n');
      _isLoading = false;
      _hasChanges = false;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Parse lists from comma-separated strings
      final likes = _likesController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final dislikes = _dislikesController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final goals = _goalsController.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      // Update profile
      final newProfile = _userProfileService.profile.copyWith(
        name: _nameController.text.trim(),
        nickname: _nicknameController.text.trim(),
        role: _roleController.text.trim(),
        likes: likes,
        dislikes: dislikes,
        goals: goals,
      );

      await _userProfileService.updateProfile(newProfile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ บันทึกโปรไฟล์เรียบร้อย'),
            backgroundColor: Colors.green,
          ),
        );
      }

      setState(() {
        _hasChanges = false;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          '🗑️ ล้างโปรไฟล์?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'AI จะลืมข้อมูลทั้งหมดเกี่ยวกับคุณ\nคุณแน่ใจหรือไม่?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ล้างข้อมูล'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _userProfileService.clearProfile();
      await _loadProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ ล้างโปรไฟล์เรียบร้อย'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _roleController.dispose();
    _likesController.dispose();
    _dislikesController.dispose();
    _goalsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('🪪 โปรไฟล์ของฉัน'),
        actions: [
          if (_hasChanges)
            TextButton.icon(
              onPressed: _isLoading ? null : _saveProfile,
              icon: const Icon(Icons.save, color: Colors.green),
              label: const Text('บันทึก', style: TextStyle(color: Colors.green)),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _clearProfile,
            tooltip: 'ล้างโปรไฟล์',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info Banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B7CB6).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF9B7CB6).withOpacity(0.5),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.auto_awesome, color: Color(0xFF9B7CB6)),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'AI จะเรียนรู้และอัปเดตข้อมูลนี้อัตโนมัติ\n'
                              'คุณสามารถแก้ไขได้ถ้า AI จำผิด',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Basic Info Section
                    _buildSectionHeader('👤 ข้อมูลพื้นฐาน'),
                    const SizedBox(height: 12),

                    _buildTextField(
                      controller: _nameController,
                      label: 'ชื่อ',
                      hint: 'ชื่อที่อยากให้ AI เรียก',
                      icon: Icons.person,
                    ),

                    _buildTextField(
                      controller: _nicknameController,
                      label: 'ชื่อเล่น',
                      hint: 'ชื่อเล่น (ถ้ามี)',
                      icon: Icons.face,
                    ),

                    _buildTextField(
                      controller: _roleController,
                      label: 'อาชีพ / บทบาท',
                      hint: 'เช่น Developer, นักศึกษา, แม่บ้าน',
                      icon: Icons.work,
                    ),

                    const SizedBox(height: 24),

                    // Preferences Section
                    _buildSectionHeader('💜 ความชอบ'),
                    const SizedBox(height: 12),

                    _buildTextField(
                      controller: _likesController,
                      label: 'สิ่งที่ชอบ',
                      hint: 'คั่นด้วยเครื่องหมาย , เช่น กาแฟ, เกม, อ่านหนังสือ',
                      icon: Icons.favorite,
                      maxLines: 2,
                    ),

                    _buildTextField(
                      controller: _dislikesController,
                      label: 'สิ่งที่ไม่ชอบ',
                      hint: 'คั่นด้วยเครื่องหมาย , เช่น อาหารเผ็ด, ตื่นเช้า',
                      icon: Icons.heart_broken,
                      maxLines: 2,
                    ),

                    const SizedBox(height: 24),

                    // Goals Section
                    _buildSectionHeader('🎯 เป้าหมาย'),
                    const SizedBox(height: 12),

                    _buildTextField(
                      controller: _goalsController,
                      label: 'เป้าหมายของฉัน',
                      hint: 'หนึ่งเป้าหมายต่อบรรทัด\nเช่น:\nออกกำลังกายสัปดาห์ละ 3 วัน\nอ่านหนังสือเดือนละ 2 เล่ม',
                      icon: Icons.flag,
                      maxLines: 5,
                    ),

                    const SizedBox(height: 24),

                    // Preview Section
                    _buildSectionHeader('👁️ ตัวอย่างที่ AI เห็น'),
                    const SizedBox(height: 12),
                    _buildPreview(),

                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _hasChanges && !_isLoading ? _saveProfile : null,
                        icon: const Icon(Icons.save),
                        label: const Text('บันทึกโปรไฟล์'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF9B7CB6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: Icon(icon, color: const Color(0xFF9B7CB6)),
          filled: true,
          fillColor: const Color(0xFF1A1A2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF9B7CB6), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    // Build lean format preview
    final parts = <String>[];

    if (_nameController.text.isNotEmpty) {
      parts.add('Name:${_nameController.text.trim()}');
    }
    if (_nicknameController.text.isNotEmpty) {
      parts.add('Nick:${_nicknameController.text.trim()}');
    }
    if (_roleController.text.isNotEmpty) {
      parts.add('Job:${_roleController.text.trim()}');
    }

    final likes = _likesController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
    if (likes.isNotEmpty) {
      parts.add('Like:${likes.join(",")}');
    }

    final dislikes = _dislikesController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
    if (dislikes.isNotEmpty) {
      parts.add('Dislike:${dislikes.join(",")}');
    }

    final preview = parts.isEmpty ? '(ยังไม่มีข้อมูล)' : '[${parts.join("|")}]';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lean Format (ประหยัด Token):',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            preview,
            style: const TextStyle(
              color: Color(0xFF9B7CB6),
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '~${preview.length} characters ≈ ${(preview.length * 0.4).round()} tokens',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
