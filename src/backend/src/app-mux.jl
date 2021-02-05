@enum FlowDirection Incoming Outgoing

using Statistics

"""
    get_aggregate_quantiles(data, variable, p, direction::FlowDirection)

Compute the aggregated flows in `direction` for `variable` and compute the quantiles of those flows.
`p` is a vector of the probabilities at which to calculate the quantiles (see `Statistics.quantile`).

Motivation: chloropleth view.
"""
function get_aggregate_quantiles(data, variable, p, direction)
    vars = mapreduce(vcat, scenarios_with(data, variable)) do scen
        sum.(get_grouped(data, variable, scen, direction))
    end
    return quantile(vars, p)
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
   get_aggregate_flows(data, variable, scenario, direction, zones)

Aggregated (always summed?) flows for all zones. Returns an iterable of pairs (zone_id => flow_amount), maybe a Dict.

Motivation: chloropleth view.

If `zones` is not `:`, only sum flows from/to those zones.

Motivation: chloropleth once you've selected one or more zones.
"""
function get_aggregate_flows(data, variable, scenario, direction, zones)
    col_idx = column_index(data, variable, scenario)
    if direction == :incoming
        # Sum only flows originating in `zones`
        return map(data.grouped_by_destination) do grp
            sum(filter(:origin => in(zones), grp)[!, col_idx])
        end
    else
        # Sum only flows ending in `zones`
        return map(data.grouped_by_origin) do grp
            sum(filter(:destination => in(zones), grp)[!, col_idx])
        end
    end
end

function get_aggregate_flows(data, variable, scenario, direction, ::Colon)
    sum.(get_grouped(data, variable, scenario, direction))
end

"""
   get_aggregate_flows(data, variable, scenario, direction, zones, comparison_scenario, percent::Bool)

Compare the aggregate flows for each zone for the given variable in the two scenarios.
Returns an iterable of pairs (zone_id => difference_in_flows), maybe a Dict.

If `percent` is true, compute the percentage difference in aggregate flow, otherwise compute the absolute difference.

Motivation: comparison chloropleth view.

If `zones` is not `:`, only sum flows from/to those zones.

Motivation: comparison chloropleth once you've selected one or more zones (new feature)
"""
function get_aggregate_flows(data, variable, scenario, direction, zones, comparison_scenario, percent::Bool)
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
function get_centroids()
    return zone_centroids
end

"""
    get_zone_info(x)

Get some info for a popup or whatever.

In the old code, we add new names to `zoneNames` in the config as new tiles are
loaded or removed. On the one hand, if we ever had loads and loads of zones,
that would be handy, on the other it triggers a lot of unnecessary events.
"""
function get_zone_info end


"""
    get_metadata(x)

Motivation:
 - client-side needs to draw some menus
 - need to know what scenarios each variable is in
 - want to know any custom units, palettes, scales, etc.
 - need to know default map position, scenario, variable, selection criteria, etc.
"""
function get_metadata end

# DATA
include("pct.jl")

data = load_pct_data()
metadata = load_pct_metadata(data)
zone_centroids = load_pct_centroids()

QUANTILES = (0.1, 0.9)

summed_incoming_flows(scenario, variable) = sum.(get_grouped(data, variable, scenario, :incoming))

# APP

import HTTP

using Mux
using JSON3

jsonresp(obj) = Dict(:body => String(JSON3.write(obj)), :headers => Dict("Content-Type" => "application/json"))

queryparams(req) = HTTP.URIs.queryparams(req[:query])

function fill_up(dict)
    map(idx -> get(dict, idx, 0), 1:524)
end

@app app = (
    Mux.defaults,
    page("/", req -> jsonresp(42)), # some kind of debug page or API help page
    # need to pick some route names
    #
    # Compatibility with GCVT:
    route("/centroids", req -> jsonresp(get_centroids())),
    route("/scenarios", req -> jsonresp(metadata["scenarios"])),
    route("/variables/od_matrices", req -> jsonresp(metadata["od_matrices"]["columns"])),
    route("/stats") do req
        d = queryparams(req)
        comparewith = d["comparewith"]
        variable = d["variable"]
        if comparewith != "none"
            jsonresp(get_aggregate_quantiles(data, variable, QUANTILES, :incoming))
        else
            # TODO change this
            jsonresp(get_aggregate_quantiles(data, variable, QUANTILES, :incoming))
        end
    end,
    route("/data") do req
        d = queryparams(req)
        scenario = d["scenario"]
        comparewith = d["comparewith"]
        variable = d["variable"]
        if haskey(d, "row")
            vs = get_aggregate_flows(data, variable, scenario, :incoming, parse.(Int, split(d["row"], ',')))
        elseif comparewith == "none"
            vs = get_aggregate_flows(data, variable, scenario, :incoming, :)
        else
            main = summed_incoming_flows(scenario, variable)
            comparator = summed_incoming_flows(comparewith, variable)
            vs = main .- comparator
        end
        # Ordered for debugging reasons.
        fill_up(OrderedDict(zip(destinations(data), vs))) |> jsonresp
    end,
    Mux.notfound()
)

serve(app, 2017)
