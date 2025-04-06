#= using Genie =#

module tmp

const API_VERSION = "0.0.2" # Change this to invalidate HTTP cache

import Genie
using Genie.Router: route, @params
using Genie.Requests: getpayload

# Generates HTML responses
using Genie.Renderer: html

using Memoize: @memoize
using ProgressMeter: @showprogress

using Base.Iterators: flatten, product
using Statistics

import HTTP
import GeoJSON
import Turf
import VegaLite

VegaLite.actionlinks(false) # Global setting - disable action button on all plots

# This converts its argument to json and sets the appropriate headers for content type
# We're customising it to set the CORS header
json(data; status::Int = 200) =
    Genie.Renderer.json(data; status = status, headers = Dict(
        "Access-Control-Allow-Origin" => "*",
        #"Cache-Control" => "public, max-age=$(365 * 24 * 60 * 60)", # cache for a year (max recommended). Change API_VERSION to invalidate
        "Cache-Control" => "max-age=0",
    ))

Genie.config.session_auto_start = false
# Default headers are supposed to go here, but they don't seem to work.
#= Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*" =#

# Test route
route("/") do
    json(Dict("Answer" => 42))
end

# Used solely to invalidate caches - increment API_VERSION if you need to do so
route("/version") do
    Genie.Renderer.json(Dict("version" => API_VERSION); status = 200, headers = Dict(
        "Access-Control-Allow-Origin" => "*",
        "Cache-Control" => "max-age=0", # Don't cache 
    ))
end


### APP ###


## State (all constant)

include("$(@__DIR__)/scenarios.jl")

const zones = GeoJSON.parsefile("$(@__DIR__)/../data/geometry/zones.geojson")

const zone_centroids = Array{Array{Float64,1},1}(undef,length(zones.features))
for f in zones.features
    zone_centroids[f.properties["fid"]] = Turf.centroid(f.geometry).coordinates
end

const NUM_ZONES = zone_centroids |> length

# This should probably be reloaded periodically so server doesn't need to be restarted?
const links, mats, metadata = load_scenarios(packdir)

const NUM_LINKS = (links |> first)[2] |> size |> first


## Funcs


# Get list of scenarios (scenario name, id, years active)
list_scenarios() = metadata["scenarios"]

# Get list of variable names and ids
function list_variables(domain)
    if domain == "links"
        metadata["links"]["columns"]
    elseif domain == "od_matrices"
        metadata["od_matrices"]["columns"]
    else
        throw(DomainError(domain, "is invalid"))
    end
end

function mat_data(scenario, year, variable)
    try
        mats[(scenario, year)][variable]
    catch e
        if e isa KeyError
            @warn e
            return fill(missing, NUM_ZONES, NUM_ZONES)
        else
            rethrow()
        end
    end
end

function link_data(scenario, year, variable)
    try
        links[(scenario, year)][!, Symbol(variable)]
    catch e
        if e isa KeyError
            @warn e
            return fill(missing, NUM_LINKS)
        else
            rethrow()
        end
    end
end

const a2d(arr) = Dict(enumerate(arr))

# Get colour to draw each shape for (scenario, year, variable, comparison scenario, comparison year) -> (colours)
mat_comp(args...; kwargs...) = comp(mat_data, args...; kwargs...)
link_comp(args...; kwargs...) = comp(link_data, args...; kwargs...)
function comp(data, scenario, year, variable, comparison_scenario, comparison_year;percent=true)

    main = data(scenario, year, variable)
    comparator = data(comparison_scenario, comparison_year, variable)

    # dims = 2 sums rows; dims = 1 sums cols
    # Returns Array{Float,2} but we want Array{Float,1} so we flatten it
    if percent
        # Avoid NaN from dividing by zero.
        # Skip missing values here because we don't want eps to be `missing`
        # and poison every value.
        eps = mean(sum(skipmissing(vec(main)))) / 10000

        result = (sum(main, dims = 2) .+ eps) ./ (sum(comparator, dims = 2) .+ eps) .- 1
    else
        result = sum(main .- comparator, dims = 2)
    end

    return collect(flatten(result))
end

