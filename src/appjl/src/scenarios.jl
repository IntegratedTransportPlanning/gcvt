using FileIO: @format_str, load, File
using RData: RString
using DataFrames: DataFrame

using Query: @filter
using Suppressor: @suppress

packdir = "$(@__DIR__)/../data/"

# This way doesn't emit warnings, but requires some change to output format.
#= linkscens = load(File(format"RDataSingle", joinpath(packdir, "processed", "link_scenarios.Rds"))) =#
#= odscens = load(File(format"RDataSingle", joinpath(packdir, "processed", "od_matrices_scenarios.Rds"))) =#

function load_scenarios(packdir=packdir)
    # This way emits warnings, but works fine.
    scenarios = @suppress load(File(format"RDataSingle", joinpath(packdir, "processed", "julia_compat_scenarios.Rds")));

    df = DataFrame(values(scenarios), [:scenario, :year, :type, :data]);
    df.year = parse.(Int, df.year)

    links = df |>
        @filter(_.type == "links") |>
        DataFrame |>
        (df -> Dict((name, year) => data for (name, year, _, data) in zip(eachcol(df)...)));

    mats = df |>
        @filter(_.type == "od_matrices") |>
        DataFrame |>
        (df -> Dict((name, year) => data for (name, year, _, data) in zip(eachcol(df)...)))

    return links, mats
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
