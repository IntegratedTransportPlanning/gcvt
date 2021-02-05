using CSV
using DataFrames
using OrderedCollections: OrderedDict

include("ODData.jl")

function load_pct_data()
    df = CSV.read(joinpath(@__DIR__, "../data/raw/PCT example data commute-msoa-nottinghamshire-od_attributes.csv"), DataFrame; missingstring="NA")

    scenario_prefixes = ("govtarget", "dutch", "cambridge", "govnearmkt", "gendereq", "ebike", "base")
    prefixed_names = filter(n -> any(startswith.(n, scenario_prefixes)), names(df))
    scenariod_variables = unique(last.(split.(prefixed_names, '_')))
    variables_without_scenario = [
     "all",
     "bicycle",
     "foot",
     "car_driver",
     "car_passenger",
     "motorbike",
     "train_tube",
     "bus",
     "taxi_other",
     "e_dist_km",
     "rf_dist_km",
     "rq_dist_km",
     "dist_rf_e",
     "dist_rq_rf",
     "rf_avslope_perc",
     "rq_avslope_perc",
     "rf_time_min",
     "rq_time_min"]

    df = df[!, ["geo_code1", "geo_code2", prefixed_names..., variables_without_scenario...]]

    vars = vcat(scenariod_variables, variables_without_scenario)
    zones = sort(unique(vcat(df[:, 1], df[:, 2])))
    zone_id(code) = findfirst(==(code), zones)

    df[!, :origin] = zone_id.(df[!, 1])
    df[!, :destination] = zone_id.(df[!, 2])

    df = df[!, ["origin", "destination", prefixed_names..., variables_without_scenario...]]

    column_vars = [ vars[findfirst(v -> endswith(name, v), vars)] for name in names(df)[3:end] ]

    column_scens = map(names(df)[3:end]) do name
        scen = findfirst(v -> startswith(name, v), scenario_prefixes)
        isnothing(scen) ? "base" : scenario_prefixes[scen]
    end

    return ODData(df, column_vars, column_scens)
end

# Minimum metadata
function load_pct_metadata(data)
    # Problems:
    # Software expects that every scenario contains every column
    # Solution:
    # scenarios_with(variable_name)
    # variables_in(scenario_name)
    var_defaults = Dict(
        "good" => "smaller",
        "thickness" => "variable",
        "statistics" => "hide",
        "force_bounds" => [],
    )

    vars = OrderedDict(var => merge(var_defaults, Dict("scenarios_with" => scenarios_with(data, var))) for var in variables(data))

    scens = OrderedDict(name => Dict("name" => name, "at" => [2010]) for name in scenarios(data))

    OrderedDict(
        "name" => "PCT stuff",
        "description" => "blah",
        "od_matrices" => Dict(
             "columns" => vars
        ),
        "scenarios" => scens,
    )
end

import GeoJSON
import Turf

function load_pct_centroids()
    zones = GeoJSON.parsefile("$(@__DIR__)/../data/processed/zones.geojson")
    zone_centroids = Array{Array{Float64,1},1}(undef,length(zones.features))
    for f in zones.features
        zone_centroids[f.properties["fid"]] = Turf.centroid(f.geometry).coordinates
    end
    return zone_centroids
end

# using Test

# function tests()
#     # Some simple regression tests.
#     # Data was manually checked against the CSV, too.
#     pct_odd = load_pct_data()

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
