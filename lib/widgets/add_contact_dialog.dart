import 'package:flutter/material.dart';

class AddContactResult {
  final bool hidden;
  final String coverName;
  final String? coverEmoji;
  final String? realName;
  final String? realEmoji;
  final String? phone;

  const AddContactResult({
    required this.hidden,
    required this.coverName,
    this.coverEmoji,
    this.realName,
    this.realEmoji,
    this.phone,
  });
}

Future<AddContactResult?> showAddContactDialog(BuildContext context) async {
  final coverCtrl = TextEditingController();
  final coverEmojiCtrl = TextEditingController(text: '📦');
  final realCtrl = TextEditingController();
  final realEmojiCtrl = TextEditingController(text: '👤');
  final phoneCtrl = TextEditingController();

  bool hidden = false;

  final res = await showDialog<AddContactResult>(
    context: context,
    barrierDismissible: true,
    builder: (dctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Add contact'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: hidden,
                    onChanged: (v) => setState(() => hidden = v),
                    title: const Text('Hidden contact'),
                    subtitle: const Text('Shows a cover identity when locked.'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: coverCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cover name',
                      hintText: 'e.g. Delivery',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: coverEmojiCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cover emoji (optional)',
                      hintText: 'e.g. 📦',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (hidden)
                    TextField(
                      controller: realCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Real name',
                        hintText: 'Visible only when unlocked',
                      ),
                    ),
                  if (hidden) const SizedBox(height: 10),
                  if (hidden)
                    TextField(
                      controller: realEmojiCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Real emoji (optional)',
                        hintText: 'e.g. 👤',
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final cover = coverCtrl.text.trim();
                  final coverEmoji = coverEmojiCtrl.text.trim();
                  final real = realCtrl.text.trim();
                  final realEmoji = realEmojiCtrl.text.trim();
                  final phone = phoneCtrl.text.trim();

                  if (cover.isEmpty) return;

                  Navigator.pop(
                    dctx,
                    AddContactResult(
                      hidden: hidden,
                      coverName: cover,
                      coverEmoji: coverEmoji.isEmpty ? null : coverEmoji,
                      realName: hidden ? (real.isEmpty ? null : real) : null,
                      realEmoji: hidden ? (realEmoji.isEmpty ? null : realEmoji) : null,
                      phone: phone.isEmpty ? null : phone,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  coverCtrl.dispose();
  coverEmojiCtrl.dispose();
  realCtrl.dispose();
  realEmojiCtrl.dispose();
  phoneCtrl.dispose();
  return res;
}
