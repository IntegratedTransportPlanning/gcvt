all: README.md

README.md: README.Rmd
	R -e 'rmarkdown::render("README.Rmd")'
	rm README.html
