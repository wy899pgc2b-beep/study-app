#!/usr/bin/env python3
"""TestFlight に送るための署名(配布用の証明書と App Store 用のプロファイル)を、App Store Connect の API で用意する。

Mac を持っていなくても GitHub Actions だけで署名できるようにする(決定事項 D-16)。
証明書の鍵は、API キー(.p8)から毎回同じものを作る。そのため鍵をどこにも保存せずに、同じ証明書を使い続けられる。
証明書は最初の 1 回(と期限切れの後)だけ作り、取り消さない(取り消すと、審査前の版が無効になることがあるため)。

鍵は App Store Connect の API キー(Admin の権限)。次の環境変数で渡す:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH(.p8 のファイル)

使い方:
  asc_signing.py create --bundle-id com.example.app --out DIR   # DIR に distribution.p12・p12-password・プロファイルを書く
      [--extensions ShieldConfiguration,ShieldAction,Monitor]   # スマホ制限の拡張(Bundle ID はアプリの後ろにつける)も署名する
  asc_signing.py self-test                                       # 鍵を使わずに、作り方だけを確かめる

DIR には、Xcode の設定(profiles.xcconfig:TK_APP_PROFILE・TK_PROFILE_<拡張>)と、
書き出しの設定に入れる Bundle ID とプロファイルの対応(export-profiles.json)も書く。
"""

import argparse
import base64
import datetime
import hashlib
import hmac
import json
import os
import re
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"
KEY_LABEL = b"tsukuelog-apple-distribution-rsa-v1"


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def token(key_id, issuer_id, private_key_pem):
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        private_key_pem,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class Client:
    def __init__(self, key_id, issuer_id, private_key_pem):
        self.auth = token(key_id, issuer_id, private_key_pem)

    def call(self, method, path, body=None):
        req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body is not None else None)
        req.add_header("Authorization", "Bearer " + self.auth)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as res:
                raw = res.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            raise ApiError(e.code, f"{method} {path}: HTTP {e.code} {detail}") from None


# ---------------------------------------------------------------- 鍵

def derive_rsa_key(secret, bits=2048):
    """secret から、いつも同じ RSA の鍵を作る(素数は決まった乱数の列から探す。Miller-Rabin を 40 回)"""
    seed = hmac.new(secret, KEY_LABEL, hashlib.sha256).digest()
    counter = 0

    def rand_bits(n):
        nonlocal counter
        out = b""
        while len(out) * 8 < n:
            out += hashlib.sha256(seed + counter.to_bytes(8, "big")).digest()
            counter += 1
        return int.from_bytes(out, "big") >> (len(out) * 8 - n)

    small = [p for p in range(3, 2000, 2) if all(p % d for d in range(3, int(p**0.5) + 1, 2))]

    def probable_prime(n):
        if any(n % p == 0 for p in small):
            return False
        d, r = n - 1, 0
        while d % 2 == 0:
            d //= 2
            r += 1
        for _ in range(40):
            a = 2 + rand_bits(n.bit_length() - 2) % (n - 3)
            x = pow(a, d, n)
            if x in (1, n - 1):
                continue
            for _ in range(r - 1):
                x = pow(x, 2, n)
                if x == n - 1:
                    break
            else:
                return False
        return True

    e = 65537

    def prime(half):
        while True:
            # 上の 2 ビットを立てて、掛けたときに bits ちょうどになるようにする
            c = rand_bits(half) | (3 << (half - 2)) | 1
            if (c - 1) % e != 0 and probable_prime(c):
                return c

    p = prime(bits // 2)
    q = prime(bits // 2)
    while q == p or abs(p - q).bit_length() < bits // 2 - 100:
        q = prime(bits // 2)
    n = p * q
    lam = (p - 1) * (q - 1) // _gcd(p - 1, q - 1)
    d = pow(e, -1, lam)
    numbers = rsa.RSAPrivateNumbers(
        p=p, q=q, d=d, dmp1=rsa.rsa_crt_dmp1(d, p), dmq1=rsa.rsa_crt_dmq1(d, q), iqmp=rsa.rsa_crt_iqmp(p, q),
        public_numbers=rsa.RSAPublicNumbers(e, n),
    )
    return numbers.private_key()


def _gcd(a, b):
    while b:
        a, b = b, a % b
    return a


def csr_pem(key):
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "TsukueLog CI")]))
        .sign(key, hashes.SHA256())
    )
    return csr.public_bytes(serialization.Encoding.PEM).decode()


