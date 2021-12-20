# Copyright 2019-2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

# This version of keydb does NOT build with Lua 5.2 or newer at this time:
#  - 5.3 and 5.4 give:
# lua_bit.c:83:2: error: #error "Unknown number type, check LUA_NUMBER_* in luaconf.h"
#  - 5.2 fails with:
# scripting.c:(.text+0x1f9b): undefined reference to `lua_open'
#    because lua_open became lua_newstate in 5.2
LUA_COMPAT=( lua5-1 luajit )

inherit autotools flag-o-matic lua-single systemd toolchain-funcs

MY_PN=KeyDB

DESCRIPTION="A persistent caching system, key-value and data structures database"
HOMEPAGE="https://keydb.dev https://github.com/EQ-Alpha/KeyDB"

if [[ ${PV} == 9999* ]] ; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/EQ-Alpha/${MY_PN}.git"
	EGIT_REPO_BRANCH='unstable'
else
	SRC_URI="https://github.com/EQ-Alpha/${MY_PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="amd64 ~x86"
	S="${WORKDIR}/${MY_PN}-${PV}"
fi

LICENSE="BSD"
SLOT="0"
IUSE="+jemalloc tcmalloc test"

RESTRICT="!test? ( test )"

RDEPEND="
	${LUA_DEPS}
	acct-group/keydb
	acct-user/keydb
	net-misc/curl[ssl]
	jemalloc? ( dev-libs/jemalloc:= )
	tcmalloc? ( dev-util/google-perftools )"

DEPEND="${RDEPEND}
	test? ( dev-lang/tcl:0= )"
BDEPEND="virtual/pkgconfig"

REQUIRED_USE="?? ( jemalloc tcmalloc )
	${LUA_REQUIRED_USE}"

PATCHES=(
	"${FILESDIR}/${PN}-6.0.8-config.patch"
	"${FILESDIR}/${PN}-5.3-shared.patch"
	"${FILESDIR}/${PN}-6.2.0-sharedlua.patch"
	"${FILESDIR}/${PN}-sentinel-5.0-config.patch"
)

src_prepare() {
	default

	# Copy lua modules into build dir
	cp "${S}"/deps/lua/src/{fpconv,lua_bit,lua_cjson,lua_cmsgpack,lua_struct,strbuf}.c "${S}"/src || die
	cp "${S}"/deps/lua/src/{fpconv,strbuf}.h "${S}"/src || die
	# Append cflag for lua_cjson
	# https://github.com/antirez/redis/commit/4fdcd213#diff-3ba529ae517f6b57803af0502f52a40bL61
	append-cflags "-DENABLE_CJSON_GLOBAL"

	# now we will rewrite present Makefiles
	local makefiles="" MKF
	for MKF in $(find -name 'Makefile' | cut -b 3-); do
		mv "${MKF}" "${MKF}.in"
		sed -i -e 's:$(CC):@CC@:g' \
			-e 's:$(CFLAGS):@AM_CFLAGS@:g' \
			-e 's:$(CXX):@CXX@:g' \
			-e 's:$(CXXFLAGS):@AM_CXXFLAGS@:g' \
			-e 's: $(DEBUG)::g' \
			-e 's: $(DEBUG_FLAGS)::g' \
			-e 's:$(R_CFLAGS):$(CFLAGS):g' \
			-e 's:$(R_LDFLAGS):$(LDFLAGS):g' \
			-e 's:$(OPTIMIZATION)::g' \
			-e 's:$(OBJARCH)::g' \
			-e 's:ARCH:TARCH:g' \
			-e '/^CCOPT=/s:$: $(LDFLAGS):g' \
			"${MKF}.in" \
		|| die "Sed failed for ${MKF}"
		makefiles+=" ${MKF}"
	done
	# autodetection of compiler and settings; generates the modified Makefiles
	cp "${FILESDIR}"/configure.ac-3.2 configure.ac || die

	# Use the correct pkgconfig name for Lua
	# The upstream configure script handles luajit specially, and is not
	# effected by these changes.
	sed -i	\
		-e "/^AC_INIT/s|, [0-9].+, |, $PV, |" \
		-e "s:AC_CONFIG_FILES(\[Makefile\]):AC_CONFIG_FILES([${makefiles}]):g" \
		-e "/PKG_CHECK_MODULES.*\<LUA\>/s,lua5.1,${ELUA},g" \
		configure.ac || die "Sed failed for configure.ac"

	eautoreconf
}

src_configure() {
	econf $(use_with lua_single_target_luajit luajit)
}

src_compile() {
	tc-export CC AR RANLIB

	local myconf=""

	if use jemalloc; then
		myconf="MALLOC=jemalloc"
	elif use tcmalloc; then
		myconf="MALLOC=tcmalloc"
	else
		myconf="MALLOC=libc"
	fi

	emake ${myconf} V=1 CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" USEASM=false
}

src_install() {
	insinto /etc/keydb
	doins keydb.conf sentinel.conf
	use prefix || fowners keydb:keydb /etc/keydb/{keydb,sentinel}.conf
	fperms 0644 /etc/keydb/{keydb,sentinel}.conf

	# TODO: rc initd and confd
	# TODO: systemd
	# TODO: logrotate

	dodoc 00-RELEASENOTES BUGS README.md

	dobin src/keydb-cli
	dosbin src/keydb-{benchmark,server,check-aof,check-rdb}
	fperms 0750 /usr/sbin/keydb-benchmark
	dosym keydb-server /usr/sbin/keydb-sentinel

	if use prefix; then
		diropts -m0750
	else
		diropts -m0750 -o keydb -g keydb
	fi

	keepdir /var/{log,lib}/keydb
}
