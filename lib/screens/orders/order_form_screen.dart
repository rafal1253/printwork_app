import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../db/database_helper.dart';
import '../../models/order.dart';
import '../../utils/theme.dart';

class OrderFormScreen extends StatefulWidget {
  final Order? order;
  const OrderFormScreen({super.key, this.order});

  @override
  State<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<OrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clientName = TextEditingController();
  final _clientPhone = TextEditingController();
  final _clientEmail = TextEditingController();
  final _product = TextEditingController();
  final _format = TextEditingController();
  final _quantity = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _deadline;
  OrderStatus _status = OrderStatus.newOrder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final o = widget.order;
    if (o != null) {
      _clientName.text = o.clientName;
      _clientPhone.text = o.clientPhone ?? '';
      _clientEmail.text = o.clientEmail ?? '';
      _product.text = o.productDescription;
      _format.text = o.format ?? '';
      _quantity.text = o.quantity?.toString() ?? '';
      _notes.text = o.notes ?? '';
      _deadline = o.deadline;
      _status = o.status;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _clientName, _clientPhone, _clientEmail,
      _product, _format, _quantity, _notes
    ]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = DatabaseHelper.instance;
    final clientId = const Uuid().v4();

    await db.upsertClient({
      'id': clientId,
      'name': _clientName.text.trim(),
      'phone': _clientPhone.text.trim().isEmpty ? null : _clientPhone.text.trim(),
      'email': _clientEmail.text.trim().isEmpty ? null : _clientEmail.text.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });

    if (widget.order == null) {
      final num = await db.getNextOrderNumber();
      final order = Order(
        orderNumber: num.toString().padLeft(4, '0'),
        clientId: clientId,
        clientName: _clientName.text.trim(),
        clientPhone: _clientPhone.text.trim().isEmpty ? null : _clientPhone.text.trim(),
        clientEmail: _clientEmail.text.trim().isEmpty ? null : _clientEmail.text.trim(),
        productDescription: _product.text.trim(),
        format: _format.text.trim().isEmpty ? null : _format.text.trim(),
        quantity: _quantity.text.isEmpty ? null : int.tryParse(_quantity.text),
        deadline: _deadline,
        status: _status,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      await db.insertOrder(order.toMap());
    } else {
      final updated = widget.order!.copyWith(
        status: _status,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        deadline: _deadline,
        format: _format.text.trim().isEmpty ? null : _format.text.trim(),
        quantity: _quantity.text.isEmpty ? null : int.tryParse(_quantity.text),
        productDescription: _product.text.trim(),
        clientPhone: _clientPhone.text.trim().isEmpty ? null : _clientPhone.text.trim(),
        clientEmail: _clientEmail.text.trim().isEmpty ? null : _clientEmail.text.trim(),
      );
      await db.updateOrder(updated.toMap());
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.order != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edytuj zlecenie' : 'Nowe zlecenie'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Zapisz',
                    style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Klient', [
              _field('Nazwa klienta *', _clientName,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Wymagane' : null),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _field('Telefon', _clientPhone,
                        keyboardType: TextInputType.phone)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field('E-mail', _clientEmail,
                        keyboardType: TextInputType.emailAddress)),
              ]),
            ]),
            const SizedBox(height: 16),
            _section('Zlecenie', [
              _field('Opis produktu *', _product,
                  maxLines: 3,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Wymagane' : null),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _field('Format (np. A4, B2)', _format)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field('Nakład (szt.)', _quantity,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ])),
              ]),
              const SizedBox(height: 10),
              _deadlinePicker(),
              const SizedBox(height: 10),
              _statusDropdown(),
            ]),
            const SizedBox(height: 16),
            _section('Uwagi', [
              _field('Notatki / uwagi do zlecenia', _notes,
                  maxLines: 4),
            ]),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children),
          ),
        ],
      );

  Widget _field(String label, TextEditingController ctrl,
      {int maxLines = 1,
      TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters,
      String? Function(String?)? validator}) =>
      TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        decoration: InputDecoration(labelText: label),
      );

  Widget _deadlinePicker() => InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _deadline ?? DateTime.now().add(const Duration(days: 7)),
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
            locale: const Locale('pl'),
          );
          if (picked != null) setState(() => _deadline = picked);
        },
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Termin realizacji',
            suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(
            _deadline != null
                ? DateFormat('dd.MM.yyyy').format(_deadline!)
                : 'Wybierz datę',
            style: TextStyle(
                fontSize: 14,
                color: _deadline != null
                    ? AppTheme.textPrimary
                    : AppTheme.textHint),
          ),
        ),
      );

  Widget _statusDropdown() => DropdownButtonFormField<OrderStatus>(
        value: _status,
        decoration: const InputDecoration(labelText: 'Status'),
        items: OrderStatus.values
            .map((s) => DropdownMenuItem(
                value: s,
                child: Row(children: [
                  Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                          color: Color(s.color), shape: BoxShape.circle)),
                  Text(s.label, style: const TextStyle(fontSize: 14)),
                ])))
            .toList(),
        onChanged: (v) => setState(() => _status = v!),
      );
}
