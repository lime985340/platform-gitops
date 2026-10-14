#!/usr/bin/env python3
"""Check Secret Manager request metrics, then reserve this CI run's calls.

Cloud Monitoring metrics are sampled and can be delayed, so this check is a
conservative preflight, not a billing-enforced account-wide hard cap.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


DEFAULT_LIMIT = 9900
DEFAULT_MAX_PER_RUN = 6
DEFAULT_STATE_BRANCH = "secret-manager-access-budget"
STATE_PATH = ".github-state/secret-manager-access.json"
SECRET_MANAGER_SERVICE = "secretmanager.googleapis.com"
METRIC_TYPE = "serviceruntime.googleapis.com/api/request_count"
METRIC_MAX_DELAY = dt.timedelta(minutes=30)


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


def google_api_request(url: str, access_token: str):
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {access_token}",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise GitHubApiError(
            f"Google Cloud usage preflight failed with HTTP {error.code}"
        ) from None
    except (urllib.error.URLError, TimeoutError) as error:
        raise GitHubApiError(
            f"Google Cloud usage preflight request failed: {error}"
        ) from None
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise GitHubApiError("Google Cloud usage preflight returned invalid JSON") from None


def google_access_token() -> str:
    try:
        result = subprocess.run(
            ["gcloud", "auth", "print-access-token"],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        raise GitHubApiError("Could not obtain the Google Cloud access token") from None
    token = result.stdout.strip()
    if not token:
        raise GitHubApiError("Google Cloud returned an empty access token")
    return token


def list_billing_projects(billing_account_id: str, access_token: str) -> list[str]:
    projects: set[str] = set()
    page_token = None
    while True:
        query = {"pageSize": 100}
        if page_token:
            query["pageToken"] = page_token
        account = urllib.parse.quote(billing_account_id, safe="-")
        url = (
            f"https://cloudbilling.googleapis.com/v1/billingAccounts/{account}/projects?"
            f"{urllib.parse.urlencode(query)}"
        )
        response = google_api_request(url, access_token)
        for project in response.get("projectBillingInfo", []):
            project_id = project.get("projectId")
            if project_id:
                projects.add(project_id)
        page_token = response.get("nextPageToken")
        if not page_token:
            break
    if not projects:
        raise GitHubApiError("No projects were returned for the configured billing account")
    return sorted(projects)


def read_project_access_count(project_id: str, access_token: str, start: dt.datetime, end: dt.datetime) -> int:
    project = urllib.parse.quote(project_id, safe="")
    query_filter = (
        f'metric.type="{METRIC_TYPE}" '
        'AND resource.type="consumed_api" '
        f'AND resource.labels.service="{SECRET_MANAGER_SERVICE}"'
    )
    page_token = None
    total = 0
    while True:
        query = {
            "filter": query_filter,
            "interval.startTime": start.isoformat(timespec="seconds").replace("+00:00", "Z"),
            "interval.endTime": end.isoformat(timespec="seconds").replace("+00:00", "Z"),
            "view": "FULL",
            "pageSize": 100000,
        }
        if page_token:
            query["pageToken"] = page_token
        url = (
            f"https://monitoring.googleapis.com/v3/projects/{project}/timeSeries?"
            f"{urllib.parse.urlencode(query)}"
        )
        response = google_api_request(url, access_token)
        for series in response.get("timeSeries", []):
            for point in series.get("points", []):
                value = point.get("value", {}).get("int64Value", "0")
                try:
                    count = int(value)
                except (TypeError, ValueError):
                    raise GitHubApiError(
                        f"Google Cloud returned an invalid request count for project {project_id}"
                    ) from None
                if count < 0:
                    raise GitHubApiError(
                        f"Google Cloud returned a negative request count for project {project_id}"
                    )
                total += count
        page_token = response.get("nextPageToken")
        if not page_token:
            break
    return total


def read_billing_account_usage(billing_account_id: str) -> tuple[int, int]:
    token = google_access_token()
    projects = list_billing_projects(billing_account_id, token)
    now = dt.datetime.now(dt.timezone.utc)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    # Query through now. The reservation ledger below covers this CI's recent
    # calls when Monitoring has not surfaced them yet.
    count = sum(
        read_project_access_count(project, token, month_start, now)
        for project in projects
    )
    return count, len(projects)


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
        billing_account_id = os.environ["GCP_BILLING_ACCOUNT_ID"]
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
    now = dt.datetime.now(dt.timezone.utc)
    month = now.strftime("%Y-%m")

    try:
        observed, project_count = read_billing_account_usage(billing_account_id)
        ensure_state_branch(repo, branch, token)
        state, sha = read_state(repo, branch, token)
        if state is None:
            current_reserved = 0
            reservations = []
        else:
            if state.get("schema_version") not in (1, 2):
                raise GitHubApiError("Unsupported budget state schema; refusing access")
            current_reserved = state.get("reserved") if state.get("month") == month else 0
            if not isinstance(current_reserved, int) or current_reserved < 0:
                raise GitHubApiError("Invalid budget count; refusing access")
            reservations = state.get("reservations", []) if state.get("month") == month else []
            if not isinstance(reservations, list):
                raise GitHubApiError("Invalid reservation history; refusing access")

        recent_reserved = 0
        cutoff = now - METRIC_MAX_DELAY
        for reservation in reservations:
            if not isinstance(reservation, dict):
                raise GitHubApiError("Invalid reservation history; refusing access")
            try:
                reserved_at = dt.datetime.fromisoformat(
                    reservation["reserved_at"].replace("Z", "+00:00")
                )
                calls = reservation["calls"]
            except (KeyError, TypeError, ValueError):
                raise GitHubApiError("Invalid reservation history; refusing access") from None
            if not isinstance(calls, int) or calls <= 0:
                raise GitHubApiError("Invalid reservation history; refusing access")
            if reserved_at.tzinfo is None:
                raise GitHubApiError("Invalid reservation timestamp; refusing access")
            if reserved_at >= cutoff:
                recent_reserved += calls

        projected = observed + recent_reserved + args.reserve
        if projected > limit:
            print(
                f"::warning::Cloud Monitoring reports {observed} Secret Manager access "
                f"requests across {project_count} billing-account projects; recent CI "
                f"reservations add {recent_reserved}, and this run needs {args.reserve}."
            )
            print("::error::Secret Manager reads blocked before access")
            return 1

        next_state = {
            "schema_version": 2,
            "month": month,
            "reserved": current_reserved + args.reserve,
            "reservations": reservations + [
                {"reserved_at": now.isoformat(timespec="seconds").replace("+00:00", "Z"), "calls": args.reserve}
            ],
        }
        write_state(repo, branch, token, next_state, sha)
        print(
            f"Cloud Monitoring reports {observed} Secret Manager access requests "
            f"across {project_count} billing-account projects. Reserved {args.reserve} "
            f"CI calls; the guarded projection is {projected}/{limit}."
        )
        if projected == limit:
            print(
                f"::warning::The GitOps CI budget reached {limit}; "
                "subsequent Secret Manager reads will be blocked."
            )
        print(
            "Usage is estimated from project-level Cloud Monitoring metrics; "
            "Google can publish these metrics up to 30 minutes late."
        )
        return 0
    except GitHubApiError as error:
        print(f"::error::{error}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
