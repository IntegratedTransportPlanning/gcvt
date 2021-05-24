# Play area for generating real "dummy" TOML for the tool to use
# Means we don't need to wait for the wizard to be working first


using TOML

dummy = """
    [project]
    name = "gcvt"
    description = "blah"
    map_origin = { lat = 1, lon = 53, zoom = 4 }

    [[geometries]]
    filename = "zones.geojson"
    id = "zones"
    feature_id = "ESOA"
    feature_name = "NAME"

    [[files]]
    filename = "matrix.csv"
    type = "matrix"
    for_geometry = "zones"
    origins = "origin"
    destinations = "destination"

    [[files.columns]]
    name = "all_govtarget_2010"
    dependent_variable = "all"
    independent_variables = { scenario = "govtarget", year = 2010 }

    [[files.columns]]
    name = "all_dutch_2010"
    dependent_variable = "all"
    independent_variables = { scenario = "dutch", year = 2010 }

    # ...

    [[dependent_variables]]
    id = "all"
    name = "Trips by any mode"
    bigger_is_better = true
    description = \"\"\"
    Some
    multiline
    description\"\"\"
    units = "people"
    palette = "blah"
    bins = [1, 5, 100]

    # ...

    [[independent_variables]]
    id = "scenario"
    type = "categorical"

    [[independent_variables.values]]
    id = "govtarget"
    name = "Government target"
    description = "blah"

    [[independent_variables.values]]
    id = "dutch"
    name = "Dutch-equivalent"

    [[independent_variables]]
    id = "year"
    type = "ordinal"
    # Values array is optional

    # ...
"""

TOML.parse(dummy)

TOML.print(metadata)

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

function oldmeta2newschema(metadata)
    newmeta = Dict()

    newmeta["project"] = Dict("name" => "Bikes and stuff", "description" => "something to do with bikes", "map_origin" => Dict("lat" => 53.231, "lon" => -1.129, "zoom" => 8))

    newmeta["geometries"] = [Dict("filename" => "processed/zones.geojson", "id" => "zones", "feature_id" => "ESOA", "feature_name" => "NAME")]

    newmeta["files"] = [Dict("filename" => "raw/PCT example data commute-msoa-nottinghamshire-od_attributes.csv", "type" => "matrix", "for_geometry" => "zones", "origins" => "origin", "destinations" => "destination", "columns" => [])]

    for (k,v) in metadata["od_matrices"]["columns"]
        for scenario in v["scenarios_with"]
            column = Dict(
                          "name" => "$(k in variables_without_scenario ? "" : scenario*"_")$(k)",
                "independent_variables" => Dict("scenario" => scenario, "year" => 2010),
                "dependent_variable" => k,
            )
            push!(newmeta["files"][1]["columns"],column)
        end
    end

    newmeta["independent_variables"] = [
        Dict(
            "id" => "scenario",
            "values" => [
                Dict("id" => k, "name" => v["name"]) for (k,v) in metadata["scenarios"]
            ],
            "type" => "categorical",
        ),
        Dict(
            "id" => "year",
            "values" => [2010],
            "type" => "numerical", # Probably need to agree on this. Years are continuous IMO - do we care about the distinction? (NB: 3BC = -3AD)
        ),
    ]

    # I've added a "show_stats" field here 
    # because it seemed like the best place for it
    newmeta["dependent_variables"] = [Dict("id" => k, "name" => k, "bigger_is_better" => v["good"], "bins" => v["force_bounds"], "show_stats" => v["statistics"]) for (k,v) in metadata["od_matrices"]["columns"]]

    newmeta
end

# open("pct_meta.toml", "w") do io
#     TOML.print(io, oldmeta2newschema(metadata))
# end
