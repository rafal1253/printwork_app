import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';
import '../../models/order.dart';
import '../../utils/theme.dart';
import '../../widgets/shared_widgets.dart';
import 'order_form_screen.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Order> _orders = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    final data = await DatabaseHelper.instance.getOrders();
    setState(() {
      _orders = data.map(Order.fromMap).toList();
      _loading = false;
    });
  }

  List<Order> get _filtered {
    if (_searchQuery.isEmpty) return _orders;
    final q = _searchQuery.toLowerCase();
    return _orders
        .where((o) =>
            o.clientName.toLowerCase().contains(q) ||
            o.orderNumber.toLowerCase().contains(q) ||
            o.productDescription.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zlecenia drukarni'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Lista'),
            Tab(text: 'Kanban'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nowe zlecenie',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const OrderFormScreen()));
              _loadOrders();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearch(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(),
                      _buildKanban(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSearch() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Szukaj po kliencie, numerze lub opisie...',
            prefixIcon: Icon(Icons.search, size: 18),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
      );

  Widget _buildList() {
    final orders = _filtered;
    if (orders.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Brak zleceń',
        subtitle: 'Dodaj pierwsze zlecenie klikając + w prawym górnym rogu',
        action: ElevatedButton.icon(
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OrderFormScreen()));
            _loadOrders();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Nowe zlecenie'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _OrderCard(
          order: orders[i],
          onTap: () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => OrderDetailScreen(orderId: orders[i].id)));
            _loadOrders();
          },
        ),
      ),
    );
  }

  Widget _buildKanban() {
    final statuses = OrderStatus.values
        .where((s) => s != OrderStatus.cancelled)
        .toList();
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      children: statuses.map((status) {
        final cols = _filtered.where((o) => o.status == status).toList();
        return _KanbanColumn(
          status: status,
          orders: cols,
          onTap: (id) async {
            await Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => OrderDetailScreen(orderId: id)));
            _loadOrders();
          },
        );
      }).toList(),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOverdue = order.deadline != null &&
        order.deadline!.isBefore(DateTime.now()) &&
        order.status != OrderStatus.completed &&
        order.status != OrderStatus.cancelled;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOverdue ? AppTheme.danger : AppTheme.border,
            width: isOverdue ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#${order.orderNumber}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                StatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(order.clientName,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 3),
            Text(order.productDescription,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (order.format != null || order.quantity != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (order.format != null)
                    _chip(Icons.crop_square_outlined, order.format!),
                  if (order.quantity != null) ...[
                    const SizedBox(width: 8),
                    _chip(Icons.layers_outlined, '${order.quantity} szt.'),
                  ],
                ],
              ),
            ],
            if (order.deadline != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: isOverdue ? AppTheme.danger : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('dd.MM.yyyy').format(order.deadline!),
                    style: TextStyle(
                        fontSize: 12,
                        color: isOverdue
                            ? AppTheme.danger
                            : AppTheme.textSecondary,
                        fontWeight: isOverdue ? FontWeight.w600 : null),
                  ),
                  if (isOverdue) ...[
                    const SizedBox(width: 6),
                    const Text('PRZETERMINOWANE',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textSecondary),
          const SizedBox(width: 3),
          Text(text,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
        ],
      );
}

class _KanbanColumn extends StatelessWidget {
  final OrderStatus status;
  final List<Order> orders;
  final Function(String) onTap;

  const _KanbanColumn(
      {required this.status, required this.orders, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Color(status.color).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text(status.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(status.color))),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Color(status.color).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${orders.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(status.color))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: orders.isEmpty
                ? const Center(
                    child: Text('Brak zleceń',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textHint)))
                : ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _OrderCard(
                      order: orders[i],
                      onTap: () => onTap(orders[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
