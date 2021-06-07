@enum FlowDirection Incoming Outgoing

using Base.Iterators: product
using Statistics

# Yes I know we have JSON3 too but programmer time is valuable
# JSON3.read puts it in a weird Dict rather than the bog standard Dict{String}
using JSON


# Environment variables
const IN_PRODUCTION = get(ENV, "ITP_OD_PROD", "0") == "1"
const SCHEMA_PATH = get(ENV, "ITP_OD_SCHEMA_PATH", "pct_meta.toml")
const PORT = parse(Int,get(ENV, "ITP_OD_BACKEND_PORT", "2017"))

# Change this to invalidate HTTP cache
const API_VERSION = IN_PRODUCTION ? "0.0.2" : rand(['a':'z'..., string.(0:9)...], 4) |> join


"""
    get_aggregate_quantiles(data, variable, p, direction::FlowDirection)

Compute the aggregated flows in `direction` for `variable` and compute the quantiles of those flows.
`p` is a vector of the probabilities at which to calculate the quantiles (see `Statistics.quantile`).

Motivation: chloropleth view.
"""
function get_aggregate_quantiles(data, variable, p, direction)
    vars = mapreduce(vcat, columns_with(data, variable)) do column
        sum.(get_grouped(data, variable, column, direction))
    end
    return quantile(vars, p)
end

"""
    get_aggregate_comparison_quantiles(data, variable, p, direction, percent)

Sample the pairwise comparisons between all scenarios featuring `variable` and compute the sample quantiles.
`p` is a vector of the probabilities at which to calculate the quantiles (see `Statistics.quantile`).

Motivation: comparison chloropleth view.
"""
function get_aggregate_comparison_quantiles(data, variable, p, direction, percent)
    vars = map(columns_with(data, variable)) do column
        sum.(get_grouped(data, variable, column, direction))
    end

    function percent_diff(a, b)
        eps = mean(skipmissing(a)) / 10000
        @. (a + eps) / (b + eps) - 1
    end
    absolute_diff(a, b) = a .- b

    diff_fnc = percent ? percent_diff : absolute_diff

    # Sample the differences between the values of this variable for each pair
    # of scenarios.
    pairs = product(1:length(vars), 1:length(vars))
    diffs = skipmissing(reduce(vcat, rand(diff_fnc(vars[a], vars[b]), 10000) for (a, b) in pairs))

    return quantile(diffs, p)
end

