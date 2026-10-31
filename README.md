# docker-pana

A Docker image that bundles the tools needed to score Dart and Flutter packages
with [pana](https://pub.dev/packages/pana): the Dart and Flutter SDKs, dartdoc,
and the WebP tools. It is built for `linux/amd64`.

## Usage

Mount the package directory at `/package` read-only. Arguments are passed to
pana, and `/package` is the package to analyze.

```sh
docker run --rm --platform linux/amd64 --memory 4g \
  --mount "type=bind,src=$PWD,dst=/package,readonly" \
  ghcr.io/skw398/docker-pana:latest \
  --exit-code-threshold 0 /package
```

`--exit-code-threshold` is the number of missing points to tolerate. With `0`,
the exit code is non-zero unless the package scores the maximum.

## GitHub Actions

```yaml
- uses: skw398/docker-pana@main
  with:
    path: '.'
    exit-code-threshold: '0'
```

| Input | Default | Description |
| --- | --- | --- |
| `path` | `.` | Package path relative to the repository root |
| `exit-code-threshold` | `0` | Missing points to tolerate |
| `image` | `ghcr.io/skw398/docker-pana:latest` | Image to use; a tag or digest may be given |

## Included versions

| Tool | Version |
| --- | --- |
| Dart | 3.13.7 |
| Flutter | 3.47.8 |
| pana | 0.23.19 |
| dartdoc | 9.0.9 |
| WebP | 1.3.2 |

WebP is newer than the version the pub.dev worker pins (1.3.0), by the smallest
release that fixes its CVEs. It rarely affects scores.

## Security

This image relies on container isolation without an additional sandbox such as
gVisor. Analysis has network access by default. When analyzing untrusted
packages, use disposable runners and do not expose secrets to the container.

## License

MIT ([LICENSE](LICENSE)). The libwebp notices are in `licenses/`; the image also
includes the license files of the bundled SDKs and pub packages.