def public_der(public_key):
    return public_key.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)


def make_p12(key, cert_der, password):
    cert = x509.load_der_x509_certificate(cert_der)
    # macOS の security コマンドが読める、古い形式(3DES・SHA1)で暗号化する
    enc = (
        serialization.PrivateFormat.PKCS12.encryption_builder()
        .kdf_rounds(50000)
        .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
        .hmac_hash(hashes.SHA1())
        .build(password.encode())
    )
    return pkcs12.serialize_key_and_certificates(b"distribution", key, cert, None, enc)


# ---------------------------------------------------------------- App Store Connect

def not_expiring(iso, days=2):
    if not iso:
        return True
    end = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return end > datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=days)


def find_or_create_certificate(client, key):
    """この鍵の配布用の証明書を探す。なければ作る"""
    mine = public_der(key.public_key())
    q = urllib.parse.urlencode({"filter[certificateType]": "DISTRIBUTION", "limit": "200"})
    for item in client.call("GET", f"/certificates?{q}").get("data", []):
        attrs = item["attributes"]
        content = attrs.get("certificateContent")
        if not content or not not_expiring(attrs.get("expirationDate")):
            continue
        cert = x509.load_der_x509_certificate(base64.b64decode(content))
        if public_der(cert.public_key()) == mine:
            print("前に作った証明書を使います")
            return item["id"], base64.b64decode(content)
    try:
        body = {"data": {"type": "certificates", "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr_pem(key)}}}
        item = client.call("POST", "/certificates", body)["data"]
    except ApiError as e:
        if e.status == 409:
            sys.exit(
                "配布用の証明書が上限に達しています。Apple Developer の「Certificates, Identifiers & Profiles」で、"
                "使っていない Apple Distribution の証明書を 1 つ取り消してから、もう一度実行してください。\n" + str(e)
            )
        raise
    print("配布用の証明書を作りました")
    return item["id"], base64.b64decode(item["attributes"]["certificateContent"])


def find_or_create_bundle_id(client, identifier, name="TsukueLog"):
    q = urllib.parse.urlencode({"filter[identifier]": identifier, "limit": "200"})
    for item in client.call("GET", f"/bundleIds?{q}").get("data", []):
        if item["attributes"]["identifier"] == identifier:
            return item["id"]
    body = {"data": {"type": "bundleIds", "attributes": {"identifier": identifier, "name": name, "platform": "IOS"}}}
    print(f"Bundle ID {identifier} を登録しました")
    return client.call("POST", "/bundleIds", body)["data"]["id"]


def find_or_create_profile(client, bundle, bundle_identifier, cert_id):
    """この証明書を含む、有効な App Store 用のプロファイルを探す。なければ作る(同じ名前の古いものは消す)"""
    name = f"TsukueLog CI {bundle_identifier}"
    q = urllib.parse.urlencode({"filter[name]": name, "filter[profileType]": "IOS_APP_STORE", "limit": "200"})
    for item in client.call("GET", f"/profiles?{q}").get("data", []):
        attrs = item["attributes"]
        certs = client.call("GET", f"/profiles/{item['id']}/certificates").get("data", [])
        usable = attrs.get("profileState") == "ACTIVE" and not_expiring(attrs.get("expirationDate")) and any(c["id"] == cert_id for c in certs)
        if usable:
            print("前に作ったプロファイルを使います")
            return item
        client.call("DELETE", f"/profiles/{item['id']}")
    body = {
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            },
        }
    }
    print("プロファイルを作りました")
    return client.call("POST", "/profiles", body)["data"]


def output(name, value):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as f:
            f.write(f"{name}={value}\n")


def profile_var(suffix):
    """拡張の名前から、プロファイルを渡す Xcode の設定の名前を作る(ShieldConfiguration → TK_PROFILE_SHIELD_CONFIGURATION)"""
    return "TK_PROFILE_" + re.sub(r"(?<!^)(?=[A-Z])", "_", suffix).upper()


def signing_targets(bundle_identifier, extensions):
    """署名するもの(Bundle ID、Bundle ID の名前、プロファイルを渡す設定の名前)。アプリと、スマホ制限の拡張"""
    targets = [(bundle_identifier, "TsukueLog", "TK_APP_PROFILE")]
    for suffix in extensions:
        targets.append((f"{bundle_identifier}.{suffix}", f"TsukueLog {suffix}", profile_var(suffix)))
    return targets


