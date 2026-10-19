import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:rust_api/rust_api.dart' as frb;
import 'package:tray/tray.dart';

import 'tray.dart';

/// The Linux transport: a real StatusNotifierItem owned by the Rust side, so a
/// left click reaches the app and a toggle updates the menu in place.
class RustTrayTransport implements TrayTransport {
  final StreamController<TrayEvent> _events =
      StreamController<TrayEvent>.broadcast();
  final Map<int, TrayMenuItem> _itemsById = {};
  bool _subscribed = false;
  String _title = '';

  @override
  Stream<TrayEvent> get events => _events.stream;

  void _ensureSubscribed() {
    if (_subscribed) {
      return;
    }
    _subscribed = true;
    frb.trayEvents().listen((event) {
      switch (event.kind) {
        case frb.TrayEventKind.activate:
          _events.add(const TrayIconActivated());
        case frb.TrayEventKind.menuRequested:
          _events.add(const TrayMenuRequested());
        case frb.TrayEventKind.itemSelected:
          final item = _itemsById[event.id];
          if (item == null) {
            return;
          }
          switch (item) {
            case TrayMenuAction(:final onSelected):
              onSelected?.call();
            case TrayMenuCheckbox(:final onSelected):
              onSelected?.call();
            case TrayMenuRadio(:final onSelected):
              onSelected?.call();
            case TrayMenuStatus():
            case TrayMenuSubmenu():
            case TrayMenuSeparator():
              return;
          }
          _events.add(TrayMenuItemSelected(item));
      }
    });
  }

  @override
  Future<void> show(TraySpec spec) async {
    _ensureSubscribed();
    _itemsById.clear();
    var id = 1024;
    final items = <frb.TrayItem>[];
    for (final item in spec.menu) {
      final current = id++;
      switch (item) {
        case TrayMenuSeparator():
          items.add(_item(current, frb.TrayItemKind.separator, ''));
        case TrayMenuAction(:final label, :final detail, :final enabled):
          _itemsById[current] = item;
          items.add(
            _item(
              current,
              frb.TrayItemKind.action,
              label,
              detail: detail,
              enabled: enabled,
            ),
          );
        case TrayMenuCheckbox(
          :final label,
          :final detail,
          :final enabled,
          :final checked,
        ):
          _itemsById[current] = item;
          items.add(
            _item(
              current,
              frb.TrayItemKind.checkbox,
              label,
              detail: detail,
              enabled: enabled,
              checked: checked,
            ),
          );
        case TrayMenuRadio(
          :final label,
          :final detail,
          :final enabled,
          :final checked,
        ):
          _itemsById[current] = item;
          items.add(
            _item(
              current,
              frb.TrayItemKind.radio,
              label,
              detail: detail,
              enabled: enabled,
              checked: checked,
            ),
          );
        case TrayMenuStatus(:final label, :final connected):
          items.add(
            _item(
              current,
              frb.TrayItemKind.status,
              label,
              connected: connected,
            ),
          );
        case TrayMenuSubmenu():
          break;
      }
    }
    final icon = await _decodeIcon(spec.icon);
    await frb.traySet(
      spec: frb.TraySpec(
        toolTip: spec.toolTip,
        title: _title,
        visible: true,
        iconWidth: icon.width,
        iconHeight: icon.height,
        iconRgba: icon.rgba,
        items: items,
      ),
    );
  }

  @override
  Future<void> hide() async {
    _itemsById.clear();
    await frb.trayHide();
  }

  @override
  Future<void> setTitle(String title) async {
    _title = title;
    await frb.traySetTitle(title: title);
  }

  @override
  Future<void> openMenu() async {}

  static frb.TrayItem _item(
    int id,
    frb.TrayItemKind kind,
    String label, {
    String? detail,
    bool enabled = true,
    bool checked = false,
    bool connected = false,
  }) {
    return frb.TrayItem(
      id: id,
      kind: kind,
      label: label,
      detail: detail,
      enabled: enabled,
      checked: checked,
      connected: connected,
    );
  }

  Future<({int width, int height, Uint8List rgba})> _decodeIcon(
    TrayIcon icon,
  ) async {
    final data = await rootBundle.load(icon.asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = bytes?.buffer.asUint8List() ?? Uint8List(0);
    final decoded = (width: image.width, height: image.height, rgba: rgba);
    image.dispose();
    return decoded;
  }
}
