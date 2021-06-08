# The first build stage, downloading Prometheus from Github and extracting it
FROM registry.access.redhat.com/ubi8/ubi-minimal as builder
LABEL maintainer "Chris Collins <collins.christopher@gmail.com>"

# Install packages needed to download and extract the Prometheus release
RUN microdnf install -y gzip jq tar

# Replace the ARCH for different architecture versions, eg: "linux-arm64.tar.tz"
ENV PROMETHEUS_ARCH="linux-amd64.tar.gz"

# Replace "tag/<tag_name>" with "latest" to build whatever the latest tag is at the time
ENV PROMETHEUS_VERSION="tags/v2.27.0"
ENV PROMETHEUS="https://api.github.com/repos/prometheus/prometheus/releases/${PROMETHEUS_VERSION}"

# The checksum file for the Prometheus project is "sha256sums.txt"
ENV SUMFILE="sha256sums.txt"

RUN mkdir /prometheus
WORKDIR /prometheus

# Download the checksum
RUN /bin/sh -c "curl -sSLf $(curl -sSLf ${PROMETHEUS} -o - | jq -r '.assets[] | select(.name|test(env.SUMFILE)) | .browser_download_url') -o ${SUMFILE}"

# Download the binary tarball
RUN /bin/sh -c "curl -sSLf -O $(curl -sSLf ${PROMETHEUS} -o - | jq -r '.assets[] | select(.name|test(env.PROMETHEUS_ARCH)) |.browser_download_url')"

# Check the binary and checksum match
RUN sha256sum --check --ignore-missing ${SUMFILE}

# Extract the tarball
RUN tar --extract --gunzip --no-same-owner --strip-components=1 --directory /prometheus --file *.tar.gz

# The second build stage, creating the final image
FROM registry.access.redhat.com/ubi8/ubi-minimal
LABEL maintainer "Chris Collins <collins.christopher@gmail.com>"

# Get the binary from the builder image
COPY --from=builder /prometheus /prometheus

WORKDIR /prometheus

# Link the binary files into the $PATH
RUN ln prometheus /bin/
RUN ln promtool /bin/

# Validate prometheus binary
RUN prometheus --version

# Add dynamic target (file_sd_config) support to the prometheus config
# https://prometheus.io/docs/prometheus/latest/configuration/configuration/#file_sd_config
RUN echo -e "\n\
  - job_name: 'dynamic'\n\
    file_sd_configs:\n\
    - files:\n\
      - data/sd_config*.yaml\n\
      - data/sd_config*.json\n\
      refresh_interval: 30s\
" >> prometheus.yml

EXPOSE 9090
VOLUME ["/prometheus/data"]

ENTRYPOINT ["prometheus"]
CMD ["--config.file=prometheus.yml"]
