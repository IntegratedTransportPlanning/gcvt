#!/bin/bash

USAGE="Usage: $0 /path/to/foo.geojson /path/to/outputdirectory"

# TODO: Do this from Julia or R (probably R) maybe and with `redo`

set -ex

mkmbtiles() {
    local geojson="$1"
    local outdir="$2"
    local base="$(basename -s .geojson "$geojson")"

    mkdir -p "$outdir"
    tippecanoe -zg -pC -f "$geojson" -o "$outdir/$base.mbtiles"
}

mktiledir() {
    local mbtiles="$1"
    local outdir="$2"
    local base="$(basename -s .mbtiles "$mbtiles")"

    mkdir -p "$outdir/tiles"
    rm -rf "$outdir/tiles/$base"
    mb-util --image_format=pbf "$mbtiles" "$outdir/tiles/$base"
}

# Links need to be clipped and stuff, which is done by process_pack_dir at the mo.
# convert2geojson() {
#     local geometry=$1
#     local base=$2

#     Rscript - <<< "
# library(tidyverse)
# library(sf)

# links = read_sf('$geometry')
# links %>%
#   select(ID_LINK) %>%
#   write_sf('$base.geojson')
# "
# }

[[ $# -lt 1 ]] && (echo "$USAGE"; exit 1)

geometry=$1
outdir=$2

base="${geometry%%.*}"

geom_extension=${geometry#*.}

# if [[ $geom_extension != geojson ]]; then
#     convert2geojson "$geometry" "$base"
#     geometry="$base.geojson"
# fi

mkmbtiles "$geometry" "$outdir"
mktiledir "$outdir/$base.mbtiles" "$outdir"
