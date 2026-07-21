enum HoraLinkProduct {
  ble('ble'),
  lora('lora');

  const HoraLinkProduct(this.storageValue);
  final String storageValue;

  static HoraLinkProduct? fromStorage(String? value) {
    for (final product in values) {
      if (product.storageValue == value) return product;
    }
    return null;
  }
}
