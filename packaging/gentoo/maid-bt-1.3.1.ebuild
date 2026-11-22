# Copyright 2026 Maidware Project
# Distributed under the terms of the MIT License

EAPI=8

DESCRIPTION="Bluetooth earbuds switcher for Linux (PC/phone/off, warm-link, watcher)"
HOMEPAGE="https://github.com/Maidware-Project/Maid-BT"
SRC_URI="https://github.com/Maidware-Project/Maid-BT/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="kde"

RDEPEND="
	dev-lang/python
	net-wireless/bluez
	sys-apps/util-linux
	x11-libs/libnotify
	media-sound/pulseaudio-utils
	dev-python/dbus-python
	dev-python/pygobject
	kde? ( kde-misc/kdeconnect )
"

S="${WORKDIR}/Maid-BT-${PV}"

src_install() {
	DESTDIR="${D}" bash install.sh --prefix=/usr --no-packages --no-config || die
}
