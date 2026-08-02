import 'package:flutter/material.dart';
import 'package:fwupdate/fwupdate.dart';

/// A small form for editing the [FirmwareInfo] Simulation Control offers
/// when "new Firmware available" is on — the tester rarely needs this
/// (presets set reasonable defaults), but it's here so specific values
/// (urgency, version string, k-octets) can be exercised deliberately.
Future<FirmwareInfo?> showFirmwareDetailsDialog(
  BuildContext context, {
  required FirmwareInfo initial,
}) {
  return showDialog<FirmwareInfo>(
    context: context,
    builder: (context) => _FirmwareDetailsDialog(initial: initial),
  );
}

class _FirmwareDetailsDialog extends StatefulWidget {
  const _FirmwareDetailsDialog({required this.initial});

  final FirmwareInfo initial;

  @override
  State<_FirmwareDetailsDialog> createState() => _FirmwareDetailsDialogState();
}

class _FirmwareDetailsDialogState extends State<_FirmwareDetailsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _version;
  late final TextEditingController _patch;
  late final TextEditingController _kOctets;
  late final TextEditingController _infoUri;
  late String _urgency;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial.names.firstOrNull ?? 'main-controller');
    _version = TextEditingController(
      text: widget.initial.stringVersions.firstOrNull ?? '1.1.0',
    );
    _patch = TextEditingController(text: widget.initial.patches.firstOrNull ?? 'none');
    _kOctets = TextEditingController(text: '${widget.initial.kOctets}');
    _infoUri = TextEditingController(text: widget.initial.infoUri?.toString() ?? '');
    _urgency = widget.initial.urgency.isNotEmpty ? widget.initial.urgency : NewFirmwareUrgency.feature;
  }

  @override
  void dispose() {
    _name.dispose();
    _version.dispose();
    _patch.dispose();
    _kOctets.dispose();
    _infoUri.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Firmware details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'printer-new-firmware-name'),
            ),
            TextField(
              controller: _version,
              decoration: const InputDecoration(
                labelText: 'printer-new-firmware-string-version',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _urgency,
              decoration: const InputDecoration(labelText: 'printer-new-firmware-urgency'),
              items: NewFirmwareUrgency.all
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => setState(() => _urgency = v ?? _urgency),
            ),
            TextField(
              controller: _patch,
              decoration: const InputDecoration(labelText: 'printer-new-firmware-patches'),
            ),
            TextField(
              controller: _kOctets,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'printer-new-firmware-k-octets'),
            ),
            TextField(
              controller: _infoUri,
              decoration: const InputDecoration(labelText: 'printer-new-firmware-info-uri'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              FirmwareInfo.simple(
                name: _name.text.trim().isEmpty ? 'main-controller' : _name.text.trim(),
                stringVersion: _version.text.trim().isEmpty ? '1.1.0' : _version.text.trim(),
                urgency: _urgency,
                patch: _patch.text.trim().isEmpty ? 'none' : _patch.text.trim(),
                kOctets: int.tryParse(_kOctets.text.trim()) ?? 45000,
                infoUri: Uri.tryParse(_infoUri.text.trim()),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
