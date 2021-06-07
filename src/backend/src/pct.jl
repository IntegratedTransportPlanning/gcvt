# This file now is only needed for the wizard

using CSV
using DataFrames
using tippecanoe_jll: tippecanoe
using TOML

include("Ogr2Ogr.jl")

# Magic syntax: "." prefix means a submodule
using .Ogr2Ogr: ogr2ogr

import GeoJSON

# This function V really should live in the wizard
# Expects to find shapefiles and CSV in `$dir/raw`
function process_pct_geometry(dir="$(@__DIR__)/../data/")
    # Get zone names and IDs
    df = CSV.read(joinpath(dir, "raw/PCT example data commute-msoa-nottinghamshire-od_attributes.csv"), DataFrame; missingstring="NA")
    zones = sort!(unique(vcat(df[!, :geo_code1], df[!, :geo_code2])))
    zone_id(code) = findfirst(==(code), zones)
    all_zones = Dict(zip(zones, keys(zones)))

    shapefile = "$dir/raw/Middle_Layer_Super_Output_Areas__December_2011__EW_BGC_V2.shp"

    geom = GeoJSON.read(
        ogr2ogr(
            shapefile,
            flags = Dict(
                 "f" => "geojson",
                 "t_srs" => "epsg:4326",
                 "s_srs" => "epsg:27700",
            )
        )
    )

    # Add our numeric key to the geojson
    zone_name_key = "MSOA11CD"
    found_zones = []
    for feat in geom.features
        # Bug, Features can have a field "id", but GeoJSON.jl doesn't let us read or edit that.
        zone_name = feat.properties[zone_name_key]
        push!(found_zones, zone_name)
        fid = get(all_zones, zone_name, "")
        if haskey(all_zones, zone_name)
            feat.properties["fid"] = fid
        end
    end

    # Remove irrelevant features
    filter!(feat -> haskey(feat.properties, "fid"), geom.features)

    x = setdiff(found_zones, zones)
    !isempty(x) && @warn "Zones in geometry but not in data:" x
    x = setdiff(zones, found_zones)
    !isempty(x) && @warn "Zones in data but not in geometry:" x

    # Save new geojson and generate tiles from it
    processed_geojson = "$dir/processed/zones.geojson"
    mkpath(dirname(processed_geojson))

    open(processed_geojson, "w") do f
        write(f, GeoJSON.write(geom))
    end

    # TODO: cleanup these dirs before writing to them?
    tiles_dir = "$dir/processed/tiles/zones"
    mkpath("$dir/processed/tiles/zones")

    tippecanoe() do bin
        run(`$bin -zg -pC --detect-shared-borders -f $processed_geojson --output-to-directory=$tiles_dir`)
    end
end
