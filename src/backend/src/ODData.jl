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

struct ODData{T <: AbstractDataFrame, U, V, W, X}
    data::T
    column_vars::U
    column_scens::V
    # These are views, we're not triplicating the data.
    grouped_by_origin::W
    grouped_by_destination::X
end

"""
    ODData(data, column_vars, column_scens)

Wrap a dataframe (`data`) whose first two columns are origin and destination and later columns are observations of some kind.

`column_vars[i]` and `column_scens[i]` give the variable and scenario (if any) of column i.

`getindex` methods are provided for the wrapped data, but beware that they don't densify the data and only return 1-D vectors.

"""
function ODData(d, v, s)
    d = sort(d, [1, 2])
    by_origin = groupby(d, 1)
    by_destination = groupby(d, 2)
    ODData(d, v, s, by_origin, by_destination)
end

# Get some metadata
function scenarios(d::ODData)
    unique(d.column_scens)
end

function variables(d::ODData)
    unique(d.column_vars)
end

function scenarios_with(d::ODData, var)
    unique(@view d.column_scens[findall(==(var), d.column_vars)])
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

# Internal helper function
function column_index(d::ODData, var, scen)
    col_idx = findfirst(==( (var, scen) ), collect(zip(d.column_vars, d.column_scens)))
    if isnothing(col_idx)
        throw(BoundsError(d, [var, scen]))
    else
        # + 2 to skip the origin and destination columns
        col_idx + 2
    end
end

# Tensor-ish getindex methods.
function getindex(d::ODData, var)
    col_idxs = findall(==(var), d.column_vars)
    if isempty(col_idxs)
        throw(BoundsError(d, [var]))
    else
        # + 2 to skip the origin and destination columns
        Iterators.flatten(d.data[!, idx + 2] for idx in col_idxs)
    end
end

function getindex(d::ODData, var, scen)
    col_idx = column_index(d, var, scen)
    d.data[!, col_idx]
end

function getindex(d::ODData, var, scen, origin)
    col_idx = column_index(d, var, scen)
    # filter(:origin => ==(origin), d.data; view=true)[!, col_idx]
    # This is a 2x sped-up version of the above filter.
    # If we need to go faster, we can do CSC with a grouped data frame or otherwise.
    @view d.data[ searchsorted(d.data[!, :origin], origin), col_idx ]
end

function getindex(d::ODData, var, scen, ::Colon, destination)
    col_idx = column_index(d, var, scen)
    filter(:destination => ==(destination), d.data)[!, col_idx]
end

# Get data grouped by origin or destination
function get_grouped(d::ODData, var, scen, direction)
    col_idx = column_index(d, var, scen)
    if direction == :incoming
        (skipmissing(row[!, col_idx]) for row in d.grouped_by_origin)
    elseif direction == :outgoing
        (skipmissing(row[!, col_idx]) for row in d.grouped_by_destination)
    else
        throw(DomainError("direction must be :incoming or :outgoing"))
    end
end
