#!/usr/bin/env python3

import argparse
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

SCOPES = [
    "https://www.googleapis.com/auth/androidpublisher"
]


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("--service-account", required=True)
    parser.add_argument("--package", required=True)
    parser.add_argument("--aab", required=True)
    parser.add_argument("--track", default="production")
    parser.add_argument("--version-name", required=True)
    parser.add_argument("--release-notes", required=True)

    args = parser.parse_args()

    credentials = service_account.Credentials.from_service_account_file(
        args.service_account,
        scopes=SCOPES,
    )

    service = build(
        "androidpublisher",
        "v3",
        credentials=credentials,
    )

    print("========================================")
    print("Google Play Release")
    print("========================================")
    print(f"Package: {args.package}")
    print(f"Version: {args.version_name}")
    print(f"Track:   {args.track}")
    print("========================================")

    # Create edit.
    edit = service.edits().insert(
        packageName=args.package,
        body={},
    ).execute()

    edit_id = edit["id"]

    print(f"Created Play edit: {edit_id}")

    # Upload AAB.
    print("Uploading AAB...")

    media = MediaFileUpload(
        args.aab,
        mimetype="application/octet-stream",
        resumable=True
    )

    bundle = service.edits().bundles().upload(
        packageName=args.package,
        editId=edit_id,
        media_body=media,
    ).execute()

    version_code = bundle["versionCode"]

    print(f"Uploaded AAB, versionCode={version_code}")

    # Read release notes.
    with open(args.release_notes, "r", encoding="utf-8") as f:
        notes = f.read().strip()

    release = {
        "versionCodes": [version_code],
        "status": "draft",
        "releaseNotes": [
            {
                "language": "en-GB",
                "text": notes,
            }
        ],
    }

    print("Assigning bundle to track...")

    service.edits().tracks().update(
        packageName=args.package,
        editId=edit_id,
        track=args.track,
        body={
            "releases": [release],
        },
    ).execute()

    print("Committing Google Play edit...")

    service.edits().commit(
        packageName=args.package,
        editId=edit_id,
    ).execute()

    print("")
    print("Google Play release created successfully.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: Google Play release failed: {exc}", file=sys.stderr)
        sys.exit(1)
