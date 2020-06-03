.PHONY: front, back, pack, tiles, setup, setupR, http

tiles:
	# TODO: These paths are pretty project-specific. Should specify the packdir better.
	./src/data-preparation/tiles.sh data/sensitive/GCVT_Scenario_Pack/processed/links.geojson data/sensitive/GCVT_Scenario_Pack/processed/tiles/2
	./src/data-preparation/tiles.sh data/sensitive/GCVT_Scenario_Pack/geometry/zones.geojson data/sensitive/GCVT_Scenario_Pack/processed/tiles/2

setup:
	cd src/backend && julia --project=. -e "import Pkg; Pkg.instantiate()"
	cd src/frontend && yarn

http:
	caddy

back:
	cd src/backend && julia --project=. src/appjl.jl

front:
	cd src/frontend && yarn run watch


## Sort of deprecated ##

pack:
	Rscript ./src/data-preparation/process_pack_dir.R

setupR:
	# You need to source packrat/init.R and run packrat::restore() in R and
	# that will take ages as packrat builds approximately all of CRAN from
	# source.
	#
	#     R
	#     source("packrat/init.R")
	#     packrat::restore()
	#
	# Then remove the comment in .Rprofile so that Rscript will use the
	# libraries that have just been built. Try not to commit the change to
	# .Rprofile.
