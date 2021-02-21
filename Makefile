.PHONY: front, back, pack, tiles, setup, setupR, http

tiles:
	# TODO: These paths are pretty project-specific. Should specify the packdir better.
	cd src/backend/src && julia --project -L "pct.jl" -E "process_pct_geometry()"

setup:
	cd src/backend && julia --project=. -e "import Pkg; Pkg.instantiate()"
	cd src/frontend && yarn

http:
	env ITP_CADDY_CACHE_TIME=31536000 caddy

back:
	cd src/backend && env ITP_OD_PROD=1 julia --project=. src/app-mux.jl

front:
	cd src/frontend && yarn run watch


## Sort of deprecated ##

pack:
	cd src/data-preparation && julia --project -e "import Pkg; Pkg.instantiate()"
	cd src/data-preparation && julia --project speed_freeflow_hack.jl
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
