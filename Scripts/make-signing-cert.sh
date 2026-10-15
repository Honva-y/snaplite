#!/bin/bash
# 在登录钥匙串里创建一个自签名的代码签名证书 "SnapLite Dev"。
# 用它签名后，重新编译不会导致「屏幕录制 / 辅助功能」权限失效（ad-hoc 签名每次编译都会变）。
# 过程中系统可能弹窗要求输入登录密码以信任证书。
set -euo pipefail
NAME="SnapLite Dev"
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "证书已存在：${NAME}"; exit 0
fi
TMP=$(mktemp -d)
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# macOS 的 security 只认旧式 PKCS12 算法（SHA1 + 3DES），OpenSSL 3 默认输出它读不了
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" -passout pass:snaplite \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P snaplite -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
rm -rf "$TMP"
echo "已创建并信任证书：${NAME}。现在运行 Scripts/build-app.sh 会自动使用它。"
