import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/preset.dart';
import '../services/preset_service.dart';
import '../utils/haku_design_tokens.dart';

/// 🎭 Presets Screen - จัดการ Presets และ Objectives
///
/// แบ่งเป็น 2 tabs:
/// 1. Presets - ตั้งค่าโหมดต่างๆ
/// 2. Locations - บันทึกสถานที่สำคัญ (home, office)

class PresetsScreen extends StatefulWidget {
  const PresetsScreen({super.key});

  @override
  State<PresetsScreen> createState() => _PresetsScreenState();
}

class _PresetsScreenState extends State<PresetsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeService();
  }

  Future<void> _initializeService() async {
    await PresetService().initialize();
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HakuAuroraBackground(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _buildAppBar(),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: kCrystal400))
              : TabBarView(
                  controller: _tabController,
                  children: const [
                    _PresetsTab(),
                    _LocationsTab(),
                  ],
                ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + 48),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AppBar(
            backgroundColor: kGlassFill,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            iconTheme: const IconThemeData(color: kFg1),
            title: const Text(
              'Presets & Locations',
              style: TextStyle(color: kFg1, fontWeight: FontWeight.w600),
            ),
            bottom: TabBar(
              controller: _tabController,
              labelColor: kCrystal400,
              unselectedLabelColor: kFg3,
              indicatorColor: kCrystal400,
              indicatorWeight: 2,
              tabs: const [
                Tab(icon: Icon(Icons.tune), text: 'Presets'),
                Tab(icon: Icon(Icons.location_on), text: 'Locations'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Presets Tab
// ============================================================================

class _PresetsTab extends StatefulWidget {
  const _PresetsTab();

  @override
  State<_PresetsTab> createState() => _PresetsTabState();
}

class _PresetsTabState extends State<_PresetsTab> {
  @override
  Widget build(BuildContext context) {
    final presets = PresetService().presets;
    final currentPreset = PresetService().currentPreset;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (currentPreset != null) ...[
          _CurrentPresetCard(preset: currentPreset),
          const SizedBox(height: 24),
        ],

        const Text(
          'All Presets',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: kFg1,
          ),
        ),
        const SizedBox(height: 12),

        ...presets.map((preset) => _PresetCard(
              preset: preset,
              isActive: preset.id == currentPreset?.id,
              onTap: () => _showPresetDetails(preset),
              onToggle: (enabled) => _togglePreset(preset, enabled),
            )),

        const SizedBox(height: 16),

        OutlinedButton.icon(
          onPressed: _showAddPresetDialog,
          style: OutlinedButton.styleFrom(
            foregroundColor: kCrystal400,
            side: const BorderSide(color: kCrystal400),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kR3),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add Custom Preset'),
        ),
      ],
    );
  }

  void _showPresetDetails(Preset preset) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PresetDetailsSheet(
        preset: preset,
        parentContext: context,
        onRefresh: () => setState(() {}),
      ),
    );
  }

  Future<void> _togglePreset(Preset preset, bool enabled) async {
    await PresetService().updatePreset(preset.copyWith(isEnabled: enabled));
    setState(() {});
  }

  void _showAddPresetDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PresetFormSheet(
        onSave: (preset) async {
          await PresetService().addPreset(preset);
          if (mounted) setState(() {});
        },
      ),
    );
  }
}

/// Current Preset Card
class _CurrentPresetCard extends StatelessWidget {
  final Preset preset;

