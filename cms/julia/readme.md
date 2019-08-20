Play interactively with `julia -L setup.jl` to add packages etc. Put application in `run.jl`.

To run as a container do

```
sudo docker build -t jtest .
sudo docker run -it --rm jtest
```

Once it's ready for use with the rest of the stuff, stick it in ../docker-compose.yml like the oembed-api one.
