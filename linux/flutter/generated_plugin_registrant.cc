//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <overlay_windows_plugin/overlay_windows_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) overlay_windows_plugin_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "OverlayWindowsPlugin");
  overlay_windows_plugin_register_with_registrar(overlay_windows_plugin_registrar);
}
