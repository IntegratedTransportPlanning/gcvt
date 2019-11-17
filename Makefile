.PHONY: front, back, pack, tiles, setup, setupR, http

tiles:
	# TODO: These paths are pretty project-specific. Should specify the packdir better.
	./src/data-preparation/tiles.sh data/sensitive/GCVT_Scenario_Pack/processed/links.geojson data/sensitive/GCVT_Scenario_Pack/processed/tiles
	./src/data-preparation/tiles.sh data/sensitive/GCVT_Scenario_Pack/geometry/zones.geojson data/sensitive/GCVT_Scenario_Pack/processed/tiles

setup:
	cd src/appjl && julia --project=. -e "import Pkg; Pkg.instantiate()"
	cd src/appts && yarn

http:
	caddy

back:
	cd src/appjl && julia --project=. src/appjl.jl

front:
	cd src/appts && yarn run watch


## Sort of deprecated ##

pack:
	Rscript ./src/data-preparation/process_pack_dir.R

setupR:
	echo "You need to source packrat/init.R and that will take ages."
	echo "Then remove the comment in .Rprofile so that Rscript will use packrat"
