#pragma once
#include <flutter_plugin_registrar.h>
#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif
FLUTTER_PLUGIN_EXPORT void FirebaseCorePluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);
