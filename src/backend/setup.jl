#!/bin/env julia
using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()
Pkg.test("NodeJS") # This forces .julia/artifacts to gain a node installation
