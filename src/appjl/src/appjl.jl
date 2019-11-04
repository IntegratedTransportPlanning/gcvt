#= using Genie =#

module tmp

import Genie
using Genie.Router: route, @params

# Generates HTML responses
using Genie.Renderer: html

# This converts its argument to json and sets the appropriate headers for content type
using Genie.Renderer: json

import YAML

Genie.config.session_auto_start = false

route("/") do
    (:message => "Hi there!") |> json
end


### APP ###

# Mapbox token (set in ENV eventually)
include("$(@__DIR__)/../.secrets.jl")

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


route("/map/") do
    # todo 
    # - set up babel so we can use modern JS and still work in old browsers
    # - port src/app/app.js functionality across
    # - move this to a separate file
    html("""
        <head>
        <meta charset='utf-8' />
        <title>Greener Connectivity Visualisation Tool</title>
        <meta name='viewport' content='initial-scale=1,maximum-scale=1,user-scalable=no' />
        <script src='https://api.tiles.mapbox.com/mapbox-gl-js/v1.5.0/mapbox-gl.js'></script>
        <link href='https://api.tiles.mapbox.com/mapbox-gl-js/v1.5.0/mapbox-gl.css' rel='stylesheet' />
        <style>
        body { margin:0; padding:0; }
        #map { position:absolute; top:0; bottom:0; width:100%; }
        </style>
        </head>
        <body>
         
        <div id='map'></div>
        <script>
        mapboxgl.accessToken = '$MAPBOX_TOKEN';
        var map = new mapboxgl.Map({
        container: 'map', // container id
        style: 'mapbox://styles/mapbox/light-v10', // stylesheet location
        center: [32, 48], // starting position [lng, lat]
        zoom: 4 // starting zoom
        });
        </script>
         
        </body>
    """)
end

Genie.AppServer.startup(parse(Int,get(ENV,"GENIE_PORT", "8000")),"0.0.0.0", async = false)

end
