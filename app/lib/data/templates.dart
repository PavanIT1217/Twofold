/// The kinds of things a family keeps in Twofold, and the fields each one
/// starts with. Every item can also have custom fields.
library;

enum FieldKind { text, secret, number, date, phone, multiline, url }

class FieldSpec {
  const FieldSpec(this.key, this.label, [this.kind = FieldKind.text]);

  final String key;
  final String label;
  final FieldKind kind;
}

enum Category {
  insurance('Insurance', '🛡️'),
  property('Property', '🏠'),
  banking('Banking', '🏦'),
  investments('Investments', '📈'),
  passwords('Passwords', '🔑'),
  ids('IDs', '🪪'),
  vehicles('Vehicles & loans', '🚗'),
  contacts('Contacts', '📞'),
  notes('Notes', '📝');

  const Category(this.label, this.emoji);

  final String label;
  final String emoji;
}

class ItemTemplate {
  const ItemTemplate({
    required this.type,
    required this.label,
    required this.category,
    required this.fields,
    this.titleHint = '',
  });

  final String type;
  final String label;
  final Category category;
  final List<FieldSpec> fields;
  final String titleHint;

  /// Date fields, which can carry renewal reminders.
  Iterable<FieldSpec> get dateFields =>
      fields.where((f) => f.kind == FieldKind.date);
}

const _policyFields = [
  FieldSpec('insurer', 'Insurer'),
  FieldSpec('policy_no', 'Policy number'),
  FieldSpec('insured', 'Who is covered'),
  FieldSpec('sum_assured', 'Sum assured', FieldKind.number),
  FieldSpec('premium', 'Premium', FieldKind.number),
  FieldSpec('frequency', 'Premium frequency'),
  FieldSpec('next_due', 'Next premium due', FieldKind.date),
  FieldSpec('expiry', 'Policy end date', FieldKind.date),
  FieldSpec('nominee', 'Nominee'),
  FieldSpec('agent_name', 'Agent name'),
  FieldSpec('agent_phone', 'Agent phone', FieldKind.phone),
  FieldSpec('claim_helpline', 'Claim helpline', FieldKind.phone),
  FieldSpec('original_at', 'Where the original is kept'),
];

