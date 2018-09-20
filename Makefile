all: README.md

README.md: README.Rmd R/combined_viewer_mapbox/*.json R/combined_viewer_mapbox/*.js
	R -e 'rmarkdown::render("README.Rmd")'
	rm README.html
