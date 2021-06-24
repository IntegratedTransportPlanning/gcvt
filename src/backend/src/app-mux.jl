@enum FlowDirection Incoming Outgoing

using Base.Iterators: product
using Statistics
using OrderedCollections: OrderedDict

# Yes I know we have JSON3 too but programmer time is valuable
# JSON3.read puts it in a weird Dict rather than the bog standard Dict{String}
using JSON
using TOML


#const DATA_ROOT = joinpath(@__DIR__, "../data/")
const DATA_ROOT = get(ENV, "ITO_OD_DATA_ROOT", joinpath(@__DIR__, "../testdata/processed"))

# Environment variables
const IN_PRODUCTION = get(ENV, "ITP_OD_PROD", "0") == "1"
#const SCHEMA_PATH = get(ENV, "ITP_OD_SCHEMA_PATH", "pct_meta.toml")
const SCHEMA_PATH = get(ENV, "ITP_OD_SCHEMA_PATH", "../testdata/processed/TEST_PROJECT_PLEASE_IGNORE_KYIV/schema.toml")
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
    return Iterators.map(getfield(data, grouptype)) do grp
        sources = grp[!, sourcecol]
        col = grp[!, col_idx]
        gen = (v for (o, v) in zip(sources, col) if o in zones)
        reduce(+, gen; init = zero(eltype(col))) # From Julia 1.6+ we can use sum(...; init = ...)
    end |> collect
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

import Turf
import GeoJSON

function load_centroids(meta)
    # TODO: support multiple geometries
    #           (a fairly big job - would need another rewrite of the frontend)
    #           (presumably fairly low priority as we can just have multiple projects?)
    
    geo = meta["geometries"][1]
    # NB: most of the slowness is this call here V
    zones = GeoJSON.parsefile(joinpath(DATA_ROOT, geo["filename"]))

    zone_centroids = Dict()
    for f in zones.features
        zone_centroids[f.properties["CORRIDOR_FEATID"]] = Turf.centroid(f.geometry).coordinates
    end
    return zone_centroids
end

include("ODData.jl")
using CSV
function load_data(meta)
    for f in meta["files"]
        # TODO: support multiple files
        df = CSV.read(
            joinpath(DATA_ROOT, f["filename"]),
            DataFrame; missingstring="NA",
        )
        column_names = map(d->d["name"], f["columns"])

        df = df[!, ["CORRIDOR_ORIGIN", "CORRIDOR_DESTINATION", column_names...]]

        # TODO: rename columns rather than store duplicates
        df[!, :origin] = df[!, 1]
        df[!, :destination] = df[!, 2]

        df = df[!, ["origin", "destination", column_names...]]

        # TODO: support multiple files
        return ODData(df, meta)
    end
    # using Test

    # function tests()
    #     # Some simple regression tests.
    #     # Data was manually checked against the CSV, too.
    #     pct_odd = load_data(meta) # PCT stuff

    #     @test pct_odd["all"] |> collect == pct_odd["all", nothing]
    #     @test pct_odd["all", nothing, 3] == [4, 1]
    #     @test pct_odd["all", nothing, :, 202] == [1, 1, 3, 1, 3, 4, 2, 5, 4, 1, 133]

    #     # Get an empty vector when asking for missing data
    #     @test isempty(pct_odd["all", nothing, 500])
    #     @test isempty(pct_odd["all", nothing, :, 1])

    #     # Works for a variable with a named scenario
    #     @test length(collect(pct_odd["slc"])) ÷ length(pct_odd["slc", "govtarget"]) == 5
    #     pct_odd["slc", "govtarget"]
    #     @test pct_odd["slc", "govtarget", 3] == [0.03, 0.01]
    #     @test pct_odd["slc", "govtarget", :, 202] == [0.01, 0.01, 0.02, 0.01, 0.03, 0.03, 0.02, 0.04, 0.03, 0.01, 5.24]
    # end
end

# DATA
# TODO: consider squashing the files array
#       (currently the frontend deals with it which is kinda strange)
metadata = TOML.parsefile(SCHEMA_PATH)

data = load_data(metadata)
# Slightly slow V
zone_centroids = load_centroids(metadata)


##### TODO

# Tidy this up
# (maybe cache it if it's slow?)

## Want to work out how to replicate scenarios_with from JS
## Should _probably_ offload it to Julia? Don't want to care about files/columns here
##
## So want a set of valid combinations of dependent variables (always 1: it's the colour on the map) and IVs
## then hold dependent value & all but one IV fixed and see what other IVs fixed

DEPS_TO_DOMAIN = Dict{String,Array{Any,1}}()
for arr in metadata["files"]
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

import VegaLite

VegaLite.actionlinks(false) # Global setting - disable action button on all plots


