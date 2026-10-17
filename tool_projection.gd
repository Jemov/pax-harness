extends RefCounted
## Lossless archive + bounded wire preview. Referenced full receipts stay readable.
const MAX_TEXT := 6000
const MAX_ITEMS := 24
static func trim(value: Variant, path: String = "result", depth: int = 0) -> Variant:
	if value is String and value.length() > MAX_TEXT:
		return {"preview_start":value.left(3500),"preview_end":value.right(1500),"omitted_characters":value.length()-5000,"full_path":path}
	if value is Array:
		var selected: Array = value if value.size() <= MAX_ITEMS else value.slice(0,16)+value.slice(-8)
		var rows: Array = []
		for index: int in selected.size(): rows.append(trim(selected[index],path+"["+str(index if index<16 or value.size()<=MAX_ITEMS else value.size()-8+index-16)+"]",depth+1))
		return rows if value.size() <= MAX_ITEMS else {"preview":rows,"total":value.size(),"omitted_items":value.size()-24,"full_path":path}
	if value is Dictionary:
		var result: Dictionary = {}
		for key: String in value: result[key] = trim(value[key],path+"."+key,depth+1)
		return result
	return value

static func receipt(value: Dictionary) -> Dictionary:
	if value.get("name") in ["datasets.transform","statistics.calculate"] and value.get("status") == "complete":
		var compact: Dictionary = value.duplicate(true)
		var result: Dictionary = compact.get("result",{})
		var rows: Array = result.get("rows",[])
		result.erase("rows")
		result["preview"] = rows.slice(0,5)
		result["total"] = rows.size()
		result["dataset_ref"] = {"receipt_id":value.get("call_id","")}
		result["instruction"] = "Full data remains local in this task receipt. Use datasets.read to inspect a page, datasets.transform/statistics.calculate to process it, or datasets.chart to render. Preview is not the complete dataset."
		compact["full_receipt"] = {"call_id":value.get("call_id",""),"tool":"trace.read","field":"result"}
		return compact
	if value.get("name") in ["charts.function","charts.map","datasets.chart"] and value.get("status") == "complete" and value.get("result",{}).has("display_ref"):
		var compact: Dictionary = value.duplicate(true)
		var chart: Dictionary = compact.result.get("chart",{})
		compact.result.erase("chart")
		compact.result["chart_summary"] = {"type":chart.get("type"),"title":chart.get("title"),"source":chart.get("source"),"basis":chart.get("basis","observed"),"points":chart.get("labels",[]).size(),"regions":chart.get("regions",[]).size()}
		compact.result["display_instruction"] = "Display a pax-chart fenced JSON block containing display_ref exactly. The native UI resolves the complete saved data; do not reconstruct or invent points."
		compact["full_receipt"] = {"call_id":value.get("call_id",""),"tool":"trace.read","field":"result"}
		return compact
	if JSON.stringify(value).length() <= 18000: return value.duplicate(true)
	if value.get("name") == "analysis.delegate":
		var compact: Dictionary = value.duplicate(true)
		for finding: Variant in compact.get("result",{}).get("findings",compact.get("result",{}).get("partial_findings",[])):
			if not finding is Dictionary: continue
			var metadata: Array = []
			for observation: Dictionary in finding.get("receipts",[]):
				metadata.append({"call_id":observation.get("call_id",""),"name":observation.get("name",""),"status":observation.get("status",""),"failure":observation.get("failure",{}),"errors":observation.get("errors",[])})
			finding["receipts"] = metadata
		compact["pruned"] = true
		compact["full_receipt"] = {"call_id":value.get("call_id",""),"tool":"trace.read","field":"result","note":"Findings and failures preserved; full child observations remain in the archived receipt. Use path=/findings/N/receipts/M/result to read one observation."}
		return compact
	var preview: Dictionary = trim(value)
	if JSON.stringify(preview).length() > 24000:
		# Never discard status, errors, mutation facts or before/after silently.
		preview = {"call_id":value.get("call_id",""),"name":value.get("name",""),"status":value.get("status",""),"errors":value.get("errors",[]),"failure":value.get("failure",{}),"submitted":value.get("submitted",false),"mutates_world":value.get("mutates_world",false),"evidence":value.get("evidence",""),"result_preview":JSON.stringify(value.get("result",{})).left(5000),"before_after_retained_in_archive":true}
	preview["pruned"] = true
	preview["full_receipt"] = {"call_id":value.get("call_id",""),"tool":"trace.read","note":"Full arguments, before/after, errors and results are retained in this chat. Read pages or the relevant targeted tool before making numerical claims or edits."}
	return preview
