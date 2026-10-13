package org.artisanscope.artisan_flutter

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.regex.Pattern

class MainActivity : FlutterActivity() {
    private val methodChannelName = "artisan/spp"
    private val discoveryChannelName = "artisan/spp_discovery"
    private val incomingChannelName = "artisan/spp_incoming"
    private val tag = "ArtisanSpp"
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val pinPattern: Pattern =
        Pattern.compile("(?:artisan[-_ ]?spp[-_ ]?|spp[-_ ]?)(\\d{4})", Pattern.CASE_INSENSITIVE)

    private var adapter: BluetoothAdapter? = null
    private var socket: BluetoothSocket? = null
    private var reader: Thread? = null
    private var discoverySink: EventChannel.EventSink? = null
    private var incomingSink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private var pendingPin: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val discovered = LinkedHashMap<String, Map<String, String>>()
    private var discoveryLatch: CountDownLatch? = null
    private val discovering = AtomicBoolean(false)

    private val bluetoothReceiver = object : BroadcastReceiver() {
        @SuppressLint("MissingPermission")
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = deviceFrom(intent) ?: return
                    val extraName = intent.getStringExtra(BluetoothDevice.EXTRA_NAME).orEmpty()
                    val name = when {
                        extraName.isNotBlank() -> extraName
                        else -> safeName(device)
                    }
                    remember(device.address, name)
                }
                BluetoothDevice.ACTION_NAME_CHANGED -> {
                    val device = deviceFrom(intent) ?: return
                    remember(device.address, safeName(device))
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    Log.i(tag, "discovery finished, count=${discovered.size}")
                    discoveryLatch?.countDown()
                }
                BluetoothDevice.ACTION_PAIRING_REQUEST -> {
                    val device = deviceFrom(intent) ?: return
                    val pin = pendingPin
                        ?: pinFromName(safeName(device))
                        ?: pinFromName(intent.getStringExtra(BluetoothDevice.EXTRA_NAME).orEmpty())
                        ?: return
                    try {
                        device.setPin(pin.toByteArray(Charsets.UTF_8))
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            @Suppress("DEPRECATION")
                            abortBroadcast()
                        }
                    } catch (error: Exception) {
                        Log.w(tag, "setPin failed: ${error.message}")
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(BluetoothManager::class.java)
        adapter = manager?.adapter
        registerBluetoothReceiver()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bonded" -> result.success(bondedDevices())
                    "discover" -> {
                        val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong() ?: 12000L)
                        Thread {
                            try {
                                val list = discoverBlocking(timeoutMs)
                                mainHandler.post { result.success(list) }
                            } catch (error: Exception) {
                                mainHandler.post {
                                    result.error("discover", error.message, null)
                                }
                            }
                        }.start()
                    }
                    "startDiscovery" -> {
                        try {
                            seedBonded()
                            if (adapter?.isDiscovering == true) adapter?.cancelDiscovery()
                            val started = adapter?.startDiscovery() == true
                            Log.i(tag, "startDiscovery=$started")
                            result.success(started)
                        } catch (error: SecurityException) {
                            result.error("permission", error.message, null)
                        }
                    }
                    "stopDiscovery" -> {
                        try {
                            adapter?.cancelDiscovery()
                        } catch (_: SecurityException) {
                        }
                        result.success(true)
                    }
                    "connect" -> connect(
                        call.argument<String>("id"),
                        call.argument<String>("pin"),
                        result,
                    )
                    "write" -> {
                        val data = call.arguments as? ByteArray
                        try {
                            socket?.outputStream?.write(data)
                            socket?.outputStream?.flush()
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("write", error.message, null)
                        }
                    }
                    "disconnect" -> {
                        closeSocket()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, discoveryChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    discoverySink = events
                }

                override fun onCancel(arguments: Any?) {
                    discoverySink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, incomingChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    incomingSink = events
                }

