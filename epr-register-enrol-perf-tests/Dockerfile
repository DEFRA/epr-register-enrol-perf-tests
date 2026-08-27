FROM ghcr.io/defra/cdp-perf-test-docker:latest

WORKDIR /opt/perftest

COPY jmeter/ ./jmeter/
COPY run-baseline.sh .


ENV S3_ENDPOINT=https://s3.eu-west-2.amazonaws.com
ENV TEST_SCENARIO=epr-register-enrol-fe-perf-tests

ENTRYPOINT [ "./run-baseline.sh", "all" ]