#!/usr/bin/env python3
"""Generate fake provisioning profiles for ProxyTelegram with custom bundle ID."""

import os
import subprocess
import sys
import tempfile
import uuid

TEAM_ID = "FAKETEAMID"
BUNDLE_ID = "com.aleksandr.ProxyTelegram"
APP_NAME = "ProxyTelegram"

# Profile name -> bundle_id suffix mapping (matches BuildConfiguration.py profile_name_mapping)
PROFILES = {
    "Telegram": "",
    "BroadcastUpload": ".BroadcastUpload",
    "Intents": ".SiriIntents",
    "NotificationContent": ".NotificationContent",
    "NotificationService": ".NotificationService",
    "Share": ".Share",
    "WatchApp": ".watchkitapp",
    "WatchExtension": ".watchkitapp.watchkitextension",
    "Widget": ".Widget",
}


def make_plist(profile_name, suffix):
    full_bundle = f"{TEAM_ID}.{BUNDLE_ID}{suffix}"
    profile_uuid = str(uuid.uuid4()).upper()

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>AppIDName</key>
\t<string>{APP_NAME}</string>
\t<key>ApplicationIdentifierPrefix</key>
\t<array>
\t\t<string>{TEAM_ID}</string>
\t</array>
\t<key>CreationDate</key>
\t<date>2026-01-01T00:00:00Z</date>
\t<key>DeveloperCertificates</key>
\t<array>
\t</array>
\t<key>Entitlements</key>
\t<dict>
\t\t<key>application-identifier</key>
\t\t<string>{full_bundle}</string>
\t\t<key>aps-environment</key>
\t\t<string>development</string>
\t\t<key>com.apple.developer.team-identifier</key>
\t\t<string>{TEAM_ID}</string>
\t\t<key>com.apple.security.application-groups</key>
\t\t<array>
\t\t\t<string>group.{BUNDLE_ID}</string>
\t\t</array>
\t\t<key>get-task-allow</key>
\t\t<true/>
\t\t<key>keychain-access-groups</key>
\t\t<array>
\t\t\t<string>{TEAM_ID}.*</string>
\t\t</array>
\t</dict>
\t<key>ExpirationDate</key>
\t<date>2030-12-31T23:59:59Z</date>
\t<key>IsXcodeManaged</key>
\t<false/>
\t<key>Name</key>
\t<string>Fake {profile_name}</string>
\t<key>Platform</key>
\t<array>
\t\t<string>iOS</string>
\t</array>
\t<key>TeamIdentifier</key>
\t<array>
\t\t<string>{TEAM_ID}</string>
\t</array>
\t<key>TeamName</key>
\t<string>Fake Team</string>
\t<key>TimeToLive</key>
\t<integer>1825</integer>
\t<key>UUID</key>
\t<string>{profile_uuid}</string>
\t<key>Version</key>
\t<integer>1</integer>
</dict>
</plist>"""


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    cert_path = os.path.join(script_dir, "fake-codesigning", "certs", "SelfSigned.p12")
    output_dir = os.path.join(script_dir, "fake-codesigning", "profiles")

    if not os.path.exists(cert_path):
        print(f"Certificate not found: {cert_path}")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)

    # Extract cert and key from p12
    with tempfile.NamedTemporaryFile(suffix=".pem", delete=False, mode="w") as pem_file:
        pem_path = pem_file.name

    try:
        subprocess.run(
            ["openssl", "pkcs12", "-in", cert_path, "-out", pem_path,
             "-nodes", "-passin", "pass:", "-legacy"],
            check=True, capture_output=True
        )
    except subprocess.CalledProcessError:
        # Try without -legacy for older openssl
        subprocess.run(
            ["openssl", "pkcs12", "-in", cert_path, "-out", pem_path,
             "-nodes", "-passin", "pass:"],
            check=True, capture_output=True
        )

    for profile_name, suffix in PROFILES.items():
        plist_xml = make_plist(profile_name, suffix)
        output_path = os.path.join(output_dir, f"{profile_name}.mobileprovision")

        with tempfile.NamedTemporaryFile(suffix=".plist", delete=False, mode="w") as plist_file:
            plist_file.write(plist_xml)
            plist_path = plist_file.name

        try:
            subprocess.run(
                ["openssl", "smime", "-sign", "-binary", "-nodetach",
                 "-in", plist_path,
                 "-outform", "der",
                 "-out", output_path,
                 "-signer", pem_path,
                 "-inkey", pem_path],
                check=True, capture_output=True
            )
            print(f"Generated: {profile_name}.mobileprovision ({BUNDLE_ID}{suffix})")
        except subprocess.CalledProcessError as e:
            print(f"Failed to generate {profile_name}: {e.stderr.decode()}")
            sys.exit(1)
        finally:
            os.unlink(plist_path)

    os.unlink(pem_path)
    print(f"\nAll {len(PROFILES)} profiles generated in {output_dir}")


if __name__ == "__main__":
    main()