"""
    get_quantiles(data, variable, p)

Return the quantiles for all values of `variable`.
`p` is a vector of the probabilities at which to calculate the quantiles (see `Statistics.quantile`).

Motivation: maybe used for scaling link colours and widths in GCVT?
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
function get_aggregate_flows(data, variable, independent_variables, direction, zones)
    scenario = independent_variables["scenario"]
    col_idx = column_name(data, variable, independent_variables)
    (grouptype, sourcecol) = direction == :incoming ? (:grouped_by_destination, :origin) : (:grouped_by_origin, :destination)
    return map(getfield(data, grouptype)) do grp
        sources = grp[!, sourcecol]
        col = grp[!, col_idx]
        gen = (v for (o, v) in zip(sources, col) if o in zones)
        reduce(+, gen; init = zero(eltype(col))) # From Julia 1.6+ we can use sum(...; init = ...)
    end
end

function get_aggregate_flows(data, variable, independent_variables, direction, ::Colon)
    column = column_name(data, variable, independent_variables)
    sum.(get_grouped(data, variable, column, direction))
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

##### TODO

# Tidy this up
# (maybe cache it if it's slow?)

## Want to work out how to replicate scenarios_with from JS
## Should _probably_ offload it to Julia? Don't want to care about files/columns here
##
## So want a set of valid combinations of dependent variables (always 1: it's the colour on the map) and IVs
## then hold dependent value & all but one IV fixed and see what other IVs fixed

DEPS_TO_DOMAIN = Dict{String,Array{Any,1}}()
for arr in metadata["newmeta"]["files"]
    for d in arr["columns"]
        if haskey(DEPS_TO_DOMAIN,d["dependent_variable"])
            push!(DEPS_TO_DOMAIN[d["dependent_variable"]],d["independent_variables"])
        else
            DEPS_TO_DOMAIN[d["dependent_variable"]] = [d["independent_variables"]]
        end
    end
end

function valid_ivs(dependent, independent_variables)
    filter(d -> issuperdict(d,independent_variables), DEPS_TO_DOMAIN[dependent]) 
end

#########


# This should probably be set from metadata?
QUANTILES = (0.1, 0.9)

# APP

import HTTP

using Mux
using JSON3

jsonresp(obj; headers = Dict()) = Dict(:body => String(JSON3.write(obj)), :headers => merge(Dict(
    "Content-Type" => "application/json",
    "Cache-Control" => IN_PRODUCTION ? "public, max-age=$(365 * 24 * 60 * 60)" : "max-age=0", # cache for a year (max recommended). Change API_VERSION to invalidate
), headers))

queryparams(req) = HTTP.URIs.queryparams(req[:query])

# Just a hack while the frontend still expects an array
function fill_up(dict)
    map(idx -> get(dict, idx, 0), 1:524)
end

@app app = (
    IN_PRODUCTION ? Mux.prod_defaults : Mux.defaults,
    page("/", req -> jsonresp(42)), # some kind of debug page or API help page
    # need to pick some route names
    #
    # Compatibility with GCVT:
    route("/version", req -> jsonresp(
        Dict("version" => API_VERSION);
        headers = Dict(
            "Cache-Control" => "max-age=0",
        )
    )),
    route("/centroids", req -> jsonresp(get_centroids())),
    route("/meta", req -> jsonresp(metadata)),

    # Dead
    route("/variables/od_matrices", req -> jsonresp(Dict())),
    route("/scenarios", req -> jsonresp(Dict())),

    route("/domain") do req
        d = queryparams(req)
        depvar = d["dependent_variable"]
        indvars = JSON.parse(get(d,"independent_variables","{}"))
        jsonresp(valid_ivs(depvar, indvars))
    end,
    route("/stats") do req
        d = queryparams(req)

        # Legacy-compat
        comparewith = get(d, "comparewith", "")
        variable = get(d, "variable", "")

        # New bits
        selectedvars = JSON.parse(get(d,"selectedvars","{}"))
        selectedbasevars = JSON.parse(get(d,"selectedbasevars","{}"))
        variable = get(selectedvars,"dependent_variable",variable)

        # Legacy-compat
        comparewith = get(get(selectedbasevars, "independent_variables", Dict()), "scenario", comparewith)

        if comparewith == "none"
            jsonresp(get_aggregate_quantiles(data, variable, QUANTILES, :incoming))
        else
            percent = get(d, "percent", "false") == "true"
            jsonresp(get_aggregate_comparison_quantiles(data, variable, QUANTILES, :incoming, percent))
        end
    end,
    route("/data") do req
        d = queryparams(req)

        # Legacy-compat
        scenario = get(d, "scenario", "")
        comparewith = get(d, "comparewith", "")
        variable = get(d, "variable", "")

        # New bits
        selectedvars = JSON.parse(get(d,"selectedvars","{}"))
        selectedbasevars = JSON.parse(get(d,"selectedbasevars","{}"))
        variable = get(selectedvars,"dependent_variable",variable)
        independent_variables = get(selectedvars,"independent_variables",Dict("scenario"=>scenario))
        base_independent_variables = get(selectedbasevars,"independent_variables",Dict("scenario"=>comparewith))

        # Legacy-compat
        comparewith = get(get(selectedbasevars, "independent_variables", Dict()), "scenario", comparewith)

        if haskey(d, "row")
            vs = get_aggregate_flows(data, variable, independent_variables, :incoming, parse.(Int, split(d["row"], ',')))
        elseif comparewith == "none"
            vs = get_aggregate_flows(data, variable, independent_variables, :incoming, :)
        else
            main = get_aggregate_flows(data, variable, independent_variables, :incoming, :)
            comparator = get_aggregate_flows(data, variable, base_independent_variables, :incoming, :)
            vs = main .- comparator
        end
        # Ordered for debugging reasons.
        fill_up(OrderedDict(zip(destinations(data), vs))) |> jsonresp
    end,
    Mux.notfound()
)

IN_PRODUCTION && wait(serve(app, PORT))
