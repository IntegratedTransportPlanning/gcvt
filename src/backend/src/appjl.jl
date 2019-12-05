#= using Genie =#

module tmp

import Genie
using Genie.Router: route, @params
using Genie.Requests: getpayload

# Generates HTML responses
using Genie.Renderer: html

using Memoize: @memoize
using ProgressMeter: @showprogress

using Base.Iterators: flatten, product

import HTTP

import GeoJSON

import Turf

# This converts its argument to json and sets the appropriate headers for content type
# We're customising it to set the CORS header
json(data; status::Int = 200) =
    Genie.Renderer.json(data; status = status, headers = Dict("Access-Control-Allow-Origin" => "*"))

using Statistics

Genie.config.session_auto_start = false
# Default headers are supposed to go here, but they don't seem to work.
#= Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*" =#

route("/") do
    json("Hi there!")
end


### APP ###

include("$(@__DIR__)/scenarios.jl")

zones = GeoJSON.parsefile("$(@__DIR__)/../data/geometry/zones.geojson")

zone_centroids = Array{Array{Float64,1},1}(undef,length(zones.features))
for f in zones.features
    zone_centroids[f.properties["fid"]] = Turf.centroid(f.geometry).coordinates
end

# This should probably be reloaded periodically so server doesn't need to be restarted?
links, mats, metadata = load_scenarios(packdir)

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
    mats[(scenario, year)][variable]
end

function link_data(scenario, year, variable)
    links[(scenario, year)][Symbol(variable)]
end

# Get colour to draw each shape for (scenario, year, variable, comparison scenario, comparison year) -> (colours)
mat_comp(args...; kwargs...) = comp(mat_data, args...; kwargs...)
link_comp(args...; kwargs...) = comp(link_data, args...; kwargs...)
function comp(data, scenario, year, variable, comparison_scenario, comparison_year;percent=true)
    # TODO: palettes, normalisation, etc.

    main = data(scenario, year, variable)
    comparator = data(comparison_scenario, comparison_year, variable)

    # dims = 2 sums rows; dims = 1 sums cols
    # Returns Array{Float,2} but we want Array{Float,1} so we flatten it
    if percent
        # Avoid NaN from dividing by zero.
        eps = mean(sum(main, dims = 2)) / 10000
        result = (sum(main, dims = 2) .+ eps) ./ (sum(comparator, dims = 2) .+ eps)
    else
        result = sum(main .- comparator, dims = 2)
    end

    return collect(flatten(result))
end

@memoize function var_stats(domain,variable,quantiles=(0,1))
    # dims = 2 sums rows; dims = 1 sums cols
    vars = []
    if domain == "od_matrices"
        vars = [get(v,variable,[]) for (k,v) in mats]
    elseif domain == "links"
        vars = [get(v,Symbol(variable),[]) for (k,v) in links]
    end
    # Sample arrays because it's slow
    vcat([rand(vars[a].-vars[b],10000) for (a,b) in product(1:length(mats),1:length(mats))]...) |>
        flatten |>
        x -> quantile(x,quantiles)
end

@memoize function var_stats_1d(domain,variable,quantiles=(0,1))
    # dims = 2 sums rows; dims = 1 sums cols
    vars = []
    if domain == "od_matrices"
        vars = [get(v,variable,[]) for (k,v) in mats]
    elseif domain == "links"
        vars = [get(v,Symbol(variable),[]) for (k,v) in links]
    end
    vcat(vars...) |> Iterators.flatten |> x -> quantile(x,quantiles)
end


println("Warming up the cache: links")
@showprogress for variable in keys(filter((k,v) -> get(v,"use",true), metadata["links"]["columns"]))
    # get these quantiles from colourMap in index.js
    var_stats("links",variable,(0.1,0.9))
end

println("Warming up the cache: matrices")
@showprogress for variable in keys(filter((k,v) -> get(v,"use",true), metadata["od_matrices"]["columns"]))
    # get these quantiles from colourMap in index.js
    var_stats("od_matrices",variable,(0.0001,0.9999))
end

route("/scenarios") do
    list_scenarios() |> json
end

route("/variables/:domain") do
    list_variables(@params(:domain)) |> json
end


route("/stats") do
    # Was removed this in ac81797 but is 'needed' below
    defaults = Dict(
        :domain => "od_matrices",
        :scenario => "GreenMax",
        :year => "2030",
        :comparewith => "DoNothing", # Consider making comparison optional: show absolute level
        :compareyear => "auto",
        :variable => "Total_GHG",
        :percent => "true",
        :quantiles => "0.0001,0.9999",  # These default percentiles seem v. generous
                                        # but we look at all possible differences
                                        # so overwhelming majority of differences are
                                        # tiny. Seems to work OK in practice.
        :row => "false",
    )
    d = merge(defaults, getpayload())
    quantiles = parse.(Float64,split(d[:quantiles],","))
    if d[:domain] in ["od_matrices", "links"]
        d[:comparewith] != "none" && return var_stats(d[:domain],d[:variable],Tuple(quantiles)) |> json
        # TODO: If metadata holds the quantiles return them here below
        return var_stats_1d(d[:domain],d[:variable],Tuple(quantiles)) |> json
    else
        throw(DomainError(:domain))
    end
end

route("/data") do
    defaults = Dict(
        :domain => "od_matrices",
        :scenario => "GreenMax",
        :year => "2030",
        :comparewith => "DoNothing", # Consider making comparison optional: show absolute level
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
            row = parse(Int,d[:row])
            return mat_data(scenario, year, variable)[row,:] |> json
        end
        if d[:comparewith] == "none"
            sum(mat_data(scenario, year, variable), dims = 2) |> Iterators.flatten |> collect |> json
        else
            mat_comp(scenario, year, variable, comparewith, compareyear, percent=percent) |> json
        end
    elseif d[:domain] == "links"
        if d[:comparewith] == "none"
            sum(link_data(scenario, year, variable), dims = 2) |> Iterators.flatten |> collect |> json
        else
            link_comp(scenario, year, variable, comparewith, compareyear, percent=percent) |> json
        end
    else
        throw(DomainError(d[:domain]))
    end
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
       ))
end

Genie.AppServer.startup(parse(Int,get(ENV,"GENIE_PORT", "8000")),"0.0.0.0", async = false)

end
