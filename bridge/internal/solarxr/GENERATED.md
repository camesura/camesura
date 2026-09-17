# Generated code

`solarxr_protocol/` is generated from the [SolarXR Protocol](https://github.com/SlimeVR/SolarXR-Protocol)
schema at commit `00c38a6dc28070b30850a89c26b17928e56245d4`, via:

```sh
flatc --go --gen-all \
  --go-module-name github.com/camesura/camesura/bridge/internal/solarxr \
  -o . schema/all.fbs
gofmt -w solarxr_protocol
```

Do not edit these files by hand; see `bridge/README.md` for the full regeneration
steps.
