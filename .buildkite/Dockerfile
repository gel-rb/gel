ARG RUBY_IMAGE
FROM ${RUBY_IMAGE:-ruby:latest}

RUN which git >/dev/null || ( \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    git \
  )

RUN mkdir -p /app/test/fixtures
WORKDIR /app

ADD Rakefile /app
RUN rake fixtures

ENV JRUBY_OPTS="--dev -J-Xmx400M"
ADD . /app

RUN ./bin/setup

CMD ["./bin/rake"]
