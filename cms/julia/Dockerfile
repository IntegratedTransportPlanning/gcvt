FROM julia:1.1
ADD . /julia-gcvt/

# Install toolchain needed for many Julia packages
RUN set -eux; \
        apt-get update; \
        apt-get install -y --no-install-recommends build-essential; \
        rm -rf /var/lib/apt/lists/*

WORKDIR julia-gcvt

# Cache packages so subsequent runs are fairly speedy
RUN julia setup.jl

CMD julia run.jl
