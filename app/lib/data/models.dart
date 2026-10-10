import 'templates.dart';
import 'version_vector.dart';

/// A custom field the user added to an item.
class CustomField {
  const CustomField({
    required this.label,
    required this.value,
    this.secret = false,
  });

  factory CustomField.fromJson(Map<String, Object?> json) => CustomField(
    label: json['label']! as String,
    value: json['value']! as String,
    secret: json['secret'] as bool? ?? false,
  );

  final String label;
  final String value;
  final bool secret;

  Map<String, Object?> toJson() => {
    'label': label,
    'value': value,
    if (secret) 'secret': true,
  };
}

/// A reminder before a date field, e.g. 30, 7 and 1 days before renewal.
class Reminder {
  const Reminder({required this.field, this.daysBefore = const [30, 7, 1]});

  factory Reminder.fromJson(Map<String, Object?> json) => Reminder(
    field: json['field']! as String,
    daysBefore: (json['days']! as List).cast<int>(),
  );

  final String field;
  final List<int> daysBefore;

  Map<String, Object?> toJson() => {'field': field, 'days': daysBefore};
}

/// An encrypted file attached to an item. The file itself is stored
/// separately; [wrappedKey] is its key, wrapped with the vault key.
class Attachment {
  const Attachment({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.keyVersion,
    required this.wrappedKey,
  });

  factory Attachment.fromJson(Map<String, Object?> json) => Attachment(
    id: json['id']! as String,
    name: json['name']! as String,
    mime: json['mime']! as String,
    size: json['size']! as int,
    keyVersion: json['kv']! as int,
    wrappedKey: json['key']! as String,
  );

  final String id;
  final String name;
  final String mime;
  final int size;
  final int keyVersion;
  final String wrappedKey;

  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'mime': mime,
    'size': size,
    'kv': keyVersion,
    'key': wrappedKey,
  };
}

/// One thing in the vault, decrypted.
class VaultItem {
  const VaultItem({
    required this.id,
    required this.type,
    required this.title,
    this.fields = const {},
    this.custom = const [],
    this.notes = '',
    this.whatToDo = '',
    this.reminders = const [],
    this.attachments = const [],
    this.pinned = false,
    this.deleted = false,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    this.vv = const VersionVector(),
  });

  factory VaultItem.fromJson(Map<String, Object?> json) => VaultItem(
    id: json['id']! as String,
    type: json['type']! as String,
    title: json['title'] as String? ?? '',
    fields: (json['fields'] as Map? ?? const {}).cast<String, String>(),
    custom: [
      for (final c in json['custom'] as List? ?? const [])
        CustomField.fromJson((c as Map).cast<String, Object?>()),
    ],
    notes: json['notes'] as String? ?? '',
    whatToDo: json['whatToDo'] as String? ?? '',
    reminders: [
      for (final r in json['reminders'] as List? ?? const [])
        Reminder.fromJson((r as Map).cast<String, Object?>()),
    ],
    attachments: [
      for (final a in json['attachments'] as List? ?? const [])
        Attachment.fromJson((a as Map).cast<String, Object?>()),
    ],
    pinned: json['pinned'] as bool? ?? false,
    deleted: json['deleted'] as bool? ?? false,
    deletedAt: _date(json['deletedAt']),
    createdAt: _date(json['createdAt'])!,
    updatedAt: _date(json['updatedAt'])!,
    updatedBy: json['updatedBy']! as String,
    vv: VersionVector.fromJson(
      (json['vv'] as Map? ?? const {}).cast<String, Object?>(),
    ),
  );

  final String id;
  final String type;
  final String title;
  final Map<String, String> fields;
  final List<CustomField> custom;
  final String notes;

  /// "What to do": who to call, which helpline, where the papers are.
  final String whatToDo;
  final List<Reminder> reminders;
  final List<Attachment> attachments;
  final bool pinned;

  /// In the trash. Trashed items are removed for good after 30 days but the
  /// record stays (with its content cleared) so the deletion syncs.
  final bool deleted;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String updatedBy;
  final VersionVector vv;

  ItemTemplate get template => templateFor(type);

  VaultItem copyWith({
    String? title,
    Map<String, String>? fields,
    List<CustomField>? custom,
    String? notes,
    String? whatToDo,
    List<Reminder>? reminders,
    List<Attachment>? attachments,
    bool? pinned,
    bool? deleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? updatedAt,
    String? updatedBy,
    VersionVector? vv,
    String? id,
  }) => VaultItem(
    id: id ?? this.id,
    type: type,
    title: title ?? this.title,
    fields: fields ?? this.fields,
    custom: custom ?? this.custom,
    notes: notes ?? this.notes,
    whatToDo: whatToDo ?? this.whatToDo,
    reminders: reminders ?? this.reminders,
    attachments: attachments ?? this.attachments,
    pinned: pinned ?? this.pinned,
    deleted: deleted ?? this.deleted,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
    vv: vv ?? this.vv,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    if (fields.isNotEmpty) 'fields': fields,
    if (custom.isNotEmpty) 'custom': [for (final c in custom) c.toJson()],
    if (notes.isNotEmpty) 'notes': notes,
    if (whatToDo.isNotEmpty) 'whatToDo': whatToDo,
    if (reminders.isNotEmpty)
      'reminders': [for (final r in reminders) r.toJson()],
    if (attachments.isNotEmpty)
      'attachments': [for (final a in attachments) a.toJson()],
    if (pinned) 'pinned': true,
    if (deleted) 'deleted': true,
    if (deletedAt != null) 'deletedAt': deletedAt!.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'updatedBy': updatedBy,
    'vv': vv.toJson(),
  };

