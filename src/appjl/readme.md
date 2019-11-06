Copy data: `cp -r path/to/sensitive/<pack name>/ ./data`

Play interactively with `julia -L setup.jl` to add packages etc. Put application in `appjl.jl`. Start with `julia --project src/appjl.jl`. NB: if running from a directory above this one, you'll need to specify the project directory (this one) explicitly.

To run as a container do

```
sudo docker build -t jtest .
sudo docker run -p8000:8000 -it --rm jtest
```

Once it's ready for use with the rest of the stuff, stick it in cms/docker-compose.yml like the oembed-api one.
