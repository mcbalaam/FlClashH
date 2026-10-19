import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:win32_registry/win32_registry.dart';

/// FlClashX derives the same HWID from the same source with the same 16-hex
/// SHA-256 truncation, so a device already bound in a panel keeps its slot.
/// Changing the source, the hash or the truncation reads as a new device.
class DeviceInfoService {
  static String? _cachedHwid;

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<Map<String, String>> getSubscriptionHeaders() async {
    final hwid = await _resolveHwid();
    final details = await _resolveDetails();
    final headers = <String, String>{};
    if (hwid != null) {
      headers['x-hwid'] = hwid;
    }
    if (details != null) {
      headers['x-device-os'] = details.os;
      headers['x-ver-os'] = details.osVersion;
      headers['x-device-model'] = details.model;
    }
    return headers;
  }

  Future<String?> _resolveHwid() async {
    final cached = _cachedHwid;
    if (cached != null) {
      return cached;
    }
    try {
      final deviceId = await _platformDeviceId();
      if (deviceId == null || deviceId.isEmpty) {
        return null;
      }
      final hwid = Platform.isAndroid
          ? deviceId
          : sha256
                .convert(utf8.encode(deviceId))
                .toString()
                .substring(0, 16)
                .toUpperCase();
      _cachedHwid = hwid;
      return hwid;
    } catch (error) {
      commonPrint.log(
        'Failed to resolve HWID: $error',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<String?> _platformDeviceId() async {
    if (Platform.isWindows) {
      final machineGuid = _machineGuid();
      if (machineGuid != null && machineGuid.isNotEmpty) {
        return machineGuid;
      }
      final info = await _deviceInfo.windowsInfo;
      return '${info.computerName}-${info.deviceId}-${info.productId}';
    }
    if (Platform.isAndroid) {
      final androidId = await _androidId();
      if (androidId != null && androidId.isNotEmpty) {
        return androidId;
      }
      final info = await _deviceInfo.androidInfo;
      return '${info.brand}-${info.device}-${info.hardware}-${info.id}';
    }
    if (Platform.isLinux) {
      final info = await _deviceInfo.linuxInfo;
      return info.machineId ?? '${info.id}-${info.name}';
    }
    if (Platform.isMacOS) {
      final info = await _deviceInfo.macOsInfo;
      return info.systemGUID ?? '${info.model}-${info.computerName}';
    }
    return null;
  }

  String? _machineGuid() {
    try {
      final key = LOCAL_MACHINE.open(r'SOFTWARE\Microsoft\Cryptography');
      try {
        return key.getString('MachineGuid');
      } finally {
        key.close();
      }
    } catch (error) {
      commonPrint.log(
        'Failed to read MachineGuid: $error',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<String?> _androidId() async {
    try {
      return await app?.getAndroidId();
    } catch (error) {
      commonPrint.log(
        'Failed to read Android ID: $error',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<({String os, String osVersion, String model})?>
  _resolveDetails() async {
    try {
      if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        return (
          os: 'Windows',
          osVersion: info.displayVersion,
          model: info.productName,
        );
      }
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return (
          os: 'Android',
          osVersion: info.version.release,
          model: '${info.manufacturer} ${info.model}',
        );
      }
      if (Platform.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        return (os: 'Linux', osVersion: info.versionId ?? '', model: info.name);
      }
      if (Platform.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        return (os: 'macOS', osVersion: info.osRelease, model: info.model);
      }
      return null;
    } catch (error) {
      commonPrint.log(
        'Failed to read device details: $error',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }
}
