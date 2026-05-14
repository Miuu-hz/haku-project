import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import '../services/database_helper.dart';
import '../services/location_service.dart';
import '../utils/haku_design_tokens.dart';

class NewEntryScreen extends ConsumerStatefulWidget {
  final Entry? existingEntry;

  const NewEntryScreen({super.key, this.existingEntry});

  @override
  ConsumerState<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends ConsumerState<NewEntryScreen> {
  final TextEditingController _contentController = TextEditingController();
  int? _selectedMood;
  bool _isLoadingLocation = false;
  bool _includeLocation = true;
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

  Future<void> _fetchLocation() async {
    setState(() => _isLoadingLocation = true);
    final position = await LocationService.getCurrentPosition();
    if (position != null && mounted) {
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
      if (mounted) Navigator.pop(context, true);
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

    return HakuAuroraBackground(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _buildAppBar(),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateFormat.format(DateTime.now()),
                        style: const TextStyle(fontSize: 14, color: kFg3),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _contentController,
                        maxLines: null,
                        minLines: 10,
                        autofocus: true,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.8,
                          color: kFg1,
                        ),
                        decoration: InputDecoration(
                          hintText: 'วันนี้เป็นยังไงบ้าง?\n\nเล่าให้ Haku ฟังหน่อย...',
                          hintStyle: TextStyle(
                            color: kFg1.withAlpha(60),
                            height: 1.8,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildMoodSelector(),
                    ],
                  ),
                ),
              ),
              _buildBottomToolbar(),
            ],
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() => PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AppBar(
              backgroundColor: kGlassFill,
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              iconTheme: const IconThemeData(color: kFg1),
              leading: IconButton(
                icon: const Icon(Icons.close, color: kFg1),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                _isEditing ? 'แก้ไขบันทึก' : 'บันทึกใหม่',
                style: const TextStyle(
                    color: kFg1, fontWeight: FontWeight.w600),
              ),
              actions: [
                TextButton(
                  onPressed: _isSaving ? null : _saveEntry,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kCrystal400),
                        )
                      : const Text(
                          'บันทึก',
                          style: TextStyle(
                            color: kCrystal600,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );

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
        const Text(
          'วันนี้รู้สึกยังไง?',
          style: TextStyle(fontSize: 14, color: kFg3),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: moods.map((mood) {
            final value = mood['value'] as int;
            final isSelected = _selectedMood == value;

            return GestureDetector(
              onTap: () =>
                  setState(() => _selectedMood = isSelected ? null : value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? kCrystal400.withAlpha(40)
                      : Colors.white.withAlpha(60),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? kCrystal400 : kGlassStroke,
                    width: isSelected ? 1.5 : 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      mood['emoji'] as String,
                      style: const TextStyle(fontSize: 26),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mood['label'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected ? kCrystal600 : kFg3,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
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

  Widget _buildBottomToolbar() => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: kGlassFill,
              border: Border(
                top: BorderSide(color: kFg1.withAlpha(12)),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Location toggle
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: _isLoadingLocation
                            ? const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kLavender500,
                              )
                            : Checkbox(
                                value: _includeLocation,
                                onChanged: (v) => setState(
                                    () => _includeLocation = v ?? true),
                                activeColor: kCrystal400,
                                checkColor: kFgOnCyan,
                              ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: _includeLocation ? kLavender500 : kFg4,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _locationName ?? 'ไม่มีตำแหน่ง',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: _includeLocation ? kFg2 : kFg4,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  IconButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('ฟีเจอร์อัดเสียงจะมาใน Phase 2')),
                    ),
                    icon: const Icon(Icons.mic_outlined, color: kFg4),
                  ),
                  IconButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('ฟีเจอร์แนบรูปจะมาใน Phase 2')),
                    ),
                    icon: const Icon(Icons.image_outlined, color: kFg4),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
