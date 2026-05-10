import 'package:uuid/uuid.dart';

enum OrderStatus {
  newOrder('new', 'Nowe', 0xFF1565C0),
  inProgress('in_progress', 'W realizacji', 0xFF6A1B9A),
  waitingMaterial('waiting_material', 'Oczekuje na materiał', 0xFFE65100),
  readyForPickup('ready_for_pickup', 'Gotowe do odbioru', 0xFF2E7D32),
  completed('completed', 'Wydane / Zakończone', 0xFF37474F),
  cancelled('cancelled', 'Anulowane', 0xFFC62828);

  final String value;
  final String label;
  final int color;
  const OrderStatus(this.value, this.label, this.color);

  static OrderStatus fromValue(String value) {
    return OrderStatus.values.firstWhere((s) => s.value == value,
        orElse: () => OrderStatus.newOrder);
  }
}

class Order {
  final String id;
  final String orderNumber;
  final String clientId;
  final String clientName;
  final String? clientPhone;
  final String? clientEmail;
  final String productDescription;
  final String? format;
  final int? quantity;
  final DateTime? deadline;
  final OrderStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Order({
    String? id,
    required this.orderNumber,
    required this.clientId,
    required this.clientName,
    this.clientPhone,
    this.clientEmail,
    required this.productDescription,
    this.format,
    this.quantity,
    this.deadline,
    this.status = OrderStatus.newOrder,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'order_number': orderNumber,
        'client_id': clientId,
        'client_name': clientName,
        'client_phone': clientPhone,
        'client_email': clientEmail,
        'product_description': productDescription,
        'format': format,
        'quantity': quantity,
        'deadline': deadline?.toIso8601String(),
        'status': status.value,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Order.fromMap(Map<String, dynamic> m) => Order(
        id: m['id'],
        orderNumber: m['order_number'],
        clientId: m['client_id'],
        clientName: m['client_name'],
        clientPhone: m['client_phone'],
        clientEmail: m['client_email'],
        productDescription: m['product_description'],
        format: m['format'],
        quantity: m['quantity'],
        deadline: m['deadline'] != null ? DateTime.parse(m['deadline']) : null,
        status: OrderStatus.fromValue(m['status']),
        notes: m['notes'],
        createdAt: DateTime.parse(m['created_at']),
        updatedAt: DateTime.parse(m['updated_at']),
      );

  Order copyWith({
    OrderStatus? status,
    String? notes,
    DateTime? deadline,
    String? format,
    int? quantity,
    String? productDescription,
    String? clientPhone,
    String? clientEmail,
  }) =>
      Order(
        id: id,
        orderNumber: orderNumber,
        clientId: clientId,
        clientName: clientName,
        clientPhone: clientPhone ?? this.clientPhone,
        clientEmail: clientEmail ?? this.clientEmail,
        productDescription: productDescription ?? this.productDescription,
        format: format ?? this.format,
        quantity: quantity ?? this.quantity,
        deadline: deadline ?? this.deadline,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
