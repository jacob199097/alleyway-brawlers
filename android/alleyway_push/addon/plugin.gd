@tool
extends EditorPlugin
## The Android build's notification plugin (android/alleyway_push). tools/build_android.mjs copies this
## folder, with the library it builds (bin/), into the Android copy of the project and switches it on there:
## the library and Firebase Cloud Messaging then go into the APK (a Gradle build). godot/ never has it, so
## the PC and Mac builds and their patches don't change.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = AlleywayPushExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class AlleywayPushExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "AlleywayPush"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(["alleyway_push/bin/alleyway_push-release.aar"])

	func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.google.firebase:firebase-messaging:24.1.0"])
