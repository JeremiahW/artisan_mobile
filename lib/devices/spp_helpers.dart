import 'dart:io';

/// Classic Bluetooth SPP adapters commonly used with Artisan (e.g. Artisan-SPP-1858).
bool looksLikeClassicSppName(String name) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return false;
  return n.contains('artisan-spp') ||
      n.startsWith('artisan spp') ||
      RegExp(r'\bspp[-_]?\d{3,}\b').hasMatch(n) ||
      n.startsWith('hc-05') ||
      n.startsWith('hc-06') ||
      n.startsWith('hc-08') ||
      n.startsWith('bt04') ||
      n.startsWith('bt05');
}

/// PIN is often embedded in the name, e.g. Artisan-SPP-1858 → 1858.
String? pinFromDeviceName(String name) {
  final match = RegExp(r'(?:artisan[-_ ]?spp[-_ ]?|spp[-_ ]?)(\d{4})', caseSensitive: false)
      .firstMatch(name);
  return match?.group(1);
}

String classicSppUnsupportedOnIosMessage(String deviceName) {
  final pin = pinFromDeviceName(deviceName) ?? '设备名末尾数字（如 1858）';
  return '「$deviceName」是经典蓝牙串口（SPP），不是低功耗蓝牙（BLE）。'
      'iPad / iPhone 的第三方 App 无法连接这类模块。'
      '请改用 Android 平板：先在系统蓝牙里配对，配对码是 $pin，'
      '再在本 App 选择对应的蓝牙串口设备后扫描连接。';
}

String classicSppWrongBleMessage(String deviceName) {
  final pin = pinFromDeviceName(deviceName) ?? '设备名末尾数字';
  if (Platform.isIOS) {
    return classicSppUnsupportedOnIosMessage(deviceName);
  }
  return '「$deviceName」是经典蓝牙串口（SPP），不能用「通用蓝牙 / BLE」连接，'
      '所以会提示没有通知特征。'
      '请改选「经典蓝牙串口 ASCII」或其他 SPP 设备。'
      '若尚未配对：到系统设置 → 蓝牙，点设备并输入配对码 $pin，再回到 App 扫描连接。';
}

String sppRequiresAndroidMessage() {
  return '经典蓝牙串口（SPP）只在 Android 平板可用。'
      'iPad 不支持 Artisan-SPP / HC-05 这类需要配对码的串口模块。';
}