  const _CurrentPresetCard({required this.preset});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kR4),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kCrystal400.withAlpha(15),
            borderRadius: BorderRadius.circular(kR4),
            border: Border.all(color: kCrystal400.withAlpha(60)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(preset.icon, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Mode',
                          style: TextStyle(fontSize: 12, color: kFg3),
                        ),
                        Text(
                          preset.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: kFg1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kVividMint.withAlpha(25),
                      borderRadius: BorderRadius.circular(kRPill),
                      border: Border.all(color: kVividMint.withAlpha(80)),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        color: kVividMint,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                preset.behavior.greeting,
                style: const TextStyle(color: kFg2, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: preset.behavior.focusAreas
                    .map((area) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: kCrystal400.withAlpha(20),
                            borderRadius: BorderRadius.circular(kRPill),
                            border: Border.all(
                                color: kCrystal400.withAlpha(60)),
                          ),
                          child: Text(
                            area,
                            style: const TextStyle(
                                fontSize: 12, color: kCrystal600),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preset Card
class _PresetCard extends StatelessWidget {
  final Preset preset;
  final bool isActive;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  const _PresetCard({
    required this.preset,
    required this.isActive,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kR3),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: kGlassFill,
              borderRadius: BorderRadius.circular(kR3),
              border: Border.all(
                color: isActive
                    ? kCrystal400.withAlpha(80)
                    : kGlassStroke,
              ),
            ),
            child: ListTile(
              leading: Text(
                preset.icon,
                style: const TextStyle(fontSize: 28),
              ),
              title: Text(
                preset.name,
                style: const TextStyle(color: kFg1, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                preset.description,
                style: const TextStyle(color: kFg3, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isActive)
                    const Icon(Icons.check_circle, color: kVividMint, size: 20),
                  const SizedBox(width: 8),
                  Switch(
                    value: preset.isEnabled,
                    onChanged: onToggle,
                    activeThumbColor: kCrystal400,
                  ),
                ],
              ),
              onTap: onTap,
            ),
          ),
        ),
      ),
    );
  }
}

/// Preset Details Sheet
class _PresetDetailsSheet extends StatelessWidget {
  final Preset preset;
  final BuildContext? parentContext;
  final VoidCallback? onRefresh;

  const _PresetDetailsSheet({
    required this.preset,
    this.parentContext,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: const BoxDecoration(
              color: kFieldTop,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kFg4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Text(preset.icon, style: const TextStyle(fontSize: 48)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: kFg1,
                            ),
                          ),
                          Text(
                            preset.description,
                            style: const TextStyle(color: kFg3, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                Divider(height: 32, color: kFg1.withAlpha(20)),

                const _SectionTitle(
                  icon: Icons.timer,
                  title: 'Trigger Conditions',
                ),
                _TriggerInfo(trigger: preset.trigger),

                Divider(height: 32, color: kFg1.withAlpha(20)),

                const _SectionTitle(
                  icon: Icons.psychology,
                  title: 'AI Behavior',
                ),
                const SizedBox(height: 8),
                const Text('Greeting:', style: TextStyle(fontSize: 12, color: kFg3)),
                Text(preset.behavior.greeting,
                    style: const TextStyle(color: kFg1, fontSize: 14)),
                const SizedBox(height: 8),
                const Text('Personality:', style: TextStyle(fontSize: 12, color: kFg3)),
                Text(preset.behavior.personality,
                    style: const TextStyle(color: kFg1, fontSize: 14)),

                const SizedBox(height: 16),

                const Text(
                  'Suggested Questions:',
                  style: TextStyle(fontSize: 12, color: kFg3),
                ),
                const SizedBox(height: 4),
                ...preset.behavior.suggestedQuestions.map(
                  (q) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 16, color: kFg4),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(q,
                              style: const TextStyle(color: kFg2, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _activatePreset(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: kCrystal400,
                          foregroundColor: kFgOnCyan,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kR3),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Activate Now'),
                      ),
                    ),
                    if (preset.isCustom) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _editPreset(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kFg2,
                            side: BorderSide(color: kFg1.withAlpha(40)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(kR3),
                            ),
                          ),
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _activatePreset(BuildContext context) {
    PresetService().switchPreset(preset.id);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched to ${preset.name}')),
    );
  }

  void _editPreset(BuildContext context) {
    Navigator.pop(context);
    final parent = parentContext;
    if (parent == null) return;
    showModalBottomSheet<void>(
      context: parent,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PresetFormSheet(
        preset: preset,
        onSave: (Preset updated) async {
          await PresetService().updatePreset(updated);
          onRefresh?.call();
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: kLavender500),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: kFg1,
            ),
          ),
        ],
      );
}

class _TriggerInfo extends StatelessWidget {
  final PresetTrigger trigger;

  const _TriggerInfo({required this.trigger});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trigger.hasTimeTrigger)
            _InfoRow(
              icon: Icons.schedule,
              label: 'Time',
              value: '${trigger.timeStart} - ${trigger.timeEnd}',
            ),
          if (trigger.hasDayTrigger)
            _InfoRow(
              icon: Icons.calendar_today,
              label: 'Days',
              value: _formatDays(trigger.daysOfWeek!),
            ),
          if (trigger.locationType != null)
            _InfoRow(
              icon: Icons.location_on,
              label: 'Location',
              value: trigger.locationType!,
            ),
          if (trigger.manualOnly)
            const _InfoRow(
              icon: Icons.touch_app,
              label: 'Manual',
              value: 'Manual activation only',
            ),
        ],
      );

  String _formatDays(List<int> days) {
    const dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days.map((d) => dayNames[d]).join(', ');
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: kFg4),
            const SizedBox(width: 8),
            Text('$label: ', style: const TextStyle(color: kFg3, fontSize: 13)),
            Text(value, style: const TextStyle(color: kFg1, fontSize: 13)),
          ],
        ),
      );
}

