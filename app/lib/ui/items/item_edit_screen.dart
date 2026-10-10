import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models.dart';
import '../../data/templates.dart';
import '../../services/reminders.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'attachment_view.dart';

/// Largest attachment Twofold accepts, to keep syncing and backups quick.
const maxAttachmentBytes = 15 * 1024 * 1024;

class ItemEditScreen extends StatefulWidget {
  const ItemEditScreen({super.key, required this.item, required this.isNew});

  final VaultItem item;
  final bool isNew;

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _CustomDraft {
  _CustomDraft(String label, String value, this.secret)
    : label = TextEditingController(text: label),
      value = TextEditingController(text: value);

  final TextEditingController label;
  final TextEditingController value;
  bool secret;

  void dispose() {
    label.dispose();
    value.dispose();
  }
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _whatToDo;
  late final TextEditingController _notes;
  late final Map<String, TextEditingController> _fields;
  late final List<_CustomDraft> _custom;
  late final Set<String> _reminderFields;
  late List<Attachment> _attachments;
  final _hidden = <String>{};
  bool _dirty = false;

  ItemTemplate get _template => widget.item.template;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _title = TextEditingController(text: item.title);
    _whatToDo = TextEditingController(text: item.whatToDo);
    _notes = TextEditingController(text: item.notes);
    _fields = {
      for (final f in _template.fields)
        f.key: TextEditingController(text: item.fields[f.key] ?? ''),
    };
    _custom = [
      for (final c in item.custom) _CustomDraft(c.label, c.value, c.secret),
    ];
    _reminderFields = {for (final r in item.reminders) r.field};
    if (widget.isNew) {
      _reminderFields.addAll(_template.dateFields.map((f) => f.key));
    }
    _attachments = List.of(item.attachments);
    _hidden.addAll(
      _template.fields
          .where((f) => f.kind == FieldKind.secret)
          .map((f) => f.key),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _whatToDo.dispose();
    _notes.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final c in _custom) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    final fields = {
      for (final e in _fields.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    final item = widget.item.copyWith(
      title: _title.text.trim(),
      fields: fields,
      custom: [
        for (final c in _custom)
          if (c.label.text.trim().isNotEmpty || c.value.text.trim().isNotEmpty)
            CustomField(
              label: c.label.text.trim(),
              value: c.value.text.trim(),
              secret: c.secret,
            ),
      ],
      whatToDo: _whatToDo.text.trim(),
      notes: _notes.text.trim(),
      reminders: [
        for (final key in _reminderFields)
          if (fields.containsKey(key)) Reminder(field: key),
      ],
      attachments: _attachments,
    );
    try {
      await app.saveItem(item);
      if (widget.isNew && fields.keys.any(_reminderFields.contains)) {
        await app.reminders.requestPermission();
      }
      navigator.pop();
    } on Object catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<bool> _confirmDiscard() async =>
      !_dirty ||
      await confirm(
        context,
        title: 'Discard changes?',
        message: 'What you typed here hasn\'t been saved.',
        action: 'Discard',
        destructive: true,
      );

  Future<void> _addAttachment(String source) async {
    final app = AppScope.read(context);
    try {
      Uint8ListAndName? picked;
      if (source == 'file') {
        final file = await app.whileAway(() => openFile());
        if (file != null) {
          picked = (
            bytes: await file.readAsBytes(),
            name: file.name,
            mime: file.mimeType ?? _guessMime(file.name),
          );
        }
      } else {
        final image = await app.whileAway(
          () => ImagePicker().pickImage(
            source: source == 'camera'
                ? ImageSource.camera
                : ImageSource.gallery,
            imageQuality: 85,
            maxWidth: 2400,
          ),
        );
        if (image != null) {
          picked = (
            bytes: await image.readAsBytes(),
            name: image.name,
            mime: image.mimeType ?? 'image/jpeg',
          );
        }
      }
      if (picked == null) return;
      if (picked.bytes.length > maxAttachmentBytes) {
        if (mounted) {
          showMessage(
            context,
            'That file is over 15 MB. Try a smaller scan or photo.',
          );
        }
        return;
      }
      final attachment = await app.addAttachment(
        picked.bytes,
        picked.name,
        picked.mime,
      );
      setState(() {
        _attachments = [..._attachments, attachment];
        _dirty = true;
      });
    } on Object catch (e) {
      if (mounted) showError(context, e);
    }
  }

  static String _guessMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _pickDate(String key) async {
    final current = parseFieldDate(_fields[key]!.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null) return;
    _fields[key]!.text =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    _changed();
    setState(() {});
  }

  Widget _fieldInput(FieldSpec f) {
    final controller = _fields[f.key]!;
    switch (f.kind) {
      case FieldKind.date:
        final date = parseFieldDate(controller.text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _pickDate(f.key),
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: f.label,
                  suffixIcon: controller.text.isEmpty
                      ? const Icon(Icons.calendar_today_outlined)
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            controller.clear();
                            _dirty = true;
                          }),
                        ),
                ),
                child: Text(date == null ? 'Not set' : formatDate(date)),
              ),
            ),
            if (date != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _reminderFields.contains(f.key),
                onChanged: (v) => setState(() {
                  v!
                      ? _reminderFields.add(f.key)
                      : _reminderFields.remove(f.key);
                  _dirty = true;
                }),
                title: const Text('Remind us 30, 7 and 1 days before'),
              ),
          ],
        );
      case FieldKind.secret:
        final hidden = _hidden.contains(f.key);
        return TextFormField(
          controller: controller,
          obscureText: hidden,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: f.label,
            suffixIcon: IconButton(
              icon: Icon(
                hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(
                () => hidden ? _hidden.remove(f.key) : _hidden.add(f.key),
              ),
            ),
          ),
        );
      case FieldKind.multiline:
        return TextFormField(
          controller: controller,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(labelText: f.label),
        );
      case FieldKind.number ||
          FieldKind.phone ||
          FieldKind.url ||
          FieldKind.text:
        return TextFormField(
          controller: controller,
          onChanged: (_) => _changed(),
          keyboardType: switch (f.kind) {
            FieldKind.number => const TextInputType.numberWithOptions(
              decimal: true,
            ),
            FieldKind.phone => TextInputType.phone,
            FieldKind.url => TextInputType.url,
            _ => TextInputType.text,
          },
          inputFormatters: f.kind == FieldKind.number
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : null,
          textCapitalization: f.kind == FieldKind.text
              ? TextCapitalization.sentences
              : TextCapitalization.none,
          decoration: InputDecoration(labelText: f.label),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final readFirst = widget.item.type == 'read_first';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isNew ? 'New ${_template.label.toLowerCase()}' : 'Edit',
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(onPressed: _save, child: const Text('Save')),
            ),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
            children: [
              TextFormField(
                controller: _title,
                autofocus: widget.isNew,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _changed(),
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: _template.titleHint.isEmpty
                      ? null
                      : _template.titleHint,
                ),
                validator: (v) => (v ?? '').trim().isEmpty && !readFirst
                    ? 'Give it a title'
                    : null,
              ),
              if (readFirst) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notes,
                  minLines: 8,
                  maxLines: 30,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _changed(),
                  decoration: const InputDecoration(
                    labelText: 'Your note to the family',
                    alignLabelWithHint: true,
                    hintText: 'What should they do first? Who should they call? Where are the important papers?',
                  ),
                ),
              ],
              if (_template.fields.isNotEmpty) ...[
                const SectionHeader('Details'),
                for (final f in _template.fields) ...[
                  _fieldInput(f),
                  const SizedBox(height: 12),
                ],
              ],
              const SectionHeader('Your own fields'),
              for (final (i, c) in _custom.indexed) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: c.label,
                        onChanged: (_) => _changed(),
                        decoration: const InputDecoration(labelText: 'Label'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: c.value,
                        obscureText: c.secret,
                        onChanged: (_) => _changed(),
                        decoration: const InputDecoration(labelText: 'Value'),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) => setState(() {
                        if (v == 'secret') c.secret = !c.secret;
                        if (v == 'remove') _custom.removeAt(i).dispose();
                        _dirty = true;
                      }),
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem(
                          value: 'secret',
                          checked: c.secret,
                          child: const Text('Hide value'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _custom.add(_CustomDraft('', '', false));
                    _dirty = true;
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a field'),
                ),
              ),
              if (!readFirst) ...[
                const SectionHeader('What to do'),
                TextFormField(
                  controller: _whatToDo,
                  minLines: 2,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _changed(),
                  decoration: const InputDecoration(
                    hintText: 'Who to call, which helpline, where the original papers are…',
                  ),
                ),
                const SectionHeader('Notes'),
                TextFormField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 12,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _changed(),
                ),
              ],
              const SectionHeader('Documents'),
              for (final a in _attachments)
                AttachmentTile(
                  attachment: a,
                  onRemove: () => setState(() {
                    _attachments = _attachments
                        .where((x) => x.id != a.id)
                        .toList();
                    _dirty = true;
                  }),
                ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _addAttachment('camera'),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Scan'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _addAttachment('gallery'),
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('Photo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _addAttachment('file'),
                    icon: const Icon(Icons.attach_file),
                    label: const Text('File'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef Uint8ListAndName = ({Uint8List bytes, String name, String mime});