"""
    var_stats(domain, variable, quantiles, percent=false)

Return quantiles to use when comparing `variable` between scenarios.

We approximate the quantiles for all pair-wise differences with this algorithm:

1. Compute the element-wise difference between each pair of scenarios for the
given `domain` and `variable`
2. sample from these differences to create a vector of differences
3. return the quantiles of the sampled vector
"""
# This is expensive, so it is memoized and the cache is warmed up before the
# webserver starts.
@memoize function var_stats(domain, variable, quantiles, percent=false)
    vars = []
    if domain == "od_matrices"
        vars = [scen[variable] for scen in values(mats)]
    elseif domain == "links"
        vars = [df[!, Symbol(variable)] for df in values(links)]
    end

    # Choose what type of diff to calculate.
    function percent_diff(l, r)
        # dims = 2 sums rows; dims = 1 sums cols
        eps = mean(sum(vars[l], dims = 2)) / 10000
        result = (sum(vars[l], dims = 2) .+ eps) ./ (sum(vars[r], dims = 2) .+ eps) .- 1
    end
    function absolute_diff(l, r)
        vars[l] .- vars[r]
    end
    diff = percent ? percent_diff : absolute_diff

    # Sample the differences between the values of this variable for each pair
    # of scenarios.
    pairs = product(1:length(vars), 1:length(vars))
    diffs = [rand(diff(a, b), 10000) for (a, b) in pairs]

    return quantile(flatten(vcat(diffs...)), quantiles)
end

"""
    var_stats_1d(domain, variable, quantiles)

Collect all values for `variable` from all scenarios in `domain` into a vector
and return the quantiles of that vector.

This is a bit expensive, so it is memoized.
"""
# memoized functions can't have docstrings - don't delete this comment
@memoize function var_stats_1d(domain, variable, quantiles)
    # dims = 2 sums rows; dims = 1 sums cols
    vars = []
    if domain == "od_matrices"
        vars = [get(v,variable,[]) for (k,v) in mats]
    elseif domain == "links"
        vars = [get(v,Symbol(variable),[]) for (k,v) in links]
    end
    vcat(vars...) |> flatten |> x -> quantile(x,quantiles)
end

"Given a pair of variable_name => meta, return true if it should be used"
is_used((name, meta)) = get(meta, "use", true)

# println("Warming up the cache: links")
# @showprogress for variable in keys(filter(is_used, list_variables("links")))
#     # get these quantiles from colourMap in index.js
#     var_stats("links", variable, (0.1, 0.9))
#     var_stats("links", variable, (0.05, 0.95), true)
# end
# 
# println("Warming up the cache: matrices")
# @showprogress for variable in keys(filter(is_used, list_variables("od_matrices")))
#     # get these quantiles from colourMap in index.js
#     var_stats("od_matrices", variable, (0.0001, 0.9999))
#     var_stats("od_matrices", variable, (0.05, 0.95), true)
# end


## Routes


route("/scenarios") do
    list_scenarios() |> json
end

route("/variables/:domain") do
    list_variables(@params(:domain)) |> json
end

# Return a vector: [low_quantile, high_quantile]
route("/stats") do
    # Was removed this in ac81797 but is 'needed' below
    defaults = Dict(
        :domain => "od_matrices",
        :comparewith => "DoMin",
        :variable => "Total_GHG",
        :percent => "true",
        :quantiles => "0.0001,0.9999",  # These default percentiles seem v. generous
                                        # but we look at all possible differences
                                        # so overwhelming majority of differences are
                                        # tiny. Seems to work OK in practice.
    )
    d = merge(defaults, getpayload())
    quantiles = parse.(Float64,split(d[:quantiles],","))
    if d[:domain] in ["od_matrices", "links"]
        d[:comparewith] != "none" && return var_stats(d[:domain],d[:variable],Tuple(quantiles),d[:percent]=="true") |> json
        # TODO: If metadata holds the quantiles return them here below
        return var_stats_1d(d[:domain],d[:variable],Tuple(quantiles)) |> json
    else
        throw(DomainError(:domain))
    end
end

