typedef TrayMenuItemSelectedCallback = void Function();

sealed class TrayMenuItem {
  const TrayMenuItem();
}

final class TrayMenuAction extends TrayMenuItem {
  const TrayMenuAction({
    required this.label,
    this.detail,
    this.enabled = true,
    this.onSelected,
  });

  final String label;
  final String? detail;
  final bool enabled;
  final TrayMenuItemSelectedCallback? onSelected;
}

final class TrayMenuCheckbox extends TrayMenuItem {
  const TrayMenuCheckbox({
    required this.label,
    required this.checked,
    this.detail,
    this.enabled = true,
    this.onSelected,
  });

  final String label;
  final bool checked;
  final String? detail;
  final bool enabled;
  final TrayMenuItemSelectedCallback? onSelected;
}

/// One entry of a radio group: exactly one item of a consecutive run is
/// [checked]. The platforms that have no radio menu item fall back to a
/// checkmark group.
final class TrayMenuRadio extends TrayMenuItem {
  const TrayMenuRadio({
    required this.label,
    required this.checked,
    this.detail,
    this.enabled = true,
    this.onSelected,
  });

  final String label;
  final bool checked;
  final String? detail;
  final bool enabled;
  final TrayMenuItemSelectedCallback? onSelected;
}

/// A non-interactive status row, drawn with a leading [connected]-coloured dot,
/// as a menu bar app shows its tunnel state.
final class TrayMenuStatus extends TrayMenuItem {
  const TrayMenuStatus({required this.label, required this.connected});

  final String label;
  final bool connected;
}

final class TrayMenuSubmenu extends TrayMenuItem {
  const TrayMenuSubmenu({
    required this.label,
    required this.items,
    this.detail,
    this.enabled = true,
  });

  final String label;
  final List<TrayMenuItem> items;
  final String? detail;
  final bool enabled;
}

final class TrayMenuSeparator extends TrayMenuItem {
  const TrayMenuSeparator();
}
