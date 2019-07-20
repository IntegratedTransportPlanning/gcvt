FROM python:3.7-alpine
COPY ./oembed-api /oembed-api
WORKDIR /oembed-api
# Install deps - currently none
# RUN pip install --trusted-host pypi.python.org -r requirements.txt
ENV PYTHONUNBUFFERED 0
CMD python -u oembed-provider.py # -u and env above should mean that logs actually work
