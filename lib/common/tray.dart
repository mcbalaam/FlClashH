import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tray/tray.dart';

import 'app_localizations.dart';
import 'l10n_labels.dart';
import 'app_ports.dart';
import 'constant.dart';
import 'keyboard.dart';
import 'provider_reader.dart';
import 'system.dart';
import 'tray_rust.dart';
import 'window.dart';

/// Where the tray actually lives. Linux runs the Rust StatusNotifierItem; the
/// other desktops keep the Flutter plugin, whose native menus are app-owned.
abstract interface class TrayTransport {
  Stream<TrayEvent> get events;

  Future<void> show(TraySpec spec);

  Future<void> hide();

  Future<void> setTitle(String title);

  Future<void> openMenu();
}

final class PluginTrayTransport implements TrayTransport {
  const PluginTrayTransport();

  @override
  Stream<TrayEvent> get events => Tray.instance.events;

  @override
  Future<void> show(TraySpec spec) => Tray.instance.show(spec);

  @override
  Future<void> hide() => Tray.instance.hide();

  @override
  Future<void> setTitle(String title) => Tray.instance.setTitle(title);

  @override
  Future<void> openMenu() => Tray.instance.openMenu();
}

TrayTransport trayTransport = system.isLinux
    ? RustTrayTransport()
    : const PluginTrayTransport();

class AppTray implements TrayPort {
  static AppTray? _instance;

  final bool isMacOS;
  final bool isWindows;

  bool _isShutDown = false;

  AppTray._internal({required this.isMacOS, required this.isWindows});

  factory AppTray() {
    _instance ??= AppTray._internal(
      isMacOS: system.isMacOS,
      isWindows: system.isWindows,
    );
    return _instance!;
  }

  @visibleForTesting
  factory AppTray.forPlatform({
    required bool isMacOS,
    required bool isWindows,
  }) {
    return AppTray._internal(isMacOS: isMacOS, isWindows: isWindows);
  }

  String get _trayIconSuffix {
    return isWindows ? 'ico' : 'png';
  }

  String get _trayIconDir {
    if (isWindows) {
      return 'assets/images/tray/windows';
    }
    return isMacOS ? 'assets/images/tray/macos' : 'assets/images/tray/unix';
  }

  String getTrayIcon({
    required bool isStart,
    required bool tunEnable,
    required bool safeMode,
  }) {
    final status = switch ((safeMode, isMacOS || !isStart, tunEnable)) {
      (true, _, _) => 4,
      (false, true, _) => 1,
      (false, false, false) => 2,
      (false, false, true) => 3,
    };
    return '$_trayIconDir/status_$status.$_trayIconSuffix';
  }

  @override
  Future<void> shutdown() async {
    _isShutDown = true;
    // Removing a status item makes macOS forget where the user dragged it in
    // the menu bar; one that goes away with the process keeps its place.
    if (isMacOS) {
      return;
    }
    await trayTransport.hide();
  }

  @override
  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  }) async {
    if (_isShutDown) {
      return;
    }
    await trayTransport.show(
      TraySpec(
        icon: TrayIcon.asset(
          getTrayIcon(
            isStart: trayState.isStart && !trayState.suspended,
            tunEnable: trayState.tunEnable,
            safeMode: trayState.safeMode,
          ),
          isTemplate: isMacOS,
          size: isMacOS ? 18 : 16,
        ),
        toolTip: trayState.safeMode
            ? currentAppLocalizations.safeModeAppTitle(appName)
            : appName,
        menu: _buildMenu(trayState: trayState, read: read),
      ),
    );
    await updateTitle(showTrayTitle: trayState.showTrayTitle, traffic: traffic);
  }

  Future<void> updateTitle({
    required bool showTrayTitle,
    required Traffic traffic,
  }) async {
    if (_isShutDown || !isMacOS) {
      return;
    }
    await trayTransport.setTitle(showTrayTitle ? traffic.trayTitle : '');
  }

  List<TrayMenuItem> _buildMenu({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    final commonAction = read(commonActionProvider.notifier);
    final systemAction = read(systemActionProvider.notifier);
    final setupAction = read(setupActionProvider.notifier);
    final appLocalizations = currentAppLocalizations;
    final showHints = read(appSettingProvider).showTrayHotkeyHints;
    String? detail(HotAction action) =>
        showHints ? _shortcut(trayState, action) : null;

    return [
      TrayMenuStatus(
        label: trayState.isStart
            ? appLocalizations.connected
            : appLocalizations.disconnected,
        connected: trayState.isStart,
      ),
      TrayMenuAction(
        label: trayState.isStart
            ? appLocalizations.stop
            : appLocalizations.start,
        detail: detail(HotAction.start),
        onSelected: commonAction.toggleRunning,
      ),
      const TrayMenuSeparator(),
      for (final mode in Mode.values)
        TrayMenuRadio(
          label: mode.label,
          checked: mode == trayState.mode,
          detail: detail(switch (mode) {
            Mode.rule => HotAction.ruleMode,
            Mode.global => HotAction.globalMode,
            Mode.direct => HotAction.directMode,
          }),
          onSelected: () {
            setupAction.changeMode(mode);
          },
        ),
      const TrayMenuSeparator(),
      if (trayState.isStart) ...[
        TrayMenuCheckbox(
          label: appLocalizations.tun,
          checked: trayState.tunEnable,
          detail: detail(HotAction.tun),
          onSelected: systemAction.updateTun,
        ),
        TrayMenuCheckbox(
          label: appLocalizations.systemProxy,
          checked: trayState.systemProxy,
          detail: detail(HotAction.proxy),
          onSelected: systemAction.updateSystemProxy,
        ),
        const TrayMenuSeparator(),
      ],
      TrayMenuAction(
        label: appLocalizations.show,
        detail: detail(HotAction.view),
        onSelected: () {
          window?.show();
        },
      ),
      TrayMenuAction(
        label: appLocalizations.exit,
        detail: detail(HotAction.exit),
        onSelected: () {
          systemAction.handleExit();
        },
      ),
    ];
  }

  String? _shortcut(TrayState trayState, HotAction action) {
    final hotKey = trayState.hotKeys[action];
    final key = hotKey?.key;
    if (hotKey == null || key == null) {
      return null;
    }
    return ShortcutLabels(
      isMacOS: isMacOS,
      isWindows: isWindows,
    ).text(hotKey.modifiers, key);
  }
}

final appTray = system.isDesktop ? AppTray() : null;