def create(client, key, bundle_identifier, extensions, out):
    os.makedirs(out, exist_ok=True)
    cert_id, cert_der = find_or_create_certificate(client, key)
    lines = []
    export = {}
    for identifier, name, var in signing_targets(bundle_identifier, extensions):
        bundle = find_or_create_bundle_id(client, identifier, name)
        attrs = find_or_create_profile(client, bundle, identifier, cert_id)["attributes"]
        with open(os.path.join(out, f"{attrs['uuid']}.mobileprovision"), "wb") as f:
            f.write(base64.b64decode(attrs["profileContent"]))
        lines.append(f"{var} = {attrs['name']}")
        export[identifier] = attrs["name"]
    password = secrets.token_urlsafe(24)
    with open(os.path.join(out, "distribution.p12"), "wb") as f:
        f.write(make_p12(key, cert_der, password))
    with open(os.path.join(out, "p12-password"), "w") as f:
        f.write(password)
    with open(os.path.join(out, "profiles.xcconfig"), "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(out, "export-profiles.json"), "w") as f:
        json.dump(export, f, indent=2)
    output("profile_name", export[bundle_identifier])


# ---------------------------------------------------------------- 確かめ

def self_test():
    ec_key = ec.generate_private_key(ec.SECP256R1())
    pem = ec_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    t = token("ABC123DEFG", "00000000-0000-0000-0000-000000000000", pem)
    claims = jwt.decode(t, ec_key.public_key(), algorithms=["ES256"], audience="appstoreconnect-v1")
    assert claims["iss"] == "00000000-0000-0000-0000-000000000000"
    assert jwt.get_unverified_header(t)["kid"] == "ABC123DEFG"
    assert claims["exp"] - claims["iat"] <= 20 * 60, "トークンの有効期限は 20 分まで"

    started = time.time()
    key = derive_rsa_key(pem)
    again = derive_rsa_key(pem)
    other = derive_rsa_key(pem + b"x")
    assert key.key_size == 2048
    assert public_der(key.public_key()) == public_der(again.public_key()), "同じ API キーからは同じ鍵"
    assert public_der(key.public_key()) != public_der(other.public_key()), "違う API キーからは違う鍵"
    sig = key.sign(b"tsukuelog", padding.PKCS1v15(), hashes.SHA256())
    key.public_key().verify(sig, b"tsukuelog", padding.PKCS1v15(), hashes.SHA256())
    assert x509.load_pem_x509_csr(csr_pem(key).encode()).is_signature_valid

    # 自分で署名した証明書で p12 を作り、読み戻す
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "test")])
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(1)
        .not_valid_before(datetime.datetime(2026, 1, 1))
        .not_valid_after(datetime.datetime(2027, 1, 1))
        .sign(key, hashes.SHA256())
    )
    p12 = make_p12(key, cert.public_bytes(serialization.Encoding.DER), "pw")
    k2, c2, _ = pkcs12.load_key_and_certificates(p12, b"pw")
    assert c2 == cert and k2.private_numbers() == key.private_numbers()
    assert not_expiring("2099-01-01T00:00:00.000+00:00") and not not_expiring("2020-01-01T00:00:00.000+00:00")
    assert profile_var("ShieldConfiguration") == "TK_PROFILE_SHIELD_CONFIGURATION"
    assert profile_var("Monitor") == "TK_PROFILE_MONITOR"
    t = signing_targets("jp.example.app", ["ShieldAction"])
    assert t == [("jp.example.app", "TsukueLog", "TK_APP_PROFILE"), ("jp.example.app.ShieldAction", "TsukueLog ShieldAction", "TK_PROFILE_SHIELD_ACTION")]
    print(f"self-test OK ({time.time() - started:.1f} 秒)")
    return p12


def main():
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=["create", "self-test"])
    p.add_argument("--bundle-id")
    p.add_argument("--out", default="signing")
    p.add_argument("--extensions", default="", help="スマホ制限の拡張(カンマ区切り)")
    a = p.parse_args()
    if a.command == "self-test":
        self_test()
        return
    if not a.bundle_id:
        p.error("--bundle-id が必要です")
    with open(os.environ["ASC_KEY_PATH"], "rb") as f:
        pem = f.read()
    client = Client(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], pem)
    extensions = [e for e in a.extensions.split(",") if e]
    create(client, derive_rsa_key(pem), a.bundle_id, extensions, a.out)


if __name__ == "__main__":
    main()
