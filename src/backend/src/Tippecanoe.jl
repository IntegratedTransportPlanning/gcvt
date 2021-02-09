module Tippecanoe
export tippecanoe

# NB: not a real package yet
using tippecanoe_jll: tippecanoe

function tippecanoe(source::String, outdir::String)
    base = replace(basename(source), r"\.geojson$" => "")
    return tippecanoe() do bin
        run(`$bin -zg -pC -f $source -o $outdir/$base.mbtiles`)
    end
end

end
