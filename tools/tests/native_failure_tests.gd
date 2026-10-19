extends SceneTree
const Failure=preload("res://mods/pax_harness/src/core/runtime_error.gd")
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
var errors: Array=[]
var checks:=0
func check(value: bool, why: String) -> void:
	checks+=1
	if not value:errors.append(why)
func _initialize() -> void:
	L.configure(JSON.parse_string(FileAccess.get_file_as_string("res://mods/pax_harness/data/lang/ru.json")),JSON.parse_string(FileAccess.get_file_as_string("res://mods/pax_harness/data/lang/en.json")))
	for language: String in ["ru","en"]:
		L.forced_language=language
		for code: String in ["tools.native_research_unchanged","tools.native_order_unchanged","tools.native_value_unchanged"]:
			var failure:=Failure.make(code)
			check(failure.category=="tool" and not failure.retryable,"a native unchanged result is not a stale-read conflict: "+code+" "+language)
			check(failure.message==(L._en if language=="en" else L._ru)["pax_harness_native_action_unchanged"],"unchanged feedback is translated without inventing a rejection cause: "+language)
	check(Failure.make("tools.source_changed_read_again").category=="conflict","actual revision changes retain the concurrency guard")
	check(Failure.make("tools.read_required").category=="conflict","required native reads retain the concurrency guard")
	L.forced_language=""
	print("NATIVE_FAILURE_TESTS ","PASS" if errors.is_empty() else errors,"; ",checks," checks")
	quit(0 if errors.is_empty() else 1)