# Adapted from VegaLite.jl
function vegalite_to_html(vl;title="Corridors plot",width=200,height=200)
    spec = VegaLite.convert_vl_to_vg(vl)
    """
      <html>
        <head>
          <title>$title</title>
          <meta charset="UTF-8">
          <script src="https://cdnjs.cloudflare.com/ajax/libs/vega/5.6.0/vega.min.js"></script>
          <script src="https://cdnjs.cloudflare.com/ajax/libs/vega-embed/5.1.2/vega-embed.min.js"></script>
        </head>
        <body>
          <div id="gcvt-chart"></div>
        </body>
        <style media="screen">
          body, #gcvt-chart {
            padding: 0;
            margin: 0;
          }
          .vega-actions a {
            margin-right: 10px;
            font-family: sans-serif;
            font-size: x-small;
            font-style: italic;
          }
        </style>
        <script type="text/javascript">
          var opt = {
            mode: "vega",
            renderer: "svg",
            actions: $(VegaLite.actionlinks())
          }
          var spec = $spec
          vegaEmbed('#gcvt-chart', spec, opt).then(function(error, result){ // Resize SVG
              document.querySelector("#gcvt-chart > svg").setAttribute("width",$width);
              document.querySelector("#gcvt-chart > svg").setAttribute("height",$height);
          });
        </script>
      </html>
    """
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
            vs = get_aggregate_flows(data, variable, independent_variables, :incoming, split(d["row"], ','))
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
    #route("/charts", req -> begin
    #    # TODO: consider whether this actually makes sense
    #    # how can we stop it from being too magic?
    #    #
    #    # user needs to pick which IV is going to be plotted
    #    # and fix all others

    #    d = queryparams(req)

    #    # Legacy-compat
    #    scenario = get(d, "scenario", "")
    #    comparewith = get(d, "comparewith", "")
    #    variable = get(d, "variable", "")

    #    # New bits
    #    selectedvars = JSON.parse(get(d,"selectedvars","{}"))
    #    selectedbasevars = JSON.parse(get(d,"selectedbasevars","{}"))
    #    variable = get(selectedvars,"dependent_variable",variable)
    #    independent_variables = get(selectedvars,"independent_variables",Dict("scenario"=>scenario))
    #    base_independent_variables = get(selectedbasevars,"independent_variables",Dict("scenario"=>comparewith))
    #    ivtoplot = get(d,"ivtoplot","year")

    #    # Legacy-compat
    #    comparewith = get(get(selectedbasevars, "independent_variables", Dict()), "scenario", comparewith)

    #    d["rows"] = d["rows"] == "all" ? Colon() : parse.(Int, split(d["rows"], ","))

    #    scenarios = split(d[:scenarios], ",")
    #    # All years that any selected scenario has data for
    #    years = sort(unique(vcat((metadata["scenarios"][s]["at"] for s in scenarios)...)))

    #    datafnc = d[:domain] == "links" ? link_data : mat_data
    #    df = DataFrame(year=String[], val=[], scenario=String[])

    #    const x_axis = metadata["independent_variables"][#=find the right id=#]["values"] # might be numbers, might need mapping to ids
    #    for year in years # for x in x_axis
    #        for scenario in scenarios # for thingy in [selectedvars,selectedbasevars]
    #            # something like this V
    #            value = sum(datafnc(scenario, year, d[:variable])[d[:rows], :])
    #            # ... don't bother with this V for now
    #            scenario_name = get(metadata["scenarios"][scenario], "name", scenario)

    #            # year -> x, scenario -> ... dunno, like notbase / base. Base / Treatment?
    #            push!(df, (year = string(year), val = value, scenario = scenario_name))
    #        end
    #    end

    #    width = parse(Int, d["width"])
    #    height = parse(Int, d["height"])
    #   #unit = get(metadata[d[:domain]]["columns"][d[:variable]], "unit", d[:variable])
    #    vl = df |> VegaLite.@vlplot(
    #        # Awful heuristic - these control size of plot excluding legend, labels etc
    #        width = width * .8,
    #        height = height * .5,

    #        mark = {
    #            :line,
    #            point = { filled = false,fill = :white },
    #        },
    #        color = {
    #            :scenario,
    #            legend = {
    #                title = nothing,
    #                orient = width < 500 ? :bottom : :right,
    #            },
    #        },
    #        x = {
    #            :year,
    #            title = "Year",
    #            type = "temporal"
    #        },
    #        y = {
    #            :val,
    #            title = "",#unit,
    #            type = "quantitative",
    #            axis = {
    #                formatType = "number",
    #                format = ".3~s",
    #            },
    #        },
    #    )
    #    vegalite_to_html(vl; width=width, height=height)
    #end,

    Mux.notfound()
)

println("Serving $SCHEMA_PATH backend on port $PORT...")
IN_PRODUCTION && wait(
    serve(app, PORT)
)
