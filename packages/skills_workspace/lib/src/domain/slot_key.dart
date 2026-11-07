final RegExp _unsafeSlotCharacters = RegExp('[^a-z0-9._]+');
final RegExp _slotEdgeCharacters = RegExp(r'^[.-]+|[.-]+$');

final class SlotKeyDerivation {
  const SlotKeyDerivation.accepted(this.value) : rejectionReason = null;

  const SlotKeyDerivation.rejected([this.rejectionReason]) : value = null;

  final String? value;
  final String? rejectionReason;
}

SlotKeyDerivation deriveSlotKeyValue(String declaredName) {
  final normalized = declaredName
      .toLowerCase()
      .replaceAll(_unsafeSlotCharacters, '-')
      .replaceAll(_slotEdgeCharacters, '');
  final slotKey = normalized.length > 255
      ? normalized.substring(0, 255)
      : normalized;
  if (slotKey.isEmpty) {
    return const SlotKeyDerivation.rejected();
  }
  final deviceStem = slotKey.split('.').first.toUpperCase();
  if (_windowsReservedDeviceNames.contains(deviceStem)) {
    return const SlotKeyDerivation.rejected('windowsReservedDeviceName');
  }
  return SlotKeyDerivation.accepted(slotKey);
}

const Set<String> _windowsReservedDeviceNames = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'CLOCK\$',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};
