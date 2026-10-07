"""Ephemeral test CA; only a disposable COPY of the validator trusts this CA."""
from pathlib import Path
import shutil
import subprocess


def certificates(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)

    def run(*args):
        subprocess.run(['openssl', *map(str, args)], check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=20)

    ca, ca_key = directory / 'ca.pem', directory / 'ca.key'
    run('req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
        '-keyout', ca_key, '-out', ca, '-days', '90', '-subj', '/CN=Isolated Test Root',
        '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
    intermediate, intermediate_key = directory / 'intermediate.pem', directory / 'intermediate.key'
    for name, issuer, issuer_key, days, extensions in (
        ('intermediate', ca, ca_key, 60, 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n'),
        ('valid', intermediate, intermediate_key, 30, 'basicConstraints=critical,CA:FALSE\nsubjectAltName=DNS:cdn.example.com\nextendedKeyUsage=serverAuth\n'),
        ('near-expiry', intermediate, intermediate_key, 1, 'basicConstraints=critical,CA:FALSE\nsubjectAltName=DNS:cdn.example.com\nextendedKeyUsage=serverAuth\n'),
        ('expired', intermediate, intermediate_key, 0, 'basicConstraints=critical,CA:FALSE\nsubjectAltName=DNS:cdn.example.com\nextendedKeyUsage=serverAuth\n'),
    ):
        key, csr, cert, ext = [directory / (name + suffix) for suffix in ('.key', '.csr', '.pem', '.ext')]
        ext.write_text(extensions)
        run('req', '-new', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
            '-keyout', key, '-out', csr, '-subj', '/CN=' + name)
        run('x509', '-req', '-in', csr, '-CA', issuer, '-CAkey', issuer_key, '-CAcreateserial',
            '-out', cert, '-days', days, '-extfile', ext)
        if name != 'intermediate':
            (directory / (name + '-fullchain.pem')).write_bytes(cert.read_bytes() + intermediate.read_bytes())
    return ca


def prepare_copy(root, destination, ca):
    scripts = Path(destination) / 'scripts'
    scripts.mkdir(parents=True, exist_ok=True)
    for name in ('prepare-node-files.sh', 'check-policy.sh', 'check-public-cert.sh', 'prepare-website.py', 'news_site.py'):
        shutil.copy2(Path(root) / 'scripts' / name, scripts / name)
    checker = scripts / 'check-public-cert.sh'
    checker.write_text(checker.read_text().replace('/etc/ssl/certs/ca-certificates.crt', str(ca)))
    return scripts
