@enum FlowDirection Incoming Outgoing

"""
    get_aggregate_quantiles(data, variable, p, direction::FlowDirection)

Compute the aggregated flows in `direction` for `variable` and compute the quantiles of those flows.
`p` is a vector of the probabilities at which to calculate the quantiles (see `Statistics.quantile`).

Motivation: chloropleth view.
"""
function get_aggregate_quantiles(data, variable, p, direction::FlowDirection)
end

"""
    get_aggregate_quantiles(data, variable, p, comparison::Bool, percent::Bool, direction::FlowDirection)

Sample the pairwise comparisons between all scenarios featuring `variable` and compute the sample quantiles.
`p` is a vector of the probabilities at which to calculate the quantiles (see `Statistics.quantile`).

Motivation: comparison chloropleth view.
"""
function get_aggregate_quantiles(data,
                                 variable,
                                 p,
                                 comparison::Bool,
                                 percent::Bool,
                                 direction::FlowDirection)
end

"""
    get_quantiles(data, variable, p)

Return the quantiles for all values of `variable`.
`p` is a vector of the probabilities at which to calculate the quantiles (see `Statistics.quantile`).

Motivation: used for scaling flow lines (and, in GCVT, link lines).
"""
function get_quantiles(data, variable, p)
end

"""
   get_aggregate_flows(data, variable, scenario, direction)

Aggregated (always summed?) flows for all zones. Returns an iterable of pairs (zone_id => flow_amount), maybe a Dict.

Motivation: chloropleth view.
"""
function get_aggregate_flows(data, variable, scenario, direction)
end

"""
   get_aggregate_flows(data, variable, scenario, direction, comparison_scenario, percent::Bool)

Compare the aggregate flows for each zone for the given variable in the two scenarios.
Returns an iterable of pairs (zone_id => difference_in_flows), maybe a Dict.

If `percent` is true, compute the percentage difference in aggregate flow, otherwise compute the absolute difference.

Motivation: comparison chloropleth view.
"""
function get_aggregate_flows(data, variable, scenario, direction, comparison_scenario, percent::Bool)
end

"""
    get_top_flows(data, variable, scenario, zone, direction, top)

Return the top flows from/to `zone` for the specified variable and scenario.
`[top_zone1 => flow1, top_zone2 => flow2, ...]`

`top` is an integer (top N flows) or maybe a float `top % of flows?`

Motivation:
 - to show flow lines for one zone, we need to know the top N flows from/to that zone.
 - to show flow lines for several zones, we want to see the top N flows from/to each zone in the selection

TODO:
 - What would comparison mode look like here?
"""
function get_top_flows(data, variable, scenario, zone, direction)
end

"""
    get_centroids(x)

Return centroids for each zone. `[zone1_centroid, zone2_centroid, ...]`
"""
function get_centroids(x)
end

"""
    get_zone_info(x)

Get some info for a popup or whatever.
"""
function get_zone_info end # unimplemented


using Mux

@app app = (
    Mux.defaults,
    route("/", debug_page), # some kind of debug page or API help page
    # need to pick some route names
)
