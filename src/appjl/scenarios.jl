using FileIO: @format_str, load, File
using RData: RString
using DataFrames

using Statistics

# Need to get all

packdir = "../../data/sensitive/GCVT_Scenario_Pack/"

linkscens = load(File(format"RDataSingle", joinpath(packdir, "processed", "link_scenarios.Rds")))

odscens = load(File(format"RDataSingle", joinpath(packdir, "processed", "od_matrices_scenarios.Rds")))

scenarios = load(File(format"RDataSingle", joinpath(packdir, "processed", "julia_compat_scenarios.Rds")))

df = DataFrame(values(scenarios), [:scenario, :year, :type, :data])
df.year = parse.(Int, df.year)

links = df |>
    @filter(_.type == "links") |>
    DataFrame |>
    (df -> Dict((name, year) => data for (name, year, _, data) in zip(eachcol(df)...)))

mats = df |>
    @filter(_.type == "od_matrices") |>
    DataFrame |>
    (df -> Dict((name, year) => data for (name, year, _, data) in zip(eachcol(df)...)))

# Aggregate to one df, takes a little while so I guess real allocation is happening
@time vcat(values(links)...);

# Could just apply the function across an iterable of each thing?
@time Iterators.flatten(map(df -> @view(df[!, :Cost_Pax]), values(links))) |> mean

# Same kind of thing for the matrices
Iterators.flatten(map(dict -> dict["Pax"], values(mats))) |> mean

Dict((name, year) => matrices for (name, year, matrices) in zip(values(odscens)...))

# Interface

# Get a vector or matrix of a variable for a given year and scenario
# Get a vector of a column for all scenarios and years (maybe not used any more?)
function get_od_matrix(odscensdf, scenario, year, variable)
    filter(row -> row[:name] == "Toll", odscensdf)
end

function get_scenarios()
end
