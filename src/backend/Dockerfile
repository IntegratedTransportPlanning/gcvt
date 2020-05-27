FROM julia:1.4
COPY . /julia-gcvt/

# Install toolchain needed for many Julia packages
# Uncomment this if we later use a package that needs it
# RUN set -eux; \
#         apt-get update; \
#         apt-get install -y --no-install-recommends build-essential; \
#         rm -rf /var/lib/apt/lists/*

WORKDIR julia-gcvt

# Use pkg server for faster builds
ENV JULIA_PKG_SERVER=pkg.julialang.org

# Cache packages so subsequent runs are fairly speedy
RUN julia setup.jl

ARG GENIE_PORT=8000

ENV GENIE_PORT=$GENIE_PORT

EXPOSE $GENIE_PORT

CMD julia --project src/appjl.jl
