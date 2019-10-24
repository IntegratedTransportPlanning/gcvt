#= using Genie =#

module tmp

import Genie
using Genie.Router: route, @params

# This converts its argument to json and sets the appropriate headers for content type
using Genie.Renderer: json

import YAML

Genie.config.session_auto_start = false

route("/") do
    (:message => "Hi there!") |> json
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
function mat_colour(scenario, year, variable, comparison_scenario, comparison_year)
    # TODO: palettes, normalisation, etc.

    # dims = 2 sums rows; dims = 1 sums cols
    sum(mat_data(scenario, year, variable) .- mat_data(comparison_scenario, comparison_year, variable), dims = 2)
end

route("/scenarios") do
    list_scenarios() |> json
end

route("/variables/:domain") do
    list_variables(@params(:domain)) |> json
end

route("/data/:domain/:scenario/:year/:variable") do
    if @params(:domain) == "od_matrices"
        mat_colour(@params(:scenario), parse(Int, @params(:year)), @params(:variable), "DoNothing", 2025) |> json
    else
        throw(DomainError(domain))
    end
end

Genie.AppServer.startup(parse(Int,get(ENV,"GENIE_PORT", "8000")),"0.0.0.0", async = false)

end
