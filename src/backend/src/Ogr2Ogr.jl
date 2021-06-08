module Ogr2Ogr
export ogr2ogr

using GDAL_jll: ogr2ogr_path

function argsdict2stringarr(args)
    ans = []
    for (k,v) in args
        if (v === true)
            push!(ans, "-$k")
        elseif (v === false)
            continue
        else
            push!(ans, "-$k")
            push!(ans, v)
        end
    end
    ans
end

# Spiky. If you ask for help the process will fail.
# Returns output by default; set `dest` if you want it to go to a file
function ogr2ogr(source, dest="/vsistdout/"; flags=Dict())
    flags = merge(Dict("f" => "geojson",), flags)
    return ogr2ogr_path() do bin
        read(`$bin $([argsdict2stringarr(flags)..., dest, source])`)
    end
end

end
