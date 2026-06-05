# rest-traffic

Test utility for [nwaku](https://github.com/waku-org/nwaku).
Given the REST API endpoint, it injects traffic with a given message size at a given rate.

See usage:
```
uv run traffic.py --help
```

Use with docker:
```
    build:
      context: ./tools/traffic-post
      dockerfile: Dockerfile
```

Run outside docker:
```
IP=$(docker inspect logos-delivery-simulator-nwaku-1 -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
uv run traffic.py --single-node=http://$IP:8645
```


