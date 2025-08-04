# FROM ruby:3.2-bullseye

# RUN apt update -y && apt install -y \
#     build-essential \
#     ruby-dev \
#     ruby-json

# Use GDAL as base as debian not yet include GDAL 3.7 required for GTFS
FROM ghcr.io/osgeo/gdal:ubuntu-small-3.10.0

RUN apt update -y && apt install -y \
    build-essential \
    bundler \
    clang \
    git \
    libgeos-dev \
    libyaml-dev \
    ruby-dev \
    ruby-json

ADD Gemfile .
ADD Gemfile.lock .
RUN bundle config --global silence_root_warning 1
RUN bundle install

ADD *.rb ./
ADD datasources datasources

RUN date -u +"%Y-%m-%dT%H:%M:%SZ" > .build

ENV LC_ALL=C.utf8
ENV LANG=C.utf8