                override fun onCancel(arguments: Any?) {
                    incomingSink = null
                }
            })
    }

    @SuppressLint("MissingPermission")
    private fun bondedDevices(): List<Map<String, String>> {
        val devices = try {
            adapter?.bondedDevices ?: emptySet()
        } catch (error: SecurityException) {
            Log.w(tag, "bondedDevices permission: ${error.message}")
            emptySet()
        }
        return devices.mapNotNull {
            val id = normalizeMac(it.address)
            if (id.isBlank()) return@mapNotNull null
            mapOf(
                "id" to id,
                "name" to (it.name?.takeIf { n -> n.isNotBlank() } ?: id),
                "bonded" to "true",
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun seedBonded() {
        synchronized(discovered) {
            for (item in bondedDevices()) {
                val id = item["id"] ?: continue
                val previous = discovered[id]
                if (previous == null) {
                    discovered[id] = item
                } else {
                    discovered[id] = previous.toMutableMap().apply {
                        put("bonded", "true")
                        val bondedName = item["name"]
                        if (!bondedName.isNullOrBlank() && bondedName != id) {
                            put("name", bondedName)
                        }
                    }
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun discoverBlocking(timeoutMs: Long): List<Map<String, String>> {
        val bluetooth = adapter ?: throw IllegalStateException("蓝牙适配器不可用")
        if (!bluetooth.isEnabled) {
            throw IllegalStateException("请先打开系统蓝牙")
        }
        if (!discovering.compareAndSet(false, true)) {
            throw IllegalStateException("正在扫描中")
        }
        try {
            synchronized(discovered) { discovered.clear() }
            seedBonded()
            val latch = CountDownLatch(1)
            discoveryLatch = latch
            if (bluetooth.isDiscovering) {
                bluetooth.cancelDiscovery()
                Thread.sleep(300)
            }
            val started = bluetooth.startDiscovery()
            Log.i(tag, "discoverBlocking startDiscovery=$started timeout=$timeoutMs")
            if (!started) {
                throw IllegalStateException(
                    "无法启动经典蓝牙扫描。请确认已授予附近的设备/位置权限，并打开系统定位。",
                )
            }
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            try {
                bluetooth.cancelDiscovery()
            } catch (_: Exception) {
            }
            Thread.sleep(200)
            seedBonded()
            synchronized(discovered) {
                return discovered.values.toList()
            }
        } finally {
            discoveryLatch = null
            discovering.set(false)
        }
    }

    private fun normalizeMac(raw: String): String {
        val cleaned = raw.trim().uppercase().replace('-', ':')
        if (Regex("^([0-9A-F]{2}:){5}[0-9A-F]{2}$").matches(cleaned)) {
            return cleaned
        }
        val hex = cleaned.replace(Regex("[^0-9A-F]"), "")
        if (hex.length == 12) {
            return hex.chunked(2).joinToString(":")
        }
        return cleaned
    }

    private fun remember(address: String, name: String) {
        val id = normalizeMac(address)
        if (id.isBlank()) return
        val label = name.ifBlank { id }
        synchronized(discovered) {
            val previous = discovered[id]
            if (previous == null) {
                discovered[id] = mapOf(
                    "id" to id,
                    "name" to label,
                    "bonded" to "false",
                )
            } else {
                val prevName = previous["name"].orEmpty()
                val keepBonded = previous["bonded"] == "true"
                val betterName = when {
                    label != id && (prevName.isBlank() || prevName == id) -> label
                    looksLikeArtisanName(label) && !looksLikeArtisanName(prevName) -> label
                    else -> prevName.ifBlank { label }
                }
                discovered[id] = mapOf(
                    "id" to id,
                    "name" to betterName,
                    "bonded" to if (keepBonded) "true" else "false",
                )
            }
        }
        Log.i(tag, "found $label ($id)")
        mainHandler.post {
            discoverySink?.success(mapOf("id" to id, "name" to label))
        }
    }

    private fun looksLikeArtisanName(name: String): Boolean {
        val lower = name.lowercase()
        return lower.contains("artisan") || lower.contains("hc-05") || lower.contains("hc-06") ||
            lower.startsWith("spp")
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String?, pin: String?, result: MethodChannel.Result) {
        if (address.isNullOrBlank()) {
            result.error("address", "缺少蓝牙地址", null)
            return
        }
        Thread {
            try {
                adapter?.cancelDiscovery()
                val device = adapter?.getRemoteDevice(address.uppercase())
                    ?: throw IllegalStateException("找不到蓝牙适配器")
                pendingPin = pin ?: pinFromName(safeName(device))
                if (device.bondState != BluetoothDevice.BOND_BONDED) {
                    device.createBond()
                    waitForBond(device, 25_000)
                }
                if (device.bondState != BluetoothDevice.BOND_BONDED) {
                    throw IllegalStateException(
                        "尚未配对。请在系统蓝牙中配对，配对码是 ${pendingPin ?: "设备名末尾数字（如 1858）"}",
                    )
                }
                closeSocket()
                var next = device.createRfcommSocketToServiceRecord(sppUuid)
                try {
                    next.connect()
                } catch (_: Exception) {
                    try {
                        next.close()
                    } catch (_: Exception) {
                    }
                    val method = device.javaClass.getMethod(
                        "createRfcommSocket",
                        Int::class.javaPrimitiveType,
                    )
                    next = method.invoke(device, 1) as BluetoothSocket
                    next.connect()
                }
                socket = next
                startReader(next.inputStream)
                mainHandler.post { result.success(true) }
            } catch (error: Exception) {
                closeSocket()
                mainHandler.post { result.error("connect", error.message, null) }
            } finally {
                pendingPin = null
            }
        }.start()
    }

    @SuppressLint("MissingPermission")
    private fun waitForBond(device: BluetoothDevice, timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (device.bondState == BluetoothDevice.BOND_BONDED) return
            try {
                Thread.sleep(300)
            } catch (_: InterruptedException) {
                return
            }
        }
    }

    private fun startReader(input: InputStream) {
        reader = Thread {
            val buffer = ByteArray(512)
            try {
                while (!Thread.currentThread().isInterrupted) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    val chunk = buffer.copyOf(count)
                    mainHandler.post { incomingSink?.success(chunk) }
                }
            } catch (_: Exception) {
            }
            mainHandler.post { incomingSink?.success(null) }
        }.also { it.start() }
    }

    private fun closeSocket() {
        reader?.interrupt()
        reader = null
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null
    }

    private fun registerBluetoothReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothDevice.ACTION_NAME_CHANGED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothDevice.ACTION_PAIRING_REQUEST)
            priority = IntentFilter.SYSTEM_HIGH_PRIORITY
        }
        // System Bluetooth broadcasts come from another process; must be exported.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(bluetoothReceiver, filter, RECEIVER_EXPORTED)
        } else {
            registerReceiver(bluetoothReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun deviceFrom(intent: Intent): BluetoothDevice? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }
    }

    @SuppressLint("MissingPermission")
    private fun safeName(device: BluetoothDevice): String {
        return try {
            device.name ?: ""
        } catch (_: SecurityException) {
            ""
        }
    }

    private fun pinFromName(name: String): String? {
        val matcher = pinPattern.matcher(name)
        return if (matcher.find()) matcher.group(1) else null
    }

    override fun onDestroy() {
        closeSocket()
        if (receiverRegistered) {
            try {
                unregisterReceiver(bluetoothReceiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }
        super.onDestroy()
    }
}
