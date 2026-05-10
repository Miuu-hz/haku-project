import 'package:flutter/material.dart';

import '../models/preset.dart';
import '../services/preset_service.dart';

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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Presets & Locations'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.tune), text: 'Presets'),
              Tab(icon: Icon(Icons.location_on), text: 'Locations'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: const [
                  _PresetsTab(),
                  _LocationsTab(),
                ],
              ),
      );
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
        // Current Preset Card
        if (currentPreset != null) ...[
          _CurrentPresetCard(preset: currentPreset),
          const SizedBox(height: 24),
        ],

        // All Presets
        Text(
          'All Presets',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
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

        // Add Custom Preset Button
        OutlinedButton.icon(
          onPressed: _showAddPresetDialog,
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
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    preset.icon,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Mode',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          preset.name,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                preset.behavior.greeting,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: preset.behavior.focusAreas
                    .map((area) => Chip(
                          label: Text(area),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      );
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
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Text(
            preset.icon,
            style: const TextStyle(fontSize: 28),
          ),
          title: Text(preset.name),
          subtitle: Text(preset.description),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive)
                const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Switch(
                value: preset.isEnabled,
                onChanged: onToggle,
              ),
            ],
          ),
          onTap: onTap,
        ),
      );
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
  Widget build(BuildContext context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Text(
                    preset.icon,
                    style: const TextStyle(fontSize: 48),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preset.name,
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        Text(preset.description),
                      ],
                    ),
                  ),
                ],
              ),

              const Divider(height: 32),

              // Trigger Info
              const _SectionTitle(
                icon: Icons.timer,
                title: 'Trigger Conditions',
              ),
              _TriggerInfo(trigger: preset.trigger),

              const Divider(height: 32),

              // Behavior Info
              const _SectionTitle(
                icon: Icons.psychology,
                title: 'AI Behavior',
              ),
              const SizedBox(height: 8),
              Text(
                'Greeting:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(preset.behavior.greeting),
              const SizedBox(height: 8),
              Text(
                'Personality:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(preset.behavior.personality),

              const SizedBox(height: 16),

              // Suggested Questions
              Text(
                'Suggested Questions:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              ...preset.behavior.suggestedQuestions.map(
                (q) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(q)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _activatePreset(context),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Activate Now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (preset.isCustom)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _editPreset(context),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );

  void _activatePreset(BuildContext context) {
    PresetService().switchPreset(preset.id);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched to ${preset.name}')),
    );
  }

  void _editPreset(BuildContext context) {
    Navigator.pop(context); // close details sheet
    final parent = parentContext;
    if (parent == null) return;
    showModalBottomSheet<void>(
      context: parent,
      isScrollControlled: true,
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
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
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
            Icon(icon, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '$label: ',
              style: const TextStyle(color: Colors.grey),
            ),
            Text(value),
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
        Text(
          'Saved Locations',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Haku uses these locations to automatically switch presets.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        // Home
        _LocationCard(
          icon: '🏠',
          title: 'Home',
          location: locations['home'],
          isLoading: _isSaving,
          onSave: () => _saveCurrentLocation('home'),
          onDelete: () => _deleteLocation('home'),
        ),

        // Office
        _LocationCard(
          icon: '🏢',
          title: 'Office',
          location: locations['office'],
          isLoading: _isSaving,
          onSave: () => _saveCurrentLocation('office'),
          onDelete: () => _deleteLocation('office'),
        ),

        // Gym
        _LocationCard(
          icon: '🏋️',
          title: 'Gym',
          location: locations['gym'],
          isLoading: _isSaving,
          onSave: () => _saveCurrentLocation('gym'),
          onDelete: () => _deleteLocation('gym'),
        ),

        const SizedBox(height: 24),

        // Instructions
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'How it works',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Go to the location you want to save\n'
                  '2. Tap "Save Current Location"\n'
                  '3. Haku will remember this place\n'
                  '4. Next time you visit, the matching preset will activate',
                ),
              ],
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
        title: const Text('Remove Location'),
        content: Text('Remove "$type" from saved locations?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
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
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (location != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        location!.name,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else
                      Text(
                        'Not set',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                  ],
                ),
              ),
              if (location != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ElevatedButton.icon(
                onPressed: isLoading ? null : onSave,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(location == null ? Icons.add_location : Icons.refresh),
                label: Text(isLoading ? 'Saving...' : (location == null ? 'Set' : 'Update')),
              ),
            ],
          ),
        ),
      );
}

// ============================================================================
// Preset Form Sheet (Add / Edit)
// ============================================================================

class _PresetFormSheet extends StatefulWidget {
  final Preset? preset; // null = add mode
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
    _personalityCtrl = TextEditingController(text: p?.behavior.personality ?? '');
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
        id: widget.preset?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              isEdit ? 'Edit Preset' : 'New Preset',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Icon + Name
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
                    decoration: const InputDecoration(
                      labelText: 'Icon',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _greetingCtrl,
              decoration: const InputDecoration(labelText: 'Greeting message'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _personalityCtrl,
              decoration: const InputDecoration(labelText: 'Personality'),
            ),
            const SizedBox(height: 4),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Manual activation only'),
              subtitle: const Text('Do not auto-trigger by time or location'),
              value: _manualOnly,
              onChanged: (v) => setState(() => _manualOnly = v),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isEdit ? 'Save Changes' : 'Create Preset'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
