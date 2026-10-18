extends RefCounted
## Native correspondence and deal controls; never turns an agreement into an order.
const Sources=preload("res://mods/pax_harness/src/data/world_sources.gd")
const Data=preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const NAMES=["diplomacy.offers","diplomacy.exchange","diplomacy.accept_offer"]
static func available(game: RefCounted,name: String) -> bool:
	var main: Node=Sources.main_node(game)
	if main==null or not main.has_method("letters"): return false
	var letters: Variant=main.letters()
	if not letters is Object or not letters.has_method("write"): return false
	return letters.has_method("offer_exchange") if name=="diplomacy.exchange" else letters.has_method("accept_offer") if name=="diplomacy.accept_offer" else name=="diplomacy.offers"
static func revision(offer: Dictionary) -> String:
	return JSON.stringify(Data.clean(offer)).sha256_text() if not offer.is_empty() else ""
static func mechanical(offer: Dictionary) -> bool:
	var deal: Variant=offer.get("deal",{})
	if not deal is Dictionary: return false
	return (deal.get("we_give") is Dictionary and not deal.we_give.is_empty()) or (deal.get("they_give") is Dictionary and not deal.they_give.is_empty()) or str(deal.get("treaty",""))!=""
static func snapshot(game: RefCounted,main: Node,faction: Dictionary) -> Dictionary:
	return {"day":game.day(),"country":str(faction.get("name","")),"body":game.home_body(),"our_stock":Data.clean(main.model.resources.stock(game.home_body())),"their_stock":Data.clean(faction.get("stock",{})),"their_money":faction.get("money",0),"treaty":str(faction.get("treaty","")),"offer":Data.clean(faction.get("offer",{})),"order_count":main.model.orders.size()}
static func execute(game: RefCounted,name: String,args: Dictionary) -> Dictionary:
	var main: Node=Sources.main_node(game)
	if not available(game,name) or main==null: return Data.failed("diplomacy.exchange_unavailable")
	var country: String=str(args.get("country",""))
	if country not in game.countries(): return Data.failed("tools.country_not_found")
	var faction: Dictionary=main.model.factions_sim.find_(country)
	if faction.is_empty() or faction.get("ours",false): return Data.failed("tools.country_not_found")
	var before: Dictionary=snapshot(game,main,faction)
	var offer: Dictionary=faction.get("offer",{}).duplicate(true)
	var pending: bool=main.player._waiting_faction.has(country)
	if name=="diplomacy.offers":
		var history: Array=Data.clean(faction.get("correspondence",[])); history.reverse()
		var offset: int=maxi(0,int(args.get("offset",0))); var limit: int=clampi(int(args.get("limit",20)),1,50)
		return Data.success({"country":country,"offer":Data.clean(offer),"offer_revision":revision(offer),"mechanical_deal_available":mechanical(offer),"reply_pending":pending,"player_offer":Data.clean(faction.get("player_offer",{})),"correspondence":history.slice(offset,offset+limit),"total":history.size(),"has_more":offset+limit<history.size(),"next_offset":mini(history.size(),offset+limit),"history_order":"newest_first","current":before,"note":"Dialogue and order_cmd are not a deal. Only offer.deal can be accepted with diplomacy.accept_offer. A counteroffer changes the terms; obtain player authorization before accepting changed terms."})
	var api: Node=main.get_tree().root.get_node_or_null("Pax") if main.is_inside_tree() else null
	if api!=null and api.has_method("world_busy") and api.call("world_busy"): return Data.failed("diplomacy.world_busy",before,before)
	if pending: return Data.failed("diplomacy.reply_pending",before,before)
	if main.rewind_state.rewinding: return Data.failed("tools.time_jump_active",before,before)
	if name=="diplomacy.exchange":
		for key: String in ["give_amount","receive_amount"]:
			if not Data.number(args.get(key)) or not is_finite(float(args[key])) or float(args[key])!=floorf(float(args[key])) or args[key]<1 or args[key]>1000000000000: return Data.failed("diplomacy.invalid_amount")
		for key: String in ["give_resource","receive_resource"]:
			if not args.get(key) is String or (not before.our_stock.has(args[key]) and not before.their_stock.has(args[key]) and args[key]!="money"): return Data.failed("diplomacy.unknown_resource")
		if args.give_resource==args.receive_resource: return Data.failed("diplomacy.same_resource")
		if float(before.our_stock.get(args.give_resource,0))<float(args.give_amount): return Data.failed("diplomacy.insufficient_stock",before,before)
		var old_count: int=faction.get("correspondence",[]).size()
		main.letters().offer_exchange(country,args.give_resource,int(args.give_amount),args.receive_resource,int(args.receive_amount))
		var after: Dictionary=snapshot(game,main,faction)
		var outgoing: Array=faction.get("correspondence",[]).slice(old_count).filter(func(row: Dictionary): return row.get("from")=="we")
		if outgoing.is_empty(): return Data.failed("diplomacy.exchange_not_submitted",before,after)
		return Data.success({"letter_submitted":true,"structured_exchange_proposed":not faction.get("player_offer",{}).is_empty(),"reply_pending":main.player._waiting_faction.has(country),"completed":false,"instruction":"Read diplomacy.offers after the actual reply. A proposal is not an executed trade; do not submit an order as a substitute."},before,after,true)
	if name!="diplomacy.accept_offer": return Data.failed("tools.unknown_tool")
	if not mechanical(offer): return Data.failed("diplomacy.no_mechanical_offer",before,before)
	if str(args.get("expected_offer_revision",""))!=revision(offer): return Data.failed("diplomacy.offer_changed_read_again",before,before)
	# Multiplayer settlements need separate remote confirmation; never infer it
	# from local offer removal. This adapter currently handles AI-country offers.
	if main.model.factions_sim.under_player(faction): return Data.failed("diplomacy.multiplayer_confirmation_required",before,before)
	main.letters().accept_offer(country)
	var after: Dictionary=snapshot(game,main,faction)
	var removed: bool=after.offer.is_empty() or after.offer.get("deal",{}).is_empty()
	var changed: bool=before.our_stock!=after.our_stock or before.their_stock!=after.their_stock or before.their_money!=after.their_money or before.treaty!=after.treaty
	if not removed or not changed: return Data.failed("diplomacy.deal_not_verified",before,after)
	if offer.deal.get("treaty","")=="trade" and after.treaty!="trade": return Data.failed("diplomacy.deal_not_verified",before,after)
	var deltas: Dictionary={}; var resources: Dictionary=offer.deal.get("we_give",{}).duplicate()
	resources.merge(offer.deal.get("they_give",{}),true)
	for resource: String in resources:
		var expected: float=float(offer.deal.get("they_give",{}).get(resource,0))-float(offer.deal.get("we_give",{}).get(resource,0))
		var actual: float=float(after.our_stock.get(resource,0))-float(before.our_stock.get(resource,0))
		deltas[resource]={"expected":expected,"actual":actual}
		if not is_equal_approx(expected,actual): return Data.failed("diplomacy.deal_not_verified",before,after)
	return Data.success({"completed":true,"engine_deal_applied":true,"accepted_deal":Data.clean(offer.deal),"verified_stock_deltas":deltas,"order_created":after.order_count!=before.order_count,"instruction":"Report actual stock/treaty changes from before/after. Do not execute the separate order_cmd: this action accepted only the engine deal."},before,after)
