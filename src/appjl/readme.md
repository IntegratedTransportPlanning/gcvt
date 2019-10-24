Play interactively with `julia -L setup.jl` to add packages etc. Put application in `appjl.jl`.

To run as a container do

```
sudo docker build -t jtest .
sudo docker run -it --rm jtest
```

Once it's ready for use with the rest of the stuff, stick it in cms/docker-compose.yml like the oembed-api one.

NB: processed data must reside in the ./data/ directory
