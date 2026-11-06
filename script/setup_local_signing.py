#!/usr/bin/env python3
"""Create/reuse one private local identity. Never create a new one per build."""
import base64
import datetime
import json
import os
from pathlib import Path
import re
import secrets
import subprocess

ROOT = Path(__file__).resolve().parent.parent
DIRECTORY = Path.home() / "Library/Application Support/FacePause/Signing"
METADATA = DIRECTORY / "identity.json"
NAME = "FacePause Local Signing"

if METADATA.exists():
    print("Existing local signing configuration retained.")
    raise SystemExit(0)

listing = subprocess.check_output(["security", "find-identity", "-p", "codesigning"], text=True)
matches = re.findall(r'([0-9A-Fa-f]{40}) "' + re.escape(NAME) + '"', listing)
if matches:
    fingerprint = matches[0].upper()
else:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives.serialization import pkcs12
    from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, NAME)])
    now = datetime.datetime.now(datetime.timezone.utc)
    certificate = (
        x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
        .public_key(private_key.public_key()).serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=3650))
        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
        .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False,
            key_encipherment=False, data_encipherment=False, key_agreement=False,
            key_cert_sign=True, crl_sign=True, encipher_only=False, decipher_only=False), critical=True)
        .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CODE_SIGNING]), critical=True)
        .sign(private_key, hashes.SHA256())
    )
    fingerprint = certificate.fingerprint(hashes.SHA1()).hex().upper()
    passphrase = secrets.token_urlsafe(32)
    blob = pkcs12.serialize_key_and_certificates(NAME.encode(), private_key, certificate, None,
        serialization.BestAvailableEncryption(passphrase.encode()))
    target = ROOT / ".build/signing/import-identity"
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(ROOT / "Support/ImportSigningIdentity.swift"), "-o", str(target)], check=True)
    packet = json.dumps({"p12": base64.b64encode(blob).decode(), "passphrase": passphrase}).encode()
    subprocess.run([str(target)], input=packet, check=True)

DIRECTORY.mkdir(parents=True, exist_ok=True, mode=0o700)
os.chmod(DIRECTORY, 0o700)
METADATA.write_text(json.dumps({"name": NAME, "sha1": fingerprint, "bundle_id": "local.facepause.mac"}, indent=2))
os.chmod(METADATA, 0o600)
print("Stable local signing configured. Public certificate fingerprint saved; private key stays in login keychain.")
