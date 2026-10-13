# Artisan Flutter

Android 平板上的 Artisan 烘焙记录。界面沿用桌面版的曲线、LCD、CHARGE 到 COOL END，以及事件按钮和滑条。第一阶段以 Android 平板为准，工程里同时留了 iOS 工程，供下一阶段的 iPad 使用。

## 运行

```bash
cd artisan-flutter
flutter pub get
flutter run
```

模拟器或平板建议横屏。默认设备是「模拟烘焙机」，按 ON 再按 START 就能看到曲线。

## 这一版接通的设备

- 蓝牙：Santoker、Thermoworks BlueDOT、IKAWA、Acaia 秤、Nordic UART 文本行
- 蓝牙串口：CENTER 309/304/K204、CENTER 302/300/K201、MODBUS RTU、Santoker 帧、Kaleido 文本、ASCII 双通道
- 网络：Kaleido Wi-Fi，地址形如 `ws://主机:80/ws`
- 本机：手动输入，以及不连硬件的模拟烘焙机

Phidget、Yoctopuce 和 Aillio Bullet 依赖桌面 USB 驱动，这一版不连接。

## 曲线文件

保存为 `.artisan.json`。也可以打开桌面版导出的制表符 CSV，以及包含 `timex`、`temp1`、`temp2` 的 `.alog` 文本曲线。