# Return a vector of data, usually floats, for the requested scenario,
# comparison parameters, and so on.
route("/data") do
    defaults = Dict(
        :domain => "od_matrices",
        :scenario => "Rail",
        :year => "2030",
        :comparewith => "DoMin",
        :compareyear => "auto",
        :variable => "Total_GHG",
        :percent => "true",
        :row => "false",
    )
    d = merge(defaults, getpayload())
    scenario = d[:scenario]
    year = parse(Int, d[:year])
    variable = d[:variable]
    compareyear = d[:compareyear] == "auto" ? year : parse(Int, d[:compareyear])
    percent = d[:percent] == "true"
    comparewith = d[:comparewith]

    if d[:domain] == "od_matrices"
        if d[:row] != "false"
            rows = parse.(Int,split(d[:row],','))
            sum([mat_data(scenario, year, variable)[row,:] for row in rows])
        elseif d[:comparewith] == "none"
            reshape(sum(mat_data(scenario, year, variable), dims = 2), :)
        else
            mat_comp(scenario, year, variable,
                     comparewith, compareyear, percent=percent)
        end
    elseif d[:domain] == "links"
        if d[:comparewith] == "none"
            link_data(scenario, year, variable)
        else
            link_comp(scenario, year, variable,
                      comparewith, compareyear, percent=percent)
        end
    else
        throw(DomainError(d[:domain]))
    end |> a2d |> json
end

route("/centroids") do
    zone_centroids |> json
end

# Want to provide:
# Zone name
# Absolute change
# Relative change
#= route("/data/popup/:zone") do =#
#=     d = getpayload() =#
#=     json(d[:zone]) =#
#= end =#

route("/oembed") do
    defaults = Dict(
        :maxwidth => 100,
        :maxheight => 100,
        :format => "json"
       )
    params = merge(defaults, getpayload())
    @assert haskey(params, :url)

    json(Dict(
        :type => "rich",
        :version => 1.0,
        # TODO: manipulate the src line to add parameters if required.
        # HTTP.URI has some code for this.
        # TODO: sanitise arguments?
        # Should check that domain and port are right
        # Shouldn't allow insertion of arbitrary HTTP
        :html => "<iframe src=$(HTTP.unescapeuri(params[:url])) width=$(params[:maxwidth]) height=$(params[:maxheight])></iframe>",
        :width => params[:maxwidth],
        :height => params[:maxheight],
        :provider_name => "Integrated Transport Planning",
        :provider_url => "https://www.itpworld.net/",
       ))
end

# Adapted from VegaLite.jl
function vegalite_to_html(vl;title="Greener Connectivity Plot",width=200,height=200)
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

# TODO:
# display units
# sensible ticks for years
#
# Usage:
# E.g. http://localhost:2016/api/charts?scenarios=Rail,Fleet,DoNothing&width=300&height=300
# Probably embed in an iframe
route("/charts") do
    defaults = Dict(
        :domain => "od_matrices",
        :scenarios => "Rail,DoMin",
        :variable => "Total_GHG",
        :rows => "all", # Unused
        :width => "200",
        :height => "200",
    )
    d = merge(defaults, getpayload())
    d[:rows] = d[:rows] == "all" ? Colon() : parse.(Int, split(d[:rows], ","))

    scenarios = split(d[:scenarios], ",")
    # All years that any selected scenario has data for
    years = sort(unique(vcat((metadata["scenarios"][s]["at"] for s in scenarios)...)))

    datafnc = d[:domain] == "links" ? link_data : mat_data
    df = DataFrame(year=String[], val=[], scenario=String[])
    for year in years
        for scenario in scenarios
            value = sum(datafnc(scenario, year, d[:variable])[d[:rows], :])
            scenario_name = get(metadata["scenarios"][scenario], "name", scenario)
            push!(df, (year = string(year), val = value, scenario = scenario_name))
        end
    end

    width = parse(Int, d[:width])
    height = parse(Int, d[:height])
    unit = get(metadata[d[:domain]]["columns"][d[:variable]], "unit", d[:variable])
    vl = df |> VegaLite.@vlplot(
        # Awful heuristic - these control size of plot excluding legend, labels etc
        width = width * .8,
        height = height * .5,

        mark = {
            :line,
            point = { filled = false,fill = :white },
        },
        color = {
            :scenario,
            legend = {
                title = nothing,
                orient = width < 500 ? :bottom : :right,
            },
        },
        x = {
            :year,
            title = "Year",
            type = "temporal"
        },
        y = {
            :val,
            title = unit,
            type = "quantitative",
            axis = {
                formatType = "number",
                format = ".3~s",
            },
        },
    )
    vegalite_to_html(vl; width=width, height=height)
end

Genie.AppServer.startup(parse(Int,get(ENV,"GENIE_PORT", "8000")),"0.0.0.0", async = false)


end
