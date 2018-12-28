ARG RUBY_IMAGE
FROM ruby:${RUBY_IMAGE:-latest}

RUN mkdir /app
WORKDIR /app

ADD . /app

RUN ./bin/setup
