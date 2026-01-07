class ItemDetail {
  final String serialNumber;
  final String currentStatus;
  final String orderNumber;
  final DateTime orderDate;
  final String inventoryId;

  ItemDetail({
    required this.serialNumber,
    required this.currentStatus,
    required this.orderNumber,
    required this.orderDate,
    required this.inventoryId,
  });
}
