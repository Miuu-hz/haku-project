import 'package:flutter/material.dart';

import '../services/workers/calendar_worker.dart';

/// 📅 Card ยืนยันการสร้าง Event (Auto-scheduling)
/// 
/// แสดงเมื่อ AI ตรวจจับว่า user พูดถึงกิจกรรม/นัดหมาย

class EventConfirmationCard extends StatelessWidget {
  final CalendarEvent event;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const EventConfirmationCard({
    super.key,
    required this.event,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFF9B7CB6).withAlpha(100)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9B7CB6).withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.event, color: Color(0xFF9B7CB6)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'เพิ่มลงปฏิทิน?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Haku ตรวจพบกิจกรรม',
                        style: TextStyle(
                          color: Colors.white.withAlpha(150),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Event Details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.white.withAlpha(150)),
                      const SizedBox(width: 8),
                      Text(
                        event.displayTime,
                        style: TextStyle(color: Colors.white.withAlpha(200)),
                      ),
                    ],
                  ),
                  if (event.location != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.white.withAlpha(150)),
                        const SizedBox(width: 8),
                        Text(
                          event.location!,
                          style: TextStyle(color: Colors.white.withAlpha(200)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.timer, size: 16, color: Colors.white.withAlpha(150)),
                      const SizedBox(width: 8),
                      Text(
                        '${event.durationMinutes} นาที',
                        style: TextStyle(color: Colors.white.withAlpha(200)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withAlpha(150),
                      side: BorderSide(color: Colors.white.withAlpha(30)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('ยกเลิก'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF9B7CB6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('เพิ่มลงปฏิทิน'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
}
