ARG RUBY_IMAGE
FROM ${RUBY_IMAGE:-ruby:latest}

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
  git

RUN mkdir -p /app/test/fixtures
WORKDIR /app

ADD Rakefile /app
RUN rake fixtures

ADD . /app

RUN ./bin/setup
