#!/usr/bin/env python3
"""Check that the selected OCI workload images are pullable and include ARM64."""

import base64
import json
import os
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ACCEPT = ", ".join(
    (
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    )
)


def get_json(url: str, headers: dict[str, str]) -> dict:
    request = Request(url, headers=headers)
    with urlopen(request, timeout=30) as response:
        return json.loads(response.read())


def main() -> int:
    username = os.environ.get("GHCR_READ_USERNAME", "")
    token = os.environ.get("GHCR_READ_TOKEN", "")
    if not username or not token:
        print("GHCR read credentials are not configured", file=sys.stderr)
        return 1

    basic = base64.b64encode(f"{username}:{token}".encode()).decode()
    images: set[tuple[str, str]] = set()
    for path in sorted(Path("clusters/oci-osaka/workloads").glob("*/*/environments/*/kustomization.yaml")):
        content = path.read_text(encoding="utf-8")
        match = re.search(
            r"(?ms)^images:\s*\n\s*- name:\s*(\S+)\s*\n\s*newName:\s*\S+\s*\n\s*newTag:\s*(\S+)",
            content,
        )
        if match:
            images.add((match.group(1).removeprefix("ghcr.io/"), match.group(2)))

    if not images:
        print("No OCI GHCR images were found", file=sys.stderr)
        return 1

    for image, tag in sorted(images):
        scope = urlencode({"scope": f"repository:{image}:pull", "service": "ghcr.io"})
        try:
            token_response = get_json(
                f"https://ghcr.io/token?{scope}",
                {"Authorization": f"Basic {basic}"},
            )
            bearer = token_response.get("token") or token_response.get("access_token")
            if not bearer:
                raise ValueError("GHCR did not return a pull token")
            headers = {"Authorization": f"Bearer {bearer}", "Accept": ACCEPT}
            manifest = get_json(f"https://ghcr.io/v2/{image}/manifests/{tag}", headers)
            if manifest.get("manifests"):
                platforms = {
                    f"{item.get('platform', {}).get('os')}/{item.get('platform', {}).get('architecture')}"
                    for item in manifest["manifests"]
                    if item.get("platform", {}).get("os")
                    and item.get("platform", {}).get("architecture")
                }
            else:
                digest = manifest.get("config", {}).get("digest")
                if not digest:
                    raise ValueError("GHCR returned a manifest without platform metadata")
                config = get_json(f"https://ghcr.io/v2/{image}/blobs/{digest}", headers)
                platforms = {f"{config.get('os')}/{config.get('architecture')}"}
            if "linux/arm64" not in platforms:
                raise ValueError("image does not publish linux/arm64")
            print(f"Verified {image}:{tag}: {', '.join(sorted(platforms))}")
        except HTTPError as error:
            print(f"Cannot verify {image}:{tag}: GHCR HTTP {error.code}", file=sys.stderr)
            return 1
        except (URLError, ValueError, KeyError) as error:
            print(f"Cannot verify {image}:{tag}: {error}", file=sys.stderr)
            return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
