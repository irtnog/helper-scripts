#!/bin/sh

## The following is meant to be copied and pasted into the Hyper-V
## guest console window in order to perform the Salt minion
## installation from the local package repository.
exec sh <<'EOF'
sed -i '' -e 's/"DHCP"/"SYNCDHCP"/' /etc/rc.conf
fetch --no-verify-peer https://salt.irtnog.org/packages/FreeBSD:10:amd64-production/Latest/pkg.txz
env SIGNATURE_TYPE=none pkg add pkg.txz && rm pkg.txz
mkdir -p /usr/local/etc/pkg/repos
ed <<'EOF1'
a
FreeBSD: {
enabled: no
}
.
w /usr/local/etc/pkg/repos/FreeBSD.conf
q
EOF1
ed <<'EOF2'
a
irtnog: {
url: "https://salt.irtnog.org/packages/${ABI}-production"
}
.
w /usr/local/etc/pkg/repos/irtnog.conf
q
EOF2
env SIGNATURE_TYPE=none SSL_NO_VERIFY_PEER=1 pkg install -y py27-salt ca_root_nss
ed /etc/rc.conf <<'EOF3'
a
salt_minion_enable="YES"
salt_minion_paths="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"
.
w
q
EOF3
EOF
