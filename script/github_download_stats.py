#!/usr/bin/env python3
import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.request


DEFAULT_REPO = "Backtthefuture/TokenStep"
API_ROOT = "https://api.github.com"


def fetch_json(url, token=None):
    request = urllib.request.Request(url)
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("User-Agent", "TokenStep-download-stats")
    if token:
        request.add_header("Authorization", f"Bearer {token}")

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        message = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"GitHub API failed: HTTP {error.code}\n{message}") from error


def load_releases(repo, token=None, include_prerelease=False, limit=None):
    releases = []
    page = 1
    while True:
        url = f"{API_ROOT}/repos/{repo}/releases?per_page=100&page={page}"
        batch = fetch_json(url, token=token)
        if not batch:
            break

        for release in batch:
            if release.get("draft"):
                continue
            if release.get("prerelease") and not include_prerelease:
                continue
            releases.append(release)
            if limit and len(releases) >= limit:
                return releases

        if len(batch) < 100:
            break
        page += 1

    return releases


def summarize_release(release):
    assets = release.get("assets", [])
    dmg = 0
    zip_count = 0
    other = 0
    rows = []

    for asset in assets:
        name = asset.get("name", "")
        count = int(asset.get("download_count") or 0)
        lower_name = name.lower()
        if lower_name.endswith(".dmg"):
            dmg += count
        elif lower_name.endswith(".zip"):
            zip_count += count
        else:
            other += count
        rows.append(
            {
                "asset": name,
                "downloads": count,
                "size": int(asset.get("size") or 0),
                "url": asset.get("browser_download_url", ""),
            }
        )

    return {
        "tag": release.get("tag_name", ""),
        "name": release.get("name") or release.get("tag_name", ""),
        "published_at": (release.get("published_at") or "")[:10],
        "dmg": dmg,
        "zip": zip_count,
        "other": other,
        "total": dmg + zip_count + other,
        "url": release.get("html_url", ""),
        "assets": rows,
    }


def format_number(value):
    return f"{value:,}"


def print_markdown(rows):
    totals = {
        "dmg": sum(row["dmg"] for row in rows),
        "zip": sum(row["zip"] for row in rows),
        "other": sum(row["other"] for row in rows),
        "total": sum(row["total"] for row in rows),
    }

    print("# TokenStep GitHub 下载统计")
    print()
    print(f"- Release 数量：{len(rows)}")
    print(f"- DMG 下载：{format_number(totals['dmg'])}")
    print(f"- ZIP 下载：{format_number(totals['zip'])}")
    print(f"- 总下载：{format_number(totals['total'])}")
    print()
    print("| 版本 | 发布日期 | DMG | ZIP | 其他 | 总下载 |")
    print("|---|---:|---:|---:|---:|---:|")
    for row in rows:
        print(
            "| {tag} | {published_at} | {dmg} | {zip} | {other} | {total} |".format(
                tag=row["tag"],
                published_at=row["published_at"] or "-",
                dmg=format_number(row["dmg"]),
                zip=format_number(row["zip"]),
                other=format_number(row["other"]),
                total=format_number(row["total"]),
            )
        )


def print_csv(rows):
    writer = csv.DictWriter(
        sys.stdout,
        fieldnames=["tag", "name", "published_at", "dmg", "zip", "other", "total", "url"],
    )
    writer.writeheader()
    for row in rows:
        writer.writerow({key: row[key] for key in writer.fieldnames})


def main():
    parser = argparse.ArgumentParser(description="Show GitHub Release download counts for TokenStep.")
    parser.add_argument("--repo", default=DEFAULT_REPO, help=f"GitHub repo, default: {DEFAULT_REPO}")
    parser.add_argument("--limit", type=int, help="Only show the newest N releases.")
    parser.add_argument("--include-prerelease", action="store_true", help="Include prereleases.")
    parser.add_argument(
        "--format",
        choices=["markdown", "json", "csv"],
        default="markdown",
        help="Output format.",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GITHUB_TOKEN"),
        help="GitHub token. Defaults to GITHUB_TOKEN if set.",
    )
    args = parser.parse_args()

    releases = load_releases(
        args.repo,
        token=args.token,
        include_prerelease=args.include_prerelease,
        limit=args.limit,
    )
    rows = [summarize_release(release) for release in releases]

    if args.format == "json":
        print(json.dumps(rows, ensure_ascii=False, indent=2))
    elif args.format == "csv":
        print_csv(rows)
    else:
        print_markdown(rows)


if __name__ == "__main__":
    main()
