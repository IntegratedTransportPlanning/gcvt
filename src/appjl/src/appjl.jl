#= using Genie =#

module tmp

import Genie
using Genie.Router: route, @params
using Genie.Requests: getpayload

# Generates HTML responses
using Genie.Renderer: html

using Memoize: @memoize
using ProgressMeter: @showprogress

# This converts its argument to json and sets the appropriate headers for content type
# We're customising it to set the CORS header
json(data; status::Int = 200) =
    Genie.Renderer.json(data; status = status, headers = Dict("Access-Control-Allow-Origin" => "*"))

import YAML

using Statistics

Genie.config.session_auto_start = false
# Default headers are supposed to go here, but they don't seem to work.
#= Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*" =#

route("/") do
    json("Hi there!")
end


### APP ###

include("$(@__DIR__)/scenarios.jl")

# This should probably be reloaded periodically so server doesn't need to be restarted?
links, mats = load_scenarios(packdir)

# This should probably be reloaded periodically so server doesn't need to be restarted?
metadata = YAML.load_file(joinpath(packdir, "meta.yaml"))

const DEFAULT_META = Dict(
    "good" => "smaller",
)

for (k,v) in metadata["links"]["columns"]
    metadata["links"]["columns"][k] = merge(DEFAULT_META,v)
end

for (k,v) in metadata["od_matrices"]["columns"]
    metadata["od_matrices"]["columns"][k] = merge(DEFAULT_META,v)
end

for (k,v) in metadata["scenarios"]
    metadata["scenarios"][k]["name"] = get(metadata["scenarios"][k],"name",k)
end

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

    # dims = 2 sums rows; dims = 1 sums cols
    # Returns Array{Float,2} but we want Array{Float,1} so we flatten it
    percent && return sum(data(scenario, year, variable), dims = 2) ./ sum(data(comparison_scenario, comparison_year, variable), dims = 2) |> Iterators.flatten |> collect
    return sum(data(scenario, year, variable) .- data(comparison_scenario, comparison_year, variable), dims = 2) |> Iterators.flatten |> collect
end

@memoize function var_stats(domain,variable,quantiles=(0,1))
    println("running")
    # dims = 2 sums rows; dims = 1 sums cols
    vars = []
    if domain == "od_matrices"
        vars = [get(v,variable,[]) for (k,v) in mats]
    elseif domain == "links"
        vars = [get(v,Symbol(variable),[]) for (k,v) in links]
    end
    # Sample arrays because it's slow
    vcat([rand(vars[a].-vars[b],10000) for (a,b) in Iterators.product(1:length(mats),1:length(mats))]...) |> Iterators.flatten |> x -> quantile(x,quantiles)
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
    d = merge(merge(DEFAULTS, Dict(
        :quantiles => "0.0001,0.9999"  # These default percentiles seem v. generous
                                # but we look at all possible differences
                                # so overwhelming majority of differences are
                                # tiny. Seems to work OK in practice.
    )), getpayload())
    quantiles = parse.(Float64,split(d[:quantiles],","))
    if d[:domain] in ["od_matrices", "links"]
        var_stats(d[:domain],d[:variable],Tuple(quantiles)) |> json
    else
        throw(DomainError(:domain))
    end
end

const DEFAULTS = Dict(
    :domain => "od_matrices",
    :scenario => "GreenMax",
    :year => "2030",
    :comparewith => "DoNothing", # Consider making comparison optional: show absolute level
    :compareyear => "2020",
    :variable => "Total_GHG",
    :percent => "true",
)

route("/data") do
    d = merge(DEFAULTS, getpayload())
    if d[:domain] == "od_matrices"
        mat_comp(d[:scenario], parse(Int, d[:year]), d[:variable], d[:comparewith], parse(Int,d[:compareyear]), percent=(d[:percent]=="true")) |> json
    elseif d[:domain] == "links"
        link_comp(d[:scenario], parse(Int, d[:year]), d[:variable], d[:comparewith], parse(Int,d[:compareyear]), percent=(d[:percent]=="true")) |> json
    else
        throw(DomainError(d[:domain]))
    end
end

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
