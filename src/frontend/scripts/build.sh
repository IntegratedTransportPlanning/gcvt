#!/usr/bin/env bash

mkdir -p www/
cp js/index.html www/
cp node_modules/construct-ui/lib/index.css www/construct-ui.css
yarn run esbuild js/index.js $@ --bundle --loader:{.jpg,.png}=file --outdir=www --sourcemap --target=chrome58,firefox57