const List<ItemTemplate> templates = [
  ItemTemplate(
    type: 'login',
    label: 'Login / password',
    category: Category.passwords,
    titleHint: 'e.g. Netbanking',
    fields: [
      FieldSpec('website', 'Website or app', FieldKind.url),
      FieldSpec('username', 'Username or email'),
      FieldSpec('password', 'Password', FieldKind.secret),
      FieldSpec('pin', 'PIN', FieldKind.secret),
    ],
  ),
  ItemTemplate(
    type: 'life_insurance',
    label: 'Life insurance',
    category: Category.insurance,
    titleHint: 'e.g. Term plan – Ravi',
    fields: _policyFields,
  ),
  ItemTemplate(
    type: 'health_insurance',
    label: 'Health insurance',
    category: Category.insurance,
    titleHint: 'e.g. Family floater',
    fields: [
      ..._policyFields,
      FieldSpec('tpa', 'TPA / cashless desk', FieldKind.phone),
      FieldSpec('member_ids', 'Member IDs', FieldKind.multiline),
    ],
  ),
  ItemTemplate(
    type: 'vehicle_insurance',
    label: 'Vehicle insurance',
    category: Category.insurance,
    titleHint: 'e.g. Car insurance',
    fields: [
      FieldSpec('insurer', 'Insurer'),
      FieldSpec('policy_no', 'Policy number'),
      FieldSpec('vehicle', 'Vehicle number'),
      FieldSpec('expiry', 'Renewal date', FieldKind.date),
      FieldSpec('premium', 'Premium', FieldKind.number),
      FieldSpec('claim_helpline', 'Claim helpline', FieldKind.phone),
    ],
  ),
  ItemTemplate(
    type: 'home_insurance',
    label: 'Home insurance',
    category: Category.insurance,
    fields: [
      FieldSpec('insurer', 'Insurer'),
      FieldSpec('policy_no', 'Policy number'),
      FieldSpec('property', 'Property covered'),
      FieldSpec('expiry', 'Renewal date', FieldKind.date),
      FieldSpec('claim_helpline', 'Claim helpline', FieldKind.phone),
    ],
  ),
  ItemTemplate(
    type: 'property',
    label: 'Property',
    category: Category.property,
    titleHint: 'e.g. Flat in Visakhapatnam',
    fields: [
      FieldSpec('address', 'Address', FieldKind.multiline),
      FieldSpec('owners', 'Owner(s)'),
      FieldSpec('survey_no', 'Survey / door number'),
      FieldSpec('registration_no', 'Registration document number'),
      FieldSpec('registration_date', 'Registration date', FieldKind.date),
      FieldSpec('sub_registrar', 'Sub-registrar office'),
      FieldSpec('tax_id', 'Property tax ID'),
      FieldSpec('tax_due', 'Property tax due', FieldKind.date),
      FieldSpec('loan', 'Home loan (lender, account)'),
      FieldSpec('original_at', 'Where the originals are kept'),
    ],
  ),
  ItemTemplate(
    type: 'bank_account',
    label: 'Bank account',
    category: Category.banking,
    titleHint: 'e.g. Savings – SBI',
    fields: [
      FieldSpec('bank', 'Bank'),
      FieldSpec('branch', 'Branch'),
      FieldSpec('account_no', 'Account number'),
      FieldSpec('ifsc', 'IFSC'),
      FieldSpec('holders', 'Account holder(s)'),
      FieldSpec('nominee', 'Nominee'),
      FieldSpec('customer_id', 'Customer ID'),
      FieldSpec('netbanking', 'Netbanking login', FieldKind.secret),
      FieldSpec('branch_phone', 'Branch phone', FieldKind.phone),
    ],
  ),
  ItemTemplate(
    type: 'locker',
    label: 'Bank locker',
    category: Category.banking,
    fields: [
      FieldSpec('bank', 'Bank and branch'),
      FieldSpec('locker_no', 'Locker number'),
      FieldSpec('key_at', 'Where the key is kept'),
      FieldSpec('holders', 'Holder(s)'),
      FieldSpec('nominee', 'Nominee'),
      FieldSpec('rent_due', 'Rent due', FieldKind.date),
      FieldSpec('contents', 'What is inside', FieldKind.multiline),
    ],
  ),
  ItemTemplate(
    type: 'deposit',
    label: 'Fixed / recurring deposit',
    category: Category.investments,
    fields: [
      FieldSpec('bank', 'Bank'),
      FieldSpec('deposit_no', 'Deposit number'),
      FieldSpec('amount', 'Amount', FieldKind.number),
      FieldSpec('rate', 'Interest rate'),
      FieldSpec('maturity', 'Maturity date', FieldKind.date),
      FieldSpec('nominee', 'Nominee'),
    ],
  ),
  ItemTemplate(
    type: 'investment',
    label: 'Investment account',
    category: Category.investments,
    titleHint: 'e.g. PPF, EPF, NPS, demat',
    fields: [
      FieldSpec('provider', 'Provider'),
      FieldSpec('account_no', 'Account / folio number'),
      FieldSpec('holder', 'Holder'),
      FieldSpec('nominee', 'Nominee'),
      FieldSpec('login', 'Login details', FieldKind.secret),
      FieldSpec('contribution_due', 'Contribution due', FieldKind.date),
    ],
  ),
  ItemTemplate(
    type: 'id_document',
    label: 'ID document',
    category: Category.ids,
    titleHint: 'e.g. Passport – Priya',
    fields: [
      FieldSpec('kind', 'Document (Aadhaar, PAN, passport…)'),
      FieldSpec('number', 'Number'),
      FieldSpec('name_on_doc', 'Name on document'),
      FieldSpec('issued', 'Issue date', FieldKind.date),
      FieldSpec('expiry', 'Expiry date', FieldKind.date),
      FieldSpec('original_at', 'Where the original is kept'),
    ],
  ),
  ItemTemplate(
    type: 'vehicle',
    label: 'Vehicle',
    category: Category.vehicles,
    fields: [
      FieldSpec('registration', 'Registration number'),
      FieldSpec('model', 'Make and model'),
      FieldSpec('owner', 'Owner'),
      FieldSpec('rc_at', 'Where the RC is kept'),
      FieldSpec('puc_expiry', 'PUC expiry', FieldKind.date),
      FieldSpec('service_due', 'Service due', FieldKind.date),
    ],
  ),
  ItemTemplate(
    type: 'loan',
    label: 'Loan',
    category: Category.vehicles,
    fields: [
      FieldSpec('lender', 'Lender'),
      FieldSpec('account_no', 'Loan account number'),
      FieldSpec('emi', 'EMI', FieldKind.number),
      FieldSpec('emi_date', 'Next EMI date', FieldKind.date),
      FieldSpec('end_date', 'Loan end date', FieldKind.date),
      FieldSpec('insurance', 'Loan insurance'),
    ],
  ),
  ItemTemplate(
    type: 'contact',
    label: 'Contact',
    category: Category.contacts,
    titleHint: 'e.g. Family doctor',
    fields: [
      FieldSpec('name', 'Name'),
      FieldSpec('role', 'Role (doctor, CA, lawyer…)'),
      FieldSpec('phone', 'Phone', FieldKind.phone),
      FieldSpec('email', 'Email'),
      FieldSpec('address', 'Address', FieldKind.multiline),
    ],
  ),
  ItemTemplate(
    type: 'note',
    label: 'Note',
    category: Category.notes,
    fields: [],
  ),
  ItemTemplate(
    type: 'read_first',
    label: 'Read this first',
    category: Category.notes,
    titleHint: 'A note for the family',
    fields: [],
  ),
];

ItemTemplate templateFor(String type) => templates.firstWhere(
  (t) => t.type == type,
  orElse: () => templates.firstWhere((t) => t.type == 'note'),
);