// ============================================================================
// Locations Tab
// ============================================================================

class _LocationsTab extends StatefulWidget {
  const _LocationsTab();

  @override
  State<_LocationsTab> createState() => _LocationsTabState();
}

class _LocationsTabState extends State<_LocationsTab> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final locations = PresetService().savedLocations;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Saved Locations',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: kFg1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Haku uses these locations to automatically switch presets.',
          style: TextStyle(fontSize: 13, color: kFg3),
        ),
        const SizedBox(height: 16),

        _LocationCard(
          icon: '🏠',
          title: 'Home',
          location: locations['home'],
          isLoading: _isSaving,
          onSave: () => _saveCurrentLocation('home'),
          onDelete: () => _deleteLocation('home'),
        ),

        _LocationCard(
          icon: '🏢',
          title: 'Office',
          location: locations['office'],
          isLoading: _isSaving,
          onSave: () => _saveCurrentLocation('office'),
          onDelete: () => _deleteLocation('office'),
        ),

        _LocationCard(
          icon: '🏋️',
          title: 'Gym',
          location: locations['gym'],
          isLoading: _isSaving,
          onSave: () => _saveCurrentLocation('gym'),
          onDelete: () => _deleteLocation('gym'),
        ),

        const SizedBox(height: 24),

        ClipRRect(
          borderRadius: BorderRadius.circular(kR4),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kLavender500.withAlpha(15),
                borderRadius: BorderRadius.circular(kR4),
                border: Border.all(color: kLavender500.withAlpha(50)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: kLavender500, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'How it works',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: kFg1,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Go to the location you want to save\n'
                    '2. Tap "Save Current Location"\n'
                    '3. Haku will remember this place\n'
                    '4. Next time you visit, the matching preset will activate',
                    style: TextStyle(color: kFg2, fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveCurrentLocation(String type) async {
    setState(() => _isSaving = true);

    try {
      final success = await PresetService().saveCurrentLocationAs(type);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved $type location')),
          );
          setState(() {});
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get current location. Please check GPS.'),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteLocation(String type) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kFieldTop,
        title: const Text('Remove Location', style: TextStyle(color: kFg1)),
        content: Text('Remove "$type" from saved locations?',
            style: const TextStyle(color: kFg2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: kFg3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: kErr)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await PresetService().removeLocation(type);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $type location')),
      );
    }
  }
}

class _LocationCard extends StatelessWidget {
  final String icon;
  final String title;
  final SavedLocation? location;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final bool isLoading;

  const _LocationCard({
    required this.icon,
    required this.title,
    required this.location,
    required this.onSave,
    required this.onDelete,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kR3),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kGlassFill,
              borderRadius: BorderRadius.circular(kR3),
              border: Border.all(color: kGlassStroke),
            ),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: kFg1,
                        ),
                      ),
                      if (location != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          location!.name,
                          style: const TextStyle(
                              fontSize: 12, color: kFg3),
                        ),
                      ] else
                        const Text(
                          'Not set',
                          style: TextStyle(fontSize: 12, color: kFg4),
                        ),
                    ],
                  ),
                ),
                if (location != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: kFg4),
                    onPressed: onDelete,
                  ),
                FilledButton.icon(
                  onPressed: isLoading ? null : onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: kCrystal400,
                    foregroundColor: kFgOnCyan,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kR2),
                    ),
                  ),
                  icon: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kFgOnCyan),
                        )
                      : Icon(location == null
                          ? Icons.add_location
                          : Icons.refresh),
                  label: Text(isLoading
                      ? 'Saving...'
                      : (location == null ? 'Set' : 'Update')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Preset Form Sheet (Add / Edit)
// ============================================================================

class _PresetFormSheet extends StatefulWidget {
  final Preset? preset;
  final Future<void> Function(Preset) onSave;

  const _PresetFormSheet({this.preset, required this.onSave});

  @override
  State<_PresetFormSheet> createState() => _PresetFormSheetState();
}

class _PresetFormSheetState extends State<_PresetFormSheet> {
  late final TextEditingController _iconCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _greetingCtrl;
  late final TextEditingController _personalityCtrl;
  bool _manualOnly = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _iconCtrl = TextEditingController(text: p?.icon ?? '⭐');
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _greetingCtrl = TextEditingController(text: p?.behavior.greeting ?? '');
    _personalityCtrl =
        TextEditingController(text: p?.behavior.personality ?? '');
    _manualOnly = p?.trigger.manualOnly ?? true;
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _greetingCtrl.dispose();
    _personalityCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a preset name')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final preset = Preset(
        id: widget.preset?.id ??
            'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        icon: _iconCtrl.text.trim().isEmpty ? '⭐' : _iconCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        trigger: PresetTrigger(manualOnly: _manualOnly),
        behavior: PresetBehavior(
          greeting: _greetingCtrl.text.trim(),
          personality: _personalityCtrl.text.trim(),
        ),
        isCustom: true,
        isEnabled: widget.preset?.isEnabled ?? true,
      );
      await widget.onSave(preset);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.preset != null;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: const BoxDecoration(
              color: kFieldTop,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: kFg4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    isEdit ? 'Edit Preset' : 'New Preset',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kFg1,
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: _iconCtrl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 28),
                          maxLength: 2,
                          decoration: InputDecoration(
                            labelText: 'Icon',
                            labelStyle: const TextStyle(color: kFg3),
                            counterText: '',
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kR2),
                              borderSide: const BorderSide(color: kGlassStroke),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kR2),
                              borderSide:
                                  const BorderSide(color: kCrystal400),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _nameCtrl,
                          style: const TextStyle(color: kFg1),
                          decoration: InputDecoration(
                            labelText: 'Name *',
                            labelStyle: const TextStyle(color: kFg3),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kR2),
                              borderSide: const BorderSide(color: kGlassStroke),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kR2),
                              borderSide:
                                  const BorderSide(color: kCrystal400),
                            ),
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _buildField(_descCtrl, 'Description'),
                  const SizedBox(height: 12),
                  _buildField(_greetingCtrl, 'Greeting message', maxLines: 2),
                  const SizedBox(height: 12),
                  _buildField(_personalityCtrl, 'Personality'),
                  const SizedBox(height: 4),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Manual activation only',
                      style: TextStyle(color: kFg1, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Do not auto-trigger by time or location',
                      style: TextStyle(color: kFg3, fontSize: 12),
                    ),
                    value: _manualOnly,
                    activeThumbColor: kCrystal400,
                    onChanged: (v) => setState(() => _manualOnly = v),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: kCrystal400,
                        foregroundColor: kFgOnCyan,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kR3),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: kFgOnCyan),
                            )
                          : Text(isEdit ? 'Save Changes' : 'Create Preset'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: kFg1),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kFg3),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR2),
          borderSide: const BorderSide(color: kGlassStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR2),
          borderSide: const BorderSide(color: kCrystal400),
        ),
      ),
    );
  }
}
