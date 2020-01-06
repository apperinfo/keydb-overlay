# Copyright 2019-2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit autotools flag-o-matic systemd toolchain-funcs

MY_PN=KeyDB

DESCRIPTION="A persistent caching system, key-value and data structures database"
HOMEPAGE="https://keydb.dev"

if [[ ${PV} == 9999* ]] ; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/JohnSully/${MY_PN}.git"
else
	SRC_URI="https://github.com/JohnSully/${MY_PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~x86"
	S="${WORKDIR}/${MY_PN}-${PV}"
fi

LICENSE="BSD"
SLOT="0"
IUSE="+jemalloc tcmalloc luajit test"

RESTRICT="!test? ( test )"

RDEPEND="
	acct-group/redis
	acct-user/redis
	!dev-db/redis
	luajit? ( dev-lang/luajit:2 )
	!luajit? ( || ( dev-lang/lua:5.1 =dev-lang/luad-5.1*:0 ) )
	tcmalloc? ( dev-util/google-perftools )
	jemalloc? ( >=dev-libs/jemalloc-5.1:= )"

DEPEND="${RDEPEND}
	test? ( dev-lang/tcl:0= )"
BDEPEND="virtual/pkgconfig"

REQUIRED_USE="?? ( jemalloc tcmalloc )"

PATCHES=(
	"${FILESDIR}/${PN}-5.3-config.patch"
	"${FILESDIR}/${PN}-5.0-shared.patch"
	"${FILESDIR}/${PN}-5.0-sharedlua.patch"
	"${FILESDIR}/${PN}-sentinel-5.0-config.patch"
)

src_prepare() {
	eapply "${PATCHES[@]}"
	eapply_user

	# Copy lua modules into build dir
	cp "${S}"/deps/lua/src/{fpconv,lua_bit,lua_cjson,lua_cmsgpack,lua_struct,strbuf}.c "${S}"/src || die
	cp "${S}"/deps/lua/src/{fpconv,strbuf}.h "${S}"/src || die
	# Append cflag for lua_cjson
	# https://github.com/antirez/redis/commit/4fdcd213#diff-3ba529ae517f6b57803af0502f52a40bL61
	append-cflags "-DENABLE_CJSON_GLOABL"

	# now we will rewrite present Makefiles
	local makefiles="" MKF
	for MKF in $(find -name 'Makefile' | cut -b 3-); do
		mv "${MKF}" "${MKF}.in"
		sed -i -e 's:$(CC):@CC@:g' \
			-e 's:$(CFLAGS):@AM_CFLAGS@:g' \
			-e 's:$(CXX):@CXX@:g' \
			-e 's:$(CXXFLAGS):@AM_CXXFLAGS@:g' \
			-e 's: $(DEBUG)::g' \
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
	if false && has_version 'dev-lang/lua:5.3'; then
		# Lua5.3 gives:
		#lua_bit.c:83:2: error: #error "Unknown number type, check LUA_NUMBER_* in luaconf.h"
		LUAPKGCONFIG=lua5.3
	elif false && has_version 'dev-lang/lua:5.2'; then
		# Lua5.2 fails with:
		# scripting.c:(.text+0x1f9b): undefined reference to `lua_open'
		# Because lua_open because lua_newstate in 5.2
		LUAPKGCONFIG=lua5.2
	elif has_version 'dev-lang/lua:5.1'; then
		LUAPKGCONFIG=lua5.1
	else
		LUAPKGCONFIG=lua
	fi
	# The upstream configure script handles luajit specially, and is not
	# effected by these changes.
	einfo "Selected LUAPKGCONFIG=${LUAPKGCONFIG}"
	sed -i	\
		-e "/^AC_INIT/s|, [0-9].+, |, $PV, |" \
		-e "s:AC_CONFIG_FILES(\[Makefile\]):AC_CONFIG_FILES([${makefiles}]):g" \
		-e "/PKG_CHECK_MODULES.*\<LUA\>/s,lua5.1,${LUAPKGCONFIG},g" \
		configure.ac || die "Sed failed for configure.ac"

	eautoreconf
}

src_configure() {
	local myeconfargs=(
		$(use_with luajit)
	)
	econf "${myeconfargs[@]}"

	# Linenoise can't be built with -std=c99, see https://bugs.gentoo.org/451164
	# also, don't define ANSI/c99 for lua twice
	sed -i -e "s:-std=c99::g" deps/linenoise/Makefile deps/Makefile || die
}

src_compile() {
	tc-export CC AR RANLIB

	local myconf=""

	if use tcmalloc; then
		myconf="${myconf} USE_TCMALLOC=yes"
	elif use jemalloc; then
		myconf="${myconf} JEMALLOC_SHARED=yes"
	else
		myconf="${myconf} MALLOC=yes"
	fi

	emake ${myconf} V=1 CC="${CC}" AR="${AR} rcu" RANLIB="${RANLIB}" USEASM=false
}

src_install() {
	insinto /etc/keydb
	doins keydb.conf sentinel.conf
	use prefix || fowners redis:redis /etc/keydb/{keydb,sentinel}.conf
	fperms 0644 /etc/keydb/{keydb,sentinel}.conf

	# TODO: rc initd and confd
	# TODO: systemd
	# TODO: logrotate

	dodoc 00-RELEASENOTES BUGS CONTRIBUTING README.md

	dobin src/keydb-cli
	dosbin src/keydb-{benchmark,server,check-aof,check-rdb}
	fperms 0750 /usr/sbin/keydb-benchmark
	dosym keydb-server /usr/sbin/keydb-sentinel

	if use prefix; then
		diropts -m0750
	else
		diropts -m0750 -o redis -g redis
	fi

	keepdir /var/{log,lib}/keydb
}
