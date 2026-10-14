# The telemetry receiver (tools/telemetry/server.py): standard library only.
#   docker build -t ashes-telemetry tools/telemetry
#   docker run -p 8930:8930 -v "$PWD/build/telemetry:/data" -e TELEMETRY_TOKEN=... ashes-telemetry
FROM python:3.12-alpine
WORKDIR /app
COPY server.py .
RUN adduser -D -H telemetry && mkdir /data && chown telemetry /data
USER telemetry
ENV TELEMETRY_DATA=/data PORT=8930
EXPOSE 8930
VOLUME /data
CMD ["python3", "-u", "server.py"]
