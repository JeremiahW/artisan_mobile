enum TransportKind { none, ble, spp, websocket }

enum ProtocolKind {
  simulator,
  manual,
  center309,
  center302,
  modbusRtu,
  santoker,
  bluedot,
  ikawa,
  acaia,
  ascii,
  kaleido,
  arduinoTc4,
}

class GattProfile {
  const GattProfile({this.service, required this.notify, this.write});

  final String? service;
  final String notify;
  final String? write;
}

class DevicePreset {
  const DevicePreset({
    required this.id,
    required this.name,
    required this.group,
    required this.transport,
    required this.protocol,
    this.prefixes = const [],
    this.gatt = const [],
    this.detail = '',
  });

  final String id;
  final String name;
  final String group;
  final TransportKind transport;
  final ProtocolKind protocol;
  final List<String> prefixes;
  final List<GattProfile> gatt;
  final String detail;
}

const nordicUart = <GattProfile>[
  GattProfile(
    service: '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
    notify: '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
    write: '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
  ),
];

const devicePresets = <DevicePreset>[
  DevicePreset(
    id: 'simulator',
    name: '模拟烘焙机',
    group: '本机',
    transport: TransportKind.none,
    protocol: ProtocolKind.simulator,
    detail: '不连接硬件，生成一条可操作的升温曲线，用来熟悉界面。',
  ),
  DevicePreset(
    id: 'manual',
    name: '手动输入',
    group: '本机',
    transport: TransportKind.none,
    protocol: ProtocolKind.manual,
    detail: '对应桌面版 NONE。用右侧温度步进记录没有数据口的烘焙。',
  ),
  DevicePreset(
    id: 'santoker-ble',
    name: 'Santoker 蓝牙',
    group: '蓝牙',
    transport: TransportKind.ble,
    protocol: ProtocolKind.santoker,
    prefixes: ['SANTOKER'],
    gatt: nordicUart,
    detail: 'Nordic UART。读取豆温、风温、火力、风门和滚筒，并可下发同样的指令。',
  ),
  DevicePreset(
    id: 'santoker-spp',
    name: 'Santoker 蓝牙串口',
    group: '蓝牙串口',
    transport: TransportKind.spp,
    protocol: ProtocolKind.santoker,
    prefixes: ['SANTOKER'],
    detail: '经典蓝牙 SPP，帧格式与 Santoker 蓝牙相同。',
  ),
  DevicePreset(
    id: 'bluedot',
    name: 'Thermoworks BlueDOT',
    group: '蓝牙',
    transport: TransportKind.ble,
    protocol: ProtocolKind.bluedot,
    prefixes: ['BlueDOT'],
    gatt: [
      GattProfile(notify: '783f2991-23e0-4bdc-ac16-78601bd84b39'),
    ],
    detail: '探针温度记入豆温。',
  ),
  DevicePreset(
    id: 'ikawa',
    name: 'IKAWA',
    group: '蓝牙',
    transport: TransportKind.ble,
    protocol: ProtocolKind.ikawa,
    prefixes: ['IKAWA'],
    gatt: [
      GattProfile(
        service: 'c92a6046-6c8d-4116-9d1d-d20a8f6a245f',
        notify: '948c5059-7f00-46d9-ac55-bf090ae066e3',
        write: '851a4582-19c1-4e6c-ab37-e7a03766ba16',
      ),
    ],
    detail: '读取上下温、设定温度、加热和风机。',
  ),
  DevicePreset(
    id: 'acaia',
    name: 'Acaia 秤',
    group: '蓝牙',
    transport: TransportKind.ble,
    protocol: ProtocolKind.acaia,
    prefixes: ['ACAIA', 'LUNAR', 'PEARL', 'PYXIS', 'CINCO', 'UMBRA', 'COSMO', 'PROCHBT', 'ACAIAS'],
    gatt: [
      GattProfile(
        service: '49535343-fe7d-4ae5-8fa9-9fafd205e455',
        notify: '49535343-1e4d-4bd9-ba61-23c647249616',
        write: '49535343-8841-43f4-a8d4-ecbe34729bb3',
      ),
      GattProfile(
        service: '00001820-0000-1000-8000-00805f9b34fb',
        notify: '00002a80-0000-1000-8000-00805f9b34fb',
        write: '00002a80-0000-1000-8000-00805f9b34fb',
      ),
      GattProfile(
        service: '0000fe40-cc7a-482a-984a-7f2ed5b3e58f',
        notify: '0000fe42-8e22-4541-9d4c-21edae82ed19',
        write: '0000fe41-8e22-4541-9d4c-21edae82ed19',
      ),
    ],
    detail: '读取克重，可去皮，并把稳定重量记入豆重或出豆重。',
  ),
  DevicePreset(
    id: 'nus-ascii',
    name: '通用蓝牙串口 ASCII',
    group: '蓝牙',
    transport: TransportKind.ble,
    protocol: ProtocolKind.ascii,
    gatt: nordicUart,
    detail: '仅用于真正的 BLE Nordic UART 模块。不要用来连 Artisan-SPP-xxxx。',
  ),
  DevicePreset(
    id: 'spp-ascii',
    name: '经典蓝牙串口 ASCII',
    group: '蓝牙串口',
    transport: TransportKind.spp,
    protocol: ProtocolKind.ascii,
    detail: '通用 SPP 文本行，格式：风温,豆温。仅 Android 可用。',
  ),
  DevicePreset(
    id: 'center309',
    name: 'CENTER 309 / 304 / K204',
    group: '蓝牙串口',
    transport: TransportKind.spp,
    protocol: ProtocolKind.center309,
    detail: '发送 0x41，解析 45 字节温度帧。通道 1 为风温，通道 2 为豆温。',
  ),
  DevicePreset(
    id: 'center302',
    name: 'CENTER 302 / 300 / K201',
    group: '蓝牙串口',
    transport: TransportKind.spp,
    protocol: ProtocolKind.center302,
    detail: '发送 0x41，解析 7 字节单通道温度，记入豆温。',
  ),
  DevicePreset(
    id: 'modbus',
    name: 'MODBUS RTU',
    group: '蓝牙串口',
    transport: TransportKind.spp,
    protocol: ProtocolKind.modbusRtu,
    detail: '从保持或输入寄存器连续读取风温和豆温。默认从站 1、地址 0、除以 10。',
  ),
  DevicePreset(
    id: 'kaleido-ws',
    name: 'Kaleido Wi-Fi',
    group: '网络',
    transport: TransportKind.websocket,
    protocol: ProtocolKind.kaleido,
    detail: 'WebSocket，默认 ws://主机:80/ws。读取 BT/ET，并可下发火力和风速。',
  ),
  DevicePreset(
    id: 'kaleido-spp',
    name: 'Kaleido 蓝牙串口',
    group: '蓝牙串口',
    transport: TransportKind.spp,
    protocol: ProtocolKind.kaleido,
    prefixes: ['KALEIDO', 'Kaleido'],
    detail: '与 Kaleido 串口模式相同的文本协议，走经典蓝牙 SPP。',
  ),
  DevicePreset(
    id: 'kaleido-tc4',
    name: 'Kaleido 双系统 (TC4)',
    group: '蓝牙串口',
    transport: TransportKind.spp,
    protocol: ProtocolKind.arduinoTc4,
    prefixes: ['Kaleido_M', 'KALEIDO_M', 'Kaleido', 'KALEIDO', 'TC4'],
    detail: '说明书双系统：蓝牙名 Kaleido_M（触摸屏需点允许）。'
        '载入 Kaleido_双系统.aset 后走 TC4：CHAN/READ/OT1/OT2/IO3/PID/CLDN。',
  ),
  DevicePreset(
    id: 'arduino-tc4',
    name: 'Arduino TC4',
    group: '蓝牙串口',
    transport: TransportKind.spp,
    protocol: ProtocolKind.arduinoTc4,
    prefixes: ['TC4', 'Arduino'],
    detail: '标准 TC4 固件串口协议。',
  ),
];

DevicePreset presetById(String id) {
  final normalized = id == 'artisan-spp' ? 'spp-ascii' : id;
  return devicePresets.firstWhere((p) => p.id == normalized, orElse: () => devicePresets.first);
}

const excludedDeviceNote =
    'Phidget、Yoctopuce 和 Aillio Bullet 依赖桌面端 USB 驱动，这一版不连接这些设备。'
    '温度记录、阶段、事件、报警、PID、曲线文件和上述蓝牙 / 蓝牙串口机型都会保留。';
