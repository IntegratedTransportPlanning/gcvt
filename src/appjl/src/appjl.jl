#= using Genie =#

module tmp

import Genie
using Genie.Router: route, @params

# Generates HTML responses
using Genie.Renderer: html

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

links, mats = load_scenarios(packdir)

metadata = YAML.load_file(joinpath(packdir, "meta.yaml"))

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

function link_data(scenario, year, variable::String)
    links[(scenario, year)][Symbol(variable)]
end

# Get colour to draw each shape for (scenario, year, variable, comparison scenario, comparison year) -> (colours)
function mat_colour(scenario, year, variable, comparison_scenario, comparison_year,percent=true)
    # TODO: palettes, normalisation, etc.

    # dims = 2 sums rows; dims = 1 sums cols
    #sum((mat_data(scenario, year, variable) ./ mat_data(comparison_scenario, comparison_year, variable) .|> x -> isnan(x) ? 0 : x), dims = 2)
    percent && return sum(mat_data(scenario, year, variable), dims = 2) ./ sum(mat_data(comparison_scenario, comparison_year, variable), dims = 2)
    return sum(mat_data(scenario, year, variable) .- mat_data(comparison_scenario, comparison_year, variable), dims = 2)
end

function var_stats(variable,quantiles=[0,1])
    # dims = 2 sums rows; dims = 1 sums cols
    vcat([get(v,variable,[]) for (k,v) in tmp.mats]...) |> Iterators.flatten |> x -> quantile(x,quantiles)
end

route("/scenarios") do
    list_scenarios() |> json
end

route("/variables/:domain") do
    list_variables(@params(:domain)) |> json
end

# Ideally this would accept an array
route("/stats/:domain/:variable/:q1/:q2") do
    if @params(:domain) == "od_matrices"
        var_stats(@params(:variable),parse.(Float64,[@params(:q1),@params(:q2)])) |> json
    else
        throw(DomainError(:domain))
    end
end

route("/data/:domain/:scenario/:year/:variable") do
    if @params(:domain) == "od_matrices"
        mat_colour(@params(:scenario), parse(Int, @params(:year)), @params(:variable), "DoNothing", 2025) |> json
    else
        throw(DomainError(:domain))
    end
end

Genie.AppServer.startup(parse(Int,get(ENV,"GENIE_PORT", "8000")),"0.0.0.0", async = false)

end
