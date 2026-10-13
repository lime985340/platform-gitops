#!/usr/bin/env python3
"""Reserve a conservative monthly Secret Manager access budget in a GitHub branch.

The counter records only calls reserved by this GitHub Actions repository. It is
not an authoritative view of usage across the Google Cloud billing account.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


DEFAULT_LIMIT = 9900
DEFAULT_MAX_PER_RUN = 6
DEFAULT_STATE_BRANCH = "secret-manager-access-budget"
STATE_PATH = ".github-state/secret-manager-access.json"


class GitHubApiError(RuntimeError):
    pass


def api_request(method: str, path: str, token: str, payload: dict | None = None):
    api_url = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{api_url}{path}",
        data=body,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            **({"Content-Type": "application/json"} if body is not None else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
            return json.loads(data) if data else None
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        # Do not echo response bodies: the API error may contain repository data.
        raise GitHubApiError(f"GitHub API {method} failed with HTTP {error.code}") from None
    except urllib.error.URLError as error:
        raise GitHubApiError(f"GitHub API request failed: {error.reason}") from None


def encoded_branch(branch: str) -> str:
    return urllib.parse.quote(branch, safe="")


def ensure_state_branch(repo: str, branch: str, token: str) -> None:
    ref_path = f"/repos/{repo}/git/ref/heads/{encoded_branch(branch)}"
    if api_request("GET", ref_path, token) is not None:
        return

    metadata = api_request("GET", f"/repos/{repo}", token)
    if not metadata or not metadata.get("default_branch"):
        raise GitHubApiError("Could not determine the repository default branch")
    default_ref = encoded_branch(metadata["default_branch"])
    default_data = api_request(
        "GET", f"/repos/{repo}/git/ref/heads/{default_ref}", token
    )
    if not default_data or not default_data.get("object", {}).get("sha"):
        raise GitHubApiError("Could not read the repository default branch ref")

    try:
        created = api_request(
            "POST",
            f"/repos/{repo}/git/refs",
            token,
            {"ref": f"refs/heads/{branch}", "sha": default_data["object"]["sha"]},
        )
    except GitHubApiError:
        # A concurrent initializer may have created the branch between requests.
        if api_request("GET", ref_path, token) is None:
            raise
        return
    if created is None and api_request("GET", ref_path, token) is None:
        raise GitHubApiError("Could not create the budget state branch")


def read_state(repo: str, branch: str, token: str):
    encoded_path = urllib.parse.quote(STATE_PATH, safe="/")
    query = urllib.parse.urlencode({"ref": branch})
    content = api_request(
        "GET", f"/repos/{repo}/contents/{encoded_path}?{query}", token
    )
    if content is None:
        return None, None
    if content.get("type") != "file" or not content.get("content"):
        raise GitHubApiError("The budget state path is not a readable file")
    try:
        raw = base64.b64decode(content["content"], validate=False)
        state = json.loads(raw)
    except (ValueError, json.JSONDecodeError):
        raise GitHubApiError("The budget state file is invalid; refusing access") from None
    return state, content.get("sha")


def write_state(repo: str, branch: str, token: str, state: dict, sha: str | None):
    encoded_path = urllib.parse.quote(STATE_PATH, safe="/")
    content = base64.b64encode(
        (json.dumps(state, indent=2, sort_keys=True) + "\n").encode("utf-8")
    ).decode("ascii")
    payload = {
        "message": f"ci: reserve Secret Manager access budget for {state['month']}",
        "content": content,
        "branch": branch,
    }
    if sha:
        payload["sha"] = sha
    result = api_request(
        "PUT", f"/repos/{repo}/contents/{encoded_path}", token, payload
    )
    if not result or not result.get("commit", {}).get("sha"):
        raise GitHubApiError("Could not persist the budget reservation")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reserve",
        type=int,
        required=True,
        help="maximum number of Secret Manager access calls this run can make",
    )
    args = parser.parse_args()

    try:
        token = os.environ["GITHUB_TOKEN"]
        repo = os.environ["GITHUB_REPOSITORY"]
    except KeyError as error:
        print(f"::error::Missing required environment variable {error.args[0]}")
        return 2

    try:
        limit = int(os.environ.get("SECRET_MANAGER_MONTHLY_LIMIT", DEFAULT_LIMIT))
        max_per_run = int(
            os.environ.get("SECRET_MANAGER_MAX_PER_RUN", DEFAULT_MAX_PER_RUN)
        )
    except ValueError:
        print("::error::Secret Manager quota limits must be integers")
        return 2

    if limit <= 0 or max_per_run <= 0 or args.reserve <= 0:
        print("::error::Secret Manager quota limits and reservation must be positive")
        return 2
    if args.reserve > max_per_run:
        print(
            "::error::Reservation exceeds SECRET_MANAGER_MAX_PER_RUN; "
            "update the reviewed workflow limit if the job legitimately needs more"
        )
        return 2

    branch = os.environ.get("SECRET_MANAGER_BUDGET_BRANCH", DEFAULT_STATE_BRANCH)
    month = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m")

    try:
        ensure_state_branch(repo, branch, token)
        state, sha = read_state(repo, branch, token)
        if state is None:
            current = 0
        else:
            if state.get("schema_version") != 1:
                raise GitHubApiError("Unsupported budget state schema; refusing access")
            current = state.get("reserved") if state.get("month") == month else 0
            if not isinstance(current, int) or current < 0:
                raise GitHubApiError("Invalid budget count; refusing access")

        projected = current + args.reserve
        if projected > limit:
            print(
                f"::warning::Secret Manager CI budget is {current}/{limit}; "
                f"this run reserves {args.reserve} and would exceed the cap."
            )
            print("::error::Secret Manager reads blocked before access")
            return 1

        next_state = {
            "schema_version": 1,
            "month": month,
            "reserved": projected,
        }
        write_state(repo, branch, token, next_state, sha)
        print(
            f"Reserved {args.reserve} Secret Manager access calls; "
            f"monthly GitOps CI reservation is {projected}/{limit}."
        )
        if projected == limit:
            print(
                f"::warning::The GitOps CI budget reached {limit}; "
                "subsequent Secret Manager reads will be blocked."
            )
        print(
            "This ledger counts this repository's reservations only; "
            "it does not report billing-account-wide usage."
        )
        return 0
    except GitHubApiError as error:
        print(f"::error::{error}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
