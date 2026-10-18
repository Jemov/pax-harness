# Geography providers

`charts.map` supports a general, read-only water-cover view in every loaded scenario:

```json
{"include_water":true,"bounds":[-7,29,40,46],"type":"choropleth"}
```

Bounds are `[west,south,east,north]` in degrees, describing a viewport rather than a claimed shoreline. The tool samples the current planet's native water/province raster, including mod edits. It never searches for a hard-coded lake name or loads another planetary map. For a non-home body, open its map in the game first. Wide views may aggregate land; grid step and aggregation are reported. Display the returned `display_ref` instead of sending polygons back through the model.

Mods can expose their own named features, worlds and geometry through the existing APIs:

```gdscript
var harness = Pax.get_mod("pax_harness")
if harness != null:
    harness.register_analytics_source(
        "my_mod.geography", "My geography", "Named features and their map provider",
        {"type":"object","properties":{},"additionalProperties":false}, read_features)
    harness.register_map_source("my_mod.map", "My world map", "My body", read_map)
```

`read_features(game, parameters, page)` returns `{rows:[],source:"...",has_more:false}` with bounded rows. Include stable feature IDs, aliases, provenance/confidence and the map-provider ID. A paginated response with more rows must include `next_offset` greater than the requested offset.

`read_map(game, arguments)` returns `{ok:true,result:{chart:...}}` using a valid choropleth/cartogram/symbol_map/flow_map specification. `charts.map` forwards `feature_ids` to the provider. Geography remains numeric data, limited by the chart schema and 256 KiB callback limit. No script, remote URL or executable content is accepted. A mod may also delegate to the generic live-raster view with `harness.map_provider_tool("charts.map", {include_water:true,bounds:...,body:...})`, omitting `provider` to avoid recursion.

Release callbacks when their world is no longer active:

```gdscript
harness.unregister_map_source("my_mod.map", read_map)
harness.unregister_analytics_source("my_mod.geography", read_features)
```

Unregistration requires the same reader Callable, so an older instance cannot remove a replacement's registration. Dead readers can be replaced on registration. Province-contour caching includes the native map version; mods changing raster geometry should increment it.

Для отображения воды не требуется отдельный адаптер под конкретный сценарий. Адаптер нужен только для имён и собственных данных мода: он передаёт идентификаторы, координаты, источник и геометрию по общему договору. При выключении мира удаляйте свои обработчики указанными выше методами. Полные полигоны сохраняются в локальной квитанции инструмента; агенту передаётся краткое описание и ссылка для показа.
