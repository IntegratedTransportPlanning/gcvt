.PHONY: front, back

README.md: README.Rmd src/app/*.json src/app/*.js
	R -e 'rmarkdown::render("README.Rmd")'
	rm README.html

front:
	cd src/app/ && yarn build

back:
	R -e 'shiny::runApp("src/app", port=6619)'
