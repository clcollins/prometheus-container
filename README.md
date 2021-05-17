# Prometheus

Prometheus - metrics - visibility

## Build a Prometheus container image

The Prometheus project publishes its own container image, `quay.io/prometheus/prometheus`, but I enjoy building my own for home projects, and prefer to use the [Red Hat Universal Base Image](https://www.redhat.com/en/blog/introducing-red-hat-universal-base-image) family for my own projects.
These images are freely available for anyone to use.
My preference is the [Universal Base Image 8 minimal](https://catalog.redhat.com/software/containers/ubi8/ubi-minimal/5c359a62bed8bd75a2c3fba8)(ubi8-minimal), based on Red Hat Enterprise Linux 8.
The ubi8-minimal image is a smaller version than the normal ubi8 images, though it is larger than the extra-sparse "busybox" image used by the official Prometheus container image.
However, since I use the Universal Base Image for other projects, that layer is a wash in terms of disk space for me.
(If two images use the same layer, that layer is shared between them, and doesn't use any additional disk space after the first image.)

My `Containerfile` is split into a [multi-stage build](https://docs.docker.com/develop/develop-images/multistage-build/).
The first, builder, image installs a few tools via DNF packages, to make downloading and extracting a Prometheus release from Github easier, then downloads a specific release for whatever architecture I need (either arm64 for a RaspberryPi Kubernetes cluster, or amd64 for running locally on my laptop) and extracts it.

```txt
# The first stage build, downloading Prometheus from Github and extracting it

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
```

The second stage of the multi-stage build copies the extracted Prometheus files to a pristine ubi8-minimal image (no need for the extra tools from the first image!), and links the binaries into the `$PATH`.

```txt
# Build the final image
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

EXPOSE 9090
VOLUME ["/prometheus/data"]

ENTRYPOINT ["prometheus"]
CMD ["--config.file=prometheus.yml"]
```

After building this image, it is time to run Prometheus locally and start collecting some metrics!

## Running Prometheus

```shell
# Run Prometheus locally, using the ./data directory for persistent data storage
# Note that the image name, prometheus:latest, will be whatever image you are using
podamn run --mount=type=bind,src=$(pwd)/data,dst=/prometheus/data,relabel=shared --publish=127.0.0.1:9090:9090 --detach prometheus:latest
```

With this, Prometheus is running locally and can be viewed


## Add some data

podman run --net="host" --pid="host" --mount=type=bind,src=/,dst=/host,ro=true,bind-propagation=rslave --detach quay.io/prometheus/node-exporter:latest --path.rootfs=/host


http://127.0.0.1:9100/metrics



Check in prometheus: http://127.0.0.1:9090/targets - you should see prometheus monitoring itself (inside the container), as well as the target you added for the host with the node_exporter. Clicking on the link will show the raw data:

```txt
# NOTE: Truncated for brevity
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 3.6547e-05
go_gc_duration_seconds{quantile="0.25"} 0.000107517
go_gc_duration_seconds{quantile="0.5"} 0.00017582
go_gc_duration_seconds{quantile="0.75"} 0.000503352
go_gc_duration_seconds{quantile="1"} 0.008072206
go_gc_duration_seconds_sum 0.029700021
go_gc_duration_seconds_count 55
```



http://127.0.0.1:9090/graph?g0.expr=rate(node_network_receive_bytes_total%7B%7D%5B5m%5D)&g0.tab=0&g0.stacked=0&g0.range_input=15m


Now, with this information, we can start to create our own rules, and instrument our own applications to provide metrics for Prometheus to consume!

## Conclusion

Prometheus consumes metrics by scraping endpoints for specially formatted data. Data is tracked and can be queried for PIT info, or graphed to show changes over time.  Even better, Prometheus supports, out of the box, alerting rules that can hook in with your infrastructure in a variety of way. Prometheus can also be used as a data source for other projects, like Grafana, to provide more sophisticated graphing information.

In the real world, at work, we use Prometheus to track metrics and provide alert thresholds that page us when clusters are unhealthy, and we use Grafana to make dashboards of data we need to view regularly. We export node data to track our nodes, and instrument our operators to allow us to track their proformance and health. Prometheus is the backbone of all of it