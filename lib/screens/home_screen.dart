import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import '../services/database_helper.dart';
import '../widgets/quick_actions_fab.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'view_entry_screen.dart';

/// 🏠 หน้า Home - แสดงรายการบันทึกล่าสุด
/// 
/// แสดง entries ในรูปแบบ Card List
/// รองรับการ pull-to-refresh และ infinite scroll

// Provider สำหรับดึงข้อมูล entries
final entriesProvider = FutureProvider<List<Entry>>((ref) => DatabaseHelper.instance.getAllEntries(limit: 50));

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 🔄 รีเฟรชข้อมูล
  Future<void> _refreshData() async {
    ref.invalidate(entriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(entriesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      
      // 🎨 App Bar ที่มีช่องค้นหา
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'ค้นหาบันทึก...',
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
                onSubmitted: (value) {
                  // TODO: ค้นหา
                },
              )
            : const Text('Haku (箱)'),
        actions: [
          // 🤖 ปุ่มแชท (ใหม่)
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'คุยกับ Haku AI',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<bool>(builder: (context) => const ChatScreen()),
              );
            },
          ),
          
          // 🔍 ปุ่มค้นหา
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                }
              });
            },
          ),
          // ⚙️ ปุ่มตั้งค่า
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<bool>(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),

      // 📋 รายการ entries
      body: entriesAsync.when(
        data: (entries) {
          if (entries.isEmpty) {
            return _buildEmptyState();
          }
          return RefreshIndicator(
            onRefresh: _refreshData,
            color: const Color(0xFF9B7CB6),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) => _EntryCard(
                  entry: entries[index],
                  onTap: () => _openEntry(entries[index]),
                  onDelete: () => _deleteEntry(entries[index]),
                ),
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF9B7CB6)),
        ),
        error: (error, stack) => Center(
          child: Text('เกิดข้อผิดพลาด: $error'),
        ),
      ),

      // ➕ Floating Action Button แบบ Expandable
      floatingActionButton: const ExpandableFab(),
    );
  }

  /// 📭 แสดงเมื่อไม่มีข้อมูล
  Widget _buildEmptyState() => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 80,
            color: Colors.white.withAlpha(50),
          ),
          const SizedBox(height: 16),
          Text(
            'ยังไม่มีบันทึก',
            style: TextStyle(
              fontSize: 20,
              color: Colors.white.withAlpha(100),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'กดปุ่ม "เขียน" เพื่อเริ่มบันทึกชีวิตของคุณ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withAlpha(70),
            ),
          ),
        ],
      ),
    );

  /// 📖 เปิดดู Entry
  Future<void> _openEntry(Entry entry) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (context) => ViewEntryScreen(entry: entry),
      ),
    );

    if (result == true) {
      _refreshData();
    }
  }

  /// 🗑️ ลบ Entry
  Future<void> _deleteEntry(Entry entry) async {
    if (entry.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบบันทึก?'),
        content: const Text('การลบนี้ไม่สามารถกู้คืนได้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteEntry(entry.id!);
      _refreshData();
    }
  }
}

/// 🎴 Widget แสดง Entry แต่ละรายการในรูปแบบ Card
class _EntryCard extends StatelessWidget {
  final Entry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _EntryCard({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy · HH:mm', 'th');
    final moodInfo = Entry.getMoodInfo(entry.mood);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1E1E2E),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🗓️ แถวบนสุด: วันที่ + อารมณ์ + ไอคอน media
              Row(
                children: [
                  // วันที่
                  Text(
                    dateFormat.format(entry.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withAlpha(100),
                    ),
                  ),
                  const Spacer(),
                  // ไอคอน media ถ้ามี
                  if (entry.mediaType != MediaType.none)
                    Icon(
                      entry.mediaType == MediaType.image
                          ? Icons.image_outlined
                          : Icons.mic_outlined,
                      size: 16,
                      color: Colors.white.withAlpha(100),
                    ),
                  const SizedBox(width: 8),
                  // อารมณ์
                  Text(
                    moodInfo['emoji'] as String,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // 📝 เนื้อหา (ตัดให้สั้นลง)
              Text(
                entry.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.white,
                ),
              ),
              
              // 📍 ตำแหน่ง (ถ้ามี)
              if (entry.locationName != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: Colors.white.withAlpha(70),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entry.locationName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withAlpha(70),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              
              // 🏷️ แท็ก (ถ้ามี)
              if (entry.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: entry.tags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B7CB6).withAlpha(50),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '#$tag',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9B7CB6),
                        ),
                      ),
                    )).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
