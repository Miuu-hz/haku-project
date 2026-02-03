import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import '../services/database_helper.dart';
import '../services/location_service.dart';

/// ➕ หน้าสร้าง Entry ใหม่
/// 
/// รองรับ:
/// - เขียนข้อความ
/// - เลือกอารมณ์ (mood)
/// - บันทึกตำแหน่ง (auto)
/// - อัดเสียง (เตรียมไว้ Phase 2)
/// - แนบรูป (เตรียมไว้ Phase 2)

class NewEntryScreen extends ConsumerStatefulWidget {
  final Entry? existingEntry;

  const NewEntryScreen({super.key, this.existingEntry});

  @override
  ConsumerState<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends ConsumerState<NewEntryScreen> {
  final TextEditingController _contentController = TextEditingController();
  int? _selectedMood;  // 1-5 (null = ไม่ได้เลือก)
  bool _isLoadingLocation = false;
  bool _includeLocation = true;  // บันทึกตำแหน่งโดยค่าเริ่มต้น
  double? _latitude;
  double? _longitude;
  String? _locationName;
  bool _isSaving = false;

  bool get _isEditing => widget.existingEntry != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final e = widget.existingEntry!;
      _contentController.text = e.content;
      _selectedMood = e.mood;
      _latitude = e.latitude;
      _longitude = e.longitude;
      _locationName = e.locationName;
      _includeLocation = e.latitude != null;
    }
    _fetchLocation();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  /// 📍 ดึงตำแหน่งปัจจุบัน
  Future<void> _fetchLocation() async {
    setState(() => _isLoadingLocation = true);
    
    final position = await LocationService.getCurrentPosition();
    
    if (position != null && mounted) {
      // แปลงพิกัดเป็นชื่อสถานที่
      final placeName = await LocationService.getLocationName(
        position.latitude,
        position.longitude,
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationName = placeName ?? 'ตำแหน่งปัจจุบัน';
        _isLoadingLocation = false;
      });
    } else {
      setState(() => _isLoadingLocation = false);
    }
  }

  /// 💾 บันทึก Entry
  Future<void> _saveEntry() async {
    final content = _contentController.text.trim();
    
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเขียนอะไรสักหน่อย')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final entry = Entry(
        id: _isEditing ? widget.existingEntry!.id : null,
        content: content,
        createdAt: _isEditing ? widget.existingEntry!.createdAt : DateTime.now(),
        latitude: _includeLocation ? _latitude : null,
        longitude: _includeLocation ? _longitude : null,
        locationName: _includeLocation ? _locationName : null,
        mood: _selectedMood,
        tags: Entry.extractTags(content),
      );

      if (_isEditing) {
        await DatabaseHelper.instance.updateEntry(entry);
      } else {
        await DatabaseHelper.instance.createEntry(entry);
      }

      if (mounted) {
        Navigator.pop(context, true);  // กลับไปหน้า home พร้อมบอกว่าสำเร็จ
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, d MMMM yyyy · HH:mm', 'th_TH');

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(_isEditing ? 'แก้ไขบันทึก' : 'บันทึกใหม่'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 💾 ปุ่มบันทึก
          TextButton(
            onPressed: _isSaving ? null : _saveEntry,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'บันทึก',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🗓️ แสดงวันที่ปัจจุบัน
                  Text(
                    dateFormat.format(DateTime.now()),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withAlpha(100),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 📝 ช่องเขียนข้อความ
                  TextField(
                    controller: _contentController,
                    maxLines: null,
                    minLines: 10,
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.8,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'วันนี้เป็นยังไงบ้าง?\n\nเล่าให้ Haku ฟังหน่อย...',
                      hintStyle: TextStyle(
                        color: Colors.white.withAlpha(50),
                        height: 1.8,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 😊 เลือกอารมณ์
                  _buildMoodSelector(),
                ],
              ),
            ),
          ),
          
          // 📍 แถบเครื่องมือด้านล่าง
          _buildBottomToolbar(),
        ],
      ),
    );
  }

  /// 😊 ส่วนเลือกอารมณ์ (Mood Selector)
  Widget _buildMoodSelector() {
    final moods = [
      {'emoji': '😢', 'label': 'แย่มาก', 'value': 1},
      {'emoji': '😕', 'label': 'แย่', 'value': 2},
      {'emoji': '😐', 'label': 'เฉยๆ', 'value': 3},
      {'emoji': '🙂', 'label': 'ดี', 'value': 4},
      {'emoji': '😄', 'label': 'ดีมาก', 'value': 5},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'วันนี้รู้สึกยังไง?',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withAlpha(100),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: moods.map((mood) {
            final value = mood['value'] as int;
            final isSelected = _selectedMood == value;
            
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedMood = isSelected ? null : value;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF9B7CB6).withAlpha(100)
                      : Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: const Color(0xFF9B7CB6))
                      : null,
                ),
                child: Column(
                  children: [
                    Text(
                      mood['emoji'] as String,
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mood['label'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withAlpha(70),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 📍 แถบเครื่องมือด้านล่าง
  Widget _buildBottomToolbar() => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(20)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 📍 สลับบันทึกตำแหน่ง
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: _isLoadingLocation
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF9B7CB6),
                        )
                      : Checkbox(
                          value: _includeLocation,
                          onChanged: (v) {
                            setState(() => _includeLocation = v ?? true);
                          },
                          activeColor: const Color(0xFF9B7CB6),
                        ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: _includeLocation
                      ? const Color(0xFF9B7CB6)
                      : Colors.white.withAlpha(100),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _locationName ?? 'ไม่มีตำแหน่ง',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: _includeLocation
                          ? Colors.white.withAlpha(200)
                          : Colors.white.withAlpha(70),
                    ),
                  ),
                ),
              ],
            ),
            
            const Spacer(),
            
            // 🎙️ ปุ่มอัดเสียง (เตรียมไว้ Phase 2)
            IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ฟีเจอร์อัดเสียงจะมาใน Phase 2')),
                );
              },
              icon: Icon(
                Icons.mic_outlined,
                color: Colors.white.withAlpha(100),
              ),
            ),
            
            // 🖼️ ปุ่มแนบรูป (เตรียมไว้ Phase 2)
            IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ฟีเจอร์แนบรูปจะมาใน Phase 2')),
                );
              },
              icon: Icon(
                Icons.image_outlined,
                color: Colors.white.withAlpha(100),
              ),
            ),
          ],
        ),
      ),
    );
}
