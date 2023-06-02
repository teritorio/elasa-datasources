FROM ruby:3.0-bullseye

RUN apt update -y && apt install -y \
    build-essential \
    ruby-dev \
    ruby-json

ADD Gemfile .
RUN bundle config --global silence_root_warning 1
RUN bundle install

ADD config.yaml .
ADD *.rb ./
ADD datasources datasources
