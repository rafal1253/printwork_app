import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';
import '../../models/order.dart';
import '../../utils/theme.dart';
import '../../widgets/shared_widgets.dart';
import 'order_form_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Order? _order;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DatabaseHelper.instance.getOrder(widget.orderId);
    setState(() {
      _order = data != null ? Order.fromMap(data) : null;
      _loading = false;
    });
  }

  Future<void> _changeStatus(OrderStatus s) async {
    final updated = _order!.copyWith(status: s);
    await DatabaseHelper.instance.updateOrder(updated.toMap());
    _load();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Usuń zlecenie'),
        content: const Text('Tej operacji nie można cofnąć. Kontynuować?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Anuluj')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Usuń',
                  style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await DatabaseHelper.instance.deleteOrder(widget.orderId);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_order == null) return const Scaffold(body: Center(child: Text('Nie znaleziono zlecenia')));

    final o = _order!;
    final isOverdue = o.deadline != null &&
        o.deadline!.isBefore(DateTime.now()) &&
        o.status != OrderStatus.completed &&
        o.status != OrderStatus.cancelled;

    return Scaffold(
      appBar: AppBar(
        title: Text('Zlecenie #${o.orderNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => OrderFormScreen(order: o)));
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outlined, color: AppTheme.danger),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                StatusBadge(status: o.status),
                const Spacer(),
                const Text('Zmień:',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(width: 8),
                DropdownButton<OrderStatus>(
                  value: o.status,
                  underline: const SizedBox(),
                  isDense: true,
                  items: OrderStatus.values
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.label,
                              style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) => v != null ? _changeStatus(v) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Client
          _card('Klient', [
            _row(Icons.person_outline, 'Nazwa', o.clientName),
            if (o.clientPhone != null)
              _row(Icons.phone_outlined, 'Telefon', o.clientPhone!),
            if (o.clientEmail != null)
              _row(Icons.email_outlined, 'E-mail', o.clientEmail!),
          ]),
          const SizedBox(height: 12),

          // Order details
          _card('Szczegóły zlecenia', [
            _row(Icons.description_outlined, 'Produkt', o.productDescription),
            if (o.format != null)
              _row(Icons.crop_square_outlined, 'Format', o.format!),
            if (o.quantity != null)
              _row(Icons.layers_outlined, 'Nakład', '${o.quantity} szt.'),
            if (o.deadline != null)
              _row(
                Icons.calendar_today_outlined,
                'Termin',
                DateFormat('dd.MM.yyyy').format(o.deadline!),
                valueColor: isOverdue ? AppTheme.danger : null,
              ),
          ]),
          const SizedBox(height: 12),

          if (o.notes != null && o.notes!.isNotEmpty)
            _card('Uwagi', [
              Text(o.notes!,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textPrimary, height: 1.5))
            ]),

          const SizedBox(height: 12),
          _card('Historia', [
            _row(Icons.add_circle_outline, 'Utworzono',
                DateFormat('dd.MM.yyyy HH:mm').format(o.createdAt)),
            _row(Icons.update_outlined, 'Ostatnia zmiana',
                DateFormat('dd.MM.yyyy HH:mm').format(o.updatedAt)),
          ]),

          const SizedBox(height: 24),
          // Quick status buttons
          const Text('Szybka zmiana statusu',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: OrderStatus.values
                .where((s) => s != o.status)
                .map((s) => OutlinedButton(
                      onPressed: () => _changeStatus(s),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Color(s.color),
                        side: BorderSide(color: Color(s.color)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: Text(s.label),
                    ))
                .toList(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );

  Widget _row(IconData icon, String label, String value,
      {Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text('$label: ',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      color: valueColor ?? AppTheme.textPrimary,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}
