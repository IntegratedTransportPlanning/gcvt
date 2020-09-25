using FileIO: @format_str, load, File
using RData: RString
using DataFrames: DataFrame

using Query: @filter
using Suppressor: @suppress

using OrderedCollections: OrderedDict

import YAML

packdir = "$(@__DIR__)/../data/"

# This way doesn't emit warnings, but requires some change to output format.
#= linkscens = load(File(format"RDataSingle", joinpath(packdir, "processed", "link_scenarios.Rds"))) =#
#= odscens = load(File(format"RDataSingle", joinpath(packdir, "processed", "od_matrices_scenarios.Rds"))) =#

function load_scenarios(packdir=packdir)
    # This way emits warnings, but works fine.
    scenarios = @suppress load(File(format"RDataSingle", joinpath(packdir, "processed", "julia_compat_scenarios.Rds")));

    df = DataFrame(values(scenarios), [:scenario, :year, :type, :data]);
    if !(typeof(df.year) <: Vector{T} where T <: Integer)
        df.year = parse.(Int, df.year)
    end

    links = df |>
        @filter(_.type == "links") |>
        DataFrame |>
        (df -> Dict((name, year) => data for (name, year, _, data) in zip(eachcol(df)...)));

    mats = df |>
        @filter(_.type == "od_matrices") |>
        DataFrame |>
        (df -> Dict((name, year) => data for (name, year, _, data) in zip(eachcol(df)...)))

    metadata = get_metadata(links, mats, packdir)

    return links, mats, metadata
end

function get_metadata(links, mats, packdir)
    # This should probably be reloaded periodically so server doesn't need to be restarted?
    metadata = YAML.load_file(joinpath(packdir, "meta.yaml"); dicttype=OrderedDict{String, Any})

    default_meta = Dict(
        "good" => "smaller",
        "thickness" => "variable",
        "statistics" => "hide",
        "force_bounds" => [],
    )

    for (k,v) in metadata["links"]["columns"]
        metadata["links"]["columns"][k] = merge(default_meta, v)
    end

    for (k,v) in metadata["od_matrices"]["columns"]
        metadata["od_matrices"]["columns"][k] = merge(default_meta, v)
    end

    for (k,v) in metadata["scenarios"]
        metadata["scenarios"][k]["name"] = get(metadata["scenarios"][k],"name",k)
    end

    # Store what years are available for each scenario
    d = Dict(links |> keys .|> x -> (x[1], Int[]))
    for (k, v) in links |> keys
        push!(d[k], v)
    end

    d2 = Dict(mats |> keys .|> x -> (x[1], Int[]))
    for (k, v) in mats |> keys
        push!(d2[k], v)
    end

    scenarioYears = Dict(
        k => sort(intersect(d[k], d2[k]))
        for k in keys(d)
    )

    for (name, years) in scenarioYears
        try
            metadata["scenarios"][name]["at"] = years
        catch x
            if isa(x, KeyError)
                metadata["scenarios"][name] = Dict("use" => false)
            else
                rethrow()
            end
        end
    end

    return metadata
end

#=

using Statistics

# Aggregate to one df, takes a little while and allocates a lot.
# But it's only once, so whatever, could do it.
@time vcat(values(links)...);

# Could just apply the function across an iterable of each thing?
@time Iterators.flatten(map(df -> @view(df[!, :Cost_Pax]), values(links))) |> mean;

# Same kind of thing for the matrices
Iterators.flatten(map(dict -> dict["Pax"], values(mats))) |> mean

Dict((name, year) => matrices for (name, year, matrices) in zip(values(odscens)...))

=#

# Interface

# Get a vector or matrix of a variable for a given year and scenario
# Get a vector of a column for all scenarios and years (maybe not used any more?)
