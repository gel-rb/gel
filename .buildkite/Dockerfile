ARG RUBY_IMAGE
FROM ${RUBY_IMAGE:-ruby:latest}

RUN (which git >/dev/null && which curl >/dev/null) || ( \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    git \
    curl \
  )

RUN mkdir -p /app/test/fixtures
WORKDIR /app

ADD tasks/fixtures.rake /app/tasks/fixtures.rake
RUN rake -f tasks/fixtures.rake fixtures

ENV JRUBY_OPTS="--dev -J-Xmx1800M"
ADD . /app

RUN ./bin/setup

CMD ["./bin/rake"]
