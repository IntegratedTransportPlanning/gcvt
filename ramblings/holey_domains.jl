# Generating dummy column names & data

inputs = Dict(
    "scenario" => ["1-squirrels-fight-back", "2-the-squirrels-dont-like-peanut-butter", "3-chaos-with-ed-miliband"],

    "year" => [2020, 1997, 2021, 2043, 2099],

    "mode" => ["Hovercraft", "SUV", "Tricycle"],
)

variables = ["kgco2perkm", "qualys-change-per-km"]


possibilities = []
for (k,array) in inputs
    push!(possibilities, ["$k=$v" for v in array])
end

column_names = []
combinations = Iterators.product(possibilities...) |> collect
for var in variables
    # +5 magic number makes it more likely to use all inputs
    for i in 1:sqrt(length(combinations))
        push!(column_names, "$(var)_$(join(rand(rand(combinations),rand(1:(length(inputs)+5))) |> unique, "_"))")
    end
end

using DataFrames
df = DataFrame(hcat(rand(1:100,100,2), rand(100,length(column_names))), ["Origin", "Destination", column_names...])

# There is some ambiguity here
# if we have e.g. year=2099_mode=SUV and mode=SUV_year=2099 there's clearly a problem
# ditto for if we have a column for year=2099 and then also a column for year=2099_mode=suv
#
# Also ditto for ambiguous origin->dest entries
# 
# I think it's probably OK to assume that the real data is cleaner than that, though, and just ignore it?


# "Real" code hereon - this stuff could be useful for real, doesn't just generate dummy data

function columnname2varanddict(colname)
    res = split(colname,"_")
    # Should include original column name here
    pairs = Dict(split(str,"=") for str in res[2:end])

    # "_" is safe to use as it cannot appear in a column name
    pairs["_originalname"] = colname
    return (res[1], pairs)
end

valid_cols = Dict()
for (k, v) in columnname2varanddict.(column_names)
    valid_cols[k] = push!(get(valid_cols,k,[]),v)
end

# This may well already exist in a library somewhere
function issuperdict(bigger, smaller)
    try
        all(bigger[k] == v for (k,v) in smaller)
    catch e
        return false
    end
end

function findstuff(;variable, inputs=Dict())
    isnothing(variable) && return valid_cols
    length(inputs) == 0 && return valid_cols[variable]
    filter(
        d -> issuperdict(d,inputs),
        valid_cols[variable],
    )
end
findcols(dicts) = [d["_originalname"] for d in dicts]
# e.g. usage
# df[:,findcols(findstuff(variable="kgco2perkm",inputs=Dict("mode"=>"SUV")))]

function mergeDictArrays(dicts)
    inputnames = Iterators.flatten(keys.(dicts)) |> unique
    Dict(k => unique(filter(!isnothing,get.(dicts,k, nothing))) for k in inputnames)
end

# e.g. usage
# Returns a dict of all other permitted inputs
#
# In the web app, we want to provide this function with all of the things aren't changing
# i.e. everything _except_ the selection you're hovering over
#
# Values which exist but aren't returned in this should be greyed out somehow. They should still be selectable to allow people to "tunnel through" dark parts of the domain.
#
# In the example below, I want to change the year after I've selected a variable and mode
# mergeDictArrays(findstuff(variable="kgco2perkm",inputs=Dict("mode"=>"SUV")))["year"]
#
#
# Example problem this solves: let scenarios be the columns and years be the rows. Entries in the matrix denote valid combinations.
#
#  2020 2019 2018
# 1  t    x
# 2
# 3       o
#
# Say I am at `o` and I want to get to `t`. Without being able to select greyed out values, I have to select `x` first before I can switch to `t`.
#
# If instead we have this set of valid scenarios,
#
#  2020 2019 2018
# 1  t     
# 2
# 3       o
#
# It is impossible to get from `o` to `t` without being able to select greyed-out values. This is what I mean by "tunnelling".
