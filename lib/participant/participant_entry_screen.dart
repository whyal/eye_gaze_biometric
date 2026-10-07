import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../logging/gaze_jsonl_logger.dart';

class ParticipantEntryScreen extends StatefulWidget {
  final Future<void> Function(String participantId) onStart;

  const ParticipantEntryScreen({
    super.key,
    required this.onStart,
  });

  @override
  State<ParticipantEntryScreen> createState() => _ParticipantEntryScreenState();
}

class _ParticipantEntryScreenState extends State<ParticipantEntryScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatParticipantId(int n) => 'P${n.toString().padLeft(3, '0')}';

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final numericId = int.parse(_controller.text.trim());
    final participantId = _formatParticipantId(numericId);
    setState(() => _submitting = true);
    final info = await GazeJsonlLogger.instance
        .getParticipantSessionInfo(participantId);
    setState(() {
      _hint = info.participantExists
          ? 'Existing user: $participantId (${info.existingSessionCount} prior sessions)'
          : 'New user: $participantId';
    });
    await widget.onStart(participantId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Participant Setup',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Enter participant number (e.g. 12 -> P012)',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Participant Number',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white38),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.greenAccent),
                    ),
                  ),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'Enter a participant number';
                    final n = int.tryParse(v);
                    if (n == null || n <= 0) return 'Enter a positive integer';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (_hint != null)
                  Text(
                    _hint!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(_submitting ? 'Starting...' : 'Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
