"""
API?

This one lets us transition to something more like a tensor fairly painlessly if we decide we want that.

get(d::ODData, var) -> Vectorish
get(d::ODData, var, scen) -> Vectorish
  Indices for vectors produced by this should be comparable if only `scen` changes,
  no guarantee otherwise.
  Some of the backend may expect a matrix here.
get(d::ODData, var, scen, origin) -> Vectorish
get(d::ODData, var, scen, :, dest) -> Vectorish

# Implied, but we don't actually need it
get(d::ODData, var, scen, origin, dest) -> Value

# Examples if we fill with `:`.

get(d, :cycle, :, :, :)
get(d, :cycle, :govtarget, :, :)
get(d, :cycle, :govtarget, 1, :)
get(d, :cycle, :govtarget, :, 1)
get(d, :cycle, :govtarget, 1, 1)
"""

using DataFrames
import Base: getindex

struct ODData{T <: AbstractDataFrame, W, X}
    data::T
    # These are views, we're not triplicating the data.
    grouped_by_origin::W
    grouped_by_destination::X
    meta::Dict{String, Any} # yeah this is a bad idea
end

"""
    ODData(data)

Wrap a dataframe (`data`) whose first two columns are origin and destination and later columns are observations of some kind.

`getindex` methods are provided for the wrapped data, but beware that they don't densify the data and only return 1-D vectors.

"""
function ODData(d, meta)
    d = sort(d, [1, 2])
    by_origin = groupby(d, 1)
    by_destination = groupby(d, 2)
    ODData(d, by_origin, by_destination, meta)
end

# All columns that have are of some dependent variable
function columns_with(d::ODData, var)
    Iterators.flatten(Iterators.map(x->x["name"], Iterators.filter(col -> get(col, "dependent_variable", "") == var, f["columns"])) for f in d.meta["files"])
end

function origins(d::ODData)
    unique(d.data[!, 1])
end

function destinations(d::ODData)
    unique(d.data[!, 2])
end

function original_column_names(d)
    names(d.data)[3:end]
end

function issuperdict(maybesuper::Dict{A,B}, maybemini::Dict{C,D}) where {A, B, C, D}
    for (k,v) in maybemini
        haskey(maybesuper, k) || return false
        issuperdict(maybesuper[k], v) || return false
    end
    return true
end

issuperdict(l,r) = l == r

# Internal helper function
function column_name(d::ODData, dependent_variable, independent_variables)
    files = d.meta["files"]

    for f in files
        index = findfirst(c -> issuperdict(c, Dict("dependent_variable" => dependent_variable, "independent_variables" => independent_variables)), f["columns"])
        if !(isnothing(index))
            return f["columns"][index]["name"]
        end
    end
    throw(BoundsError(d, [dependent_variable, independent_variables]))
end

function varscen2depinds(var, scen)
    return (var, Dict("scenario" => scen))
end

function getindex(d::ODData, var, scen)
    (dependent_variable, independent_variables) = varscen2depinds(var, scen)
    col_idx = column_name(d, dependent_variable, independent_variables)
    d.data[!, col_idx]
end

function getindex(d::ODData, var, scen, origin)
    (dependent_variable, independent_variables) = varscen2depinds(var, scen)
    col_idx = column_name(d, dependent_variable, independent_variables)
    # filter(:origin => ==(origin), d.data; view=true)[!, col_idx]
    # This is a 2x sped-up version of the above filter.
    # If we need to go faster, we can do CSC with a grouped data frame or otherwise.
    @view d.data[ searchsorted(d.data[!, :origin], origin), col_idx ]
end

function getindex(d::ODData, var, scen, ::Colon, destination)
    (dependent_variable, independent_variables) = varscen2depinds(var, scen)
    col_idx = column_name(d, dependent_variable, independent_variables)
    filter(:destination => ==(destination), d.data)[!, col_idx]
end

# Get data grouped by origin or destination
function get_grouped(d::ODData, var, column, direction)
    if direction == :outgoing
        (skipmissing(row[!, column]) for row in d.grouped_by_origin)
    elseif direction == :incoming
        (skipmissing(row[!, column]) for row in d.grouped_by_destination)
    else
        throw(DomainError("direction must be :incoming or :outgoing"))
    end
end
