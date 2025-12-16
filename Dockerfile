FROM ruby:3.2-trixie

RUN apt update -y && apt install -y \
    build-essential \
    bundler \
    clang \
    git \
    libgeos-dev \
    libyaml-dev \
    ruby-dev \
    ruby-json \
    unzip

RUN wget https://install.duckdb.org/v1.4.3/libduckdb-linux-amd64.zip && \
    unzip libduckdb-linux-amd64.zip -d libduckdb && \
    mv libduckdb/duckdb.* /usr/local/include/ && \
    mv libduckdb/libduckdb.so /usr/local/lib && \
    rm -fr libduckdb-linux-amd64.zip libduckdb

ADD Gemfile .
ADD Gemfile.lock .
RUN bundle config --global silence_root_warning 1
RUN bundle install

RUN bundle exec ruby -e "require 'duckdb'; DuckDB::Database.open.connect.query('INSTALL httpfs');"

ADD *.rb ./
ADD datasources datasources

RUN date -u +"%Y-%m-%dT%H:%M:%SZ" > .build

ENV LC_ALL=C.utf8
ENV LANG=C.utf8
