#!/usr/bin/env bash
# Validate public trust without printing certificate/key contents or OpenSSL errors.
set +x
set -Eeuo pipefail
umask 077
usage() { printf 'Usage: check-public-cert.sh --cert FILE --key FILE --hostname DOMAIN [--min-valid-seconds N]\nRequires a non-self-signed TLS leaf chaining to the system public CA bundle.\n'; }
cert='' key='' hostname='' minimum=1209600
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --cert|--key|--hostname|--min-valid-seconds)
            (($# >= 2)) || exit 2
            case "$1" in --cert) cert=$2;; --key) key=$2;; --hostname) hostname=$2;; --min-valid-seconds) minimum=$2;; esac
            shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ -f $cert && -f $key && $hostname =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && $minimum =~ ^[0-9]+$ ]] || { printf '[FAIL] CERT: certificate/key/domain inputs required\n' >&2; exit 2; }
exec 3>&1 4>&2
exec 1>/dev/null 2>/dev/null
work=$(mktemp -d)
ok=false
finish() {
    local code=$?
    rm -rf -- "$work"
    if [[ $ok != true ]]; then
        printf '[FAIL] CERT: public trust, hostname, expiry or key-pair validation failed; details withheld\n' >&4
        exit 1
    fi
    exit "$code"
}
trap finish EXIT
openssl x509 -in "$cert" -out "$work/leaf.pem"
subject=$(openssl x509 -in "$work/leaf.pem" -noout -subject -nameopt RFC2253)
issuer=$(openssl x509 -in "$work/leaf.pem" -noout -issuer -nameopt RFC2253)
[[ ${subject#subject=} != "${issuer#issuer=}" ]]
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt -untrusted "$cert" \
    -purpose sslserver -verify_hostname "$hostname" "$work/leaf.pem"
openssl x509 -in "$work/leaf.pem" -noout -checkend "$minimum"
openssl x509 -in "$work/leaf.pem" -pubkey -noout > "$work/cert.pub"
openssl pkey -in "$key" -passin pass: -pubout > "$work/key.pub"
cmp -s "$work/cert.pub" "$work/key.pub"
ok=true
printf '[PASS] CERT: public chain, hostname, remaining validity and key pair verified\n' >&3
