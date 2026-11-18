#!/usr/bin/env python3
"""Reject block and character device nodes in every layer of a docker save archive."""

import argparse
import json
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    args = parser.parse_args()
    device_count = 0
    layer_count = 0
    with tarfile.open(args.archive, "r:*") as archive:
        with archive.extractfile("manifest.json") as manifest_file:
            manifest = json.load(manifest_file)
        if not manifest:
            raise SystemExit("Image archive has an empty manifest.")
        layers = dict.fromkeys(layer for image in manifest for layer in image["Layers"])
        if not layers:
            raise SystemExit("Image archive has no layers.")
        for layer_name in layers:
            with archive.extractfile(layer_name) as layer_file:
                with tarfile.open(fileobj=layer_file, mode="r|*") as layer:
                    for entry in layer:
                        if entry.isblk() or entry.ischr():
                            device_count += 1
                            print(
                                f"Unsupported device node: {entry.name} "
                                f"(layer {layer_name}, device {entry.devmajor}:{entry.devminor})",
                                flush=True,
                            )
            layer_count += 1
    if device_count:
        raise SystemExit(f"Image archive contains {device_count} unsupported device node(s).")
    print(f"Checked {layer_count} layers: no block or character device nodes.")


if __name__ == "__main__":
    main()