  /// Everything a search should match.
  String get searchText => [
    title,
    template.label,
    ...fields.values,
    for (final c in custom) ...[c.label, if (!c.secret) c.value],
    notes,
    whatToDo,
  ].join(' ').toLowerCase();

  static DateTime? _date(Object? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);
}

enum Role {
  owner('Owner', 'Manages family members and can change everything'),
  editor('Editor', 'Can add and change items'),
  viewer('Viewer', 'Can only look');

  const Role(this.label, this.description);

  final String label;
  final String description;

  bool get canEdit => this != Role.viewer;
}

/// One paired phone. A person with two phones is two members.
class Member {
  const Member({
    required this.id,
    required this.name,
    required this.publicKey,
    required this.role,
    required this.addedAt,
    this.removed = false,
  });

  factory Member.fromJson(Map<String, Object?> json) => Member(
    id: json['id']! as String,
    name: json['name']! as String,
    publicKey: json['pk']! as String,
    role: Role.values.byName(json['role']! as String),
    addedAt: DateTime.fromMillisecondsSinceEpoch(json['addedAt']! as int),
    removed: json['removed'] as bool? ?? false,
  );

  final String id;
  final String name;

  /// Base64url X25519 public key.
  final String publicKey;
  final Role role;
  final DateTime addedAt;
  final bool removed;

  Member copyWith({String? name, Role? role, bool? removed}) => Member(
    id: id,
    name: name ?? this.name,
    publicKey: publicKey,
    role: role ?? this.role,
    addedAt: addedAt,
    removed: removed ?? this.removed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'pk': publicKey,
    'role': role.name,
    'addedAt': addedAt.millisecondsSinceEpoch,
    if (removed) 'removed': true,
  };
}

/// The vault's name and members. Stored encrypted like an item.
class Roster {
  const Roster({
    required this.vaultName,
    required this.members,
    this.vv = const VersionVector(),
  });

  factory Roster.fromJson(Map<String, Object?> json) => Roster(
    vaultName: json['vaultName']! as String,
    members: {
      for (final m in json['members']! as List)
        (m as Map)['id']! as String: Member.fromJson(m.cast<String, Object?>()),
    },
    vv: VersionVector.fromJson(
      (json['vv'] as Map? ?? const {}).cast<String, Object?>(),
    ),
  );

  static const maxMembers = 6;

  final String vaultName;
  final Map<String, Member> members;
  final VersionVector vv;

  Iterable<Member> get active => members.values.where((m) => !m.removed);

  Member? activeMember(String id) {
    final m = members[id];
    return m == null || m.removed ? null : m;
  }

  Roster copyWith({
    String? vaultName,
    Map<String, Member>? members,
    VersionVector? vv,
  }) => Roster(
    vaultName: vaultName ?? this.vaultName,
    members: members ?? this.members,
    vv: vv ?? this.vv,
  );

  /// Combines two rosters edited on different phones: members from both,
  /// and a removal on either side wins.
  Roster mergeWith(Roster other) {
    final merged = Map.of(members);
    other.members.forEach((id, theirs) {
      final mine = merged[id];
      if (mine == null) {
        merged[id] = theirs;
      } else if (theirs.removed && !mine.removed) {
        merged[id] = theirs;
      } else if (!mine.removed && !theirs.removed && mine.role != theirs.role) {
        // Keep the less powerful role when two owners disagree.
        merged[id] = mine.role.index > theirs.role.index ? mine : theirs;
      }
    });
    final order = vv.compare(other.vv);
    // Every phone must end up with the same name, so a tie is broken by
    // picking the larger string rather than "mine".
    final newerName = switch (order) {
      Order.before => other.vaultName,
      Order.after || Order.same => vaultName,
      Order.concurrent =>
        vaultName.compareTo(other.vaultName) >= 0 ? vaultName : other.vaultName,
    };
    return Roster(
      vaultName: newerName,
      members: merged,
      vv: vv.merge(other.vv),
    );
  }

  Map<String, Object?> toJson() => {
    'vaultName': vaultName,
    'members': [for (final m in members.values) m.toJson()],
    'vv': vv.toJson(),
  };
}
