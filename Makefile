.PHONY: front, back, pack, tiles, setup, setupR, http, watchfront, muxd, getcaddy

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
	cd src/frontend && yarn run build

watchfront:
	cd src/frontend && yarn run watch

muxd:
	tmux new-session\; splitw make watchfront\; splitw make http\; splitw make back\; kill-pane -t0\; select-layout tiled

getcaddy:
	curl -L https://github.com/caddyserver/caddy/releases/download/v1.0.4/caddy_v1.0.4_linux_amd64.tar.gz | tar xz caddy
