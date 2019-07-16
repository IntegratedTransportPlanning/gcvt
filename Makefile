.PHONY: front, back

README.md: README.Rmd src/app/*.json src/app/*.js
	R -e 'rmarkdown::render("README.Rmd")'
	rm README.html

pack:
	# The first step is buggy at the mo, but this is how it is supposed to work.
	# cd src/data-preparation && Rscript process_pack_dir.R
	./tiles.sh data/sensitive/GCVT_Scenario_Pack/processed/links.geojson
	./tiles.sh data/sensitive/GCVT_Scenario_Pack/geometry/zones.geojson

front:
	cd src/app/ && yarn build

back:
	R -e 'shiny::runApp("src/app", port=6619)'
