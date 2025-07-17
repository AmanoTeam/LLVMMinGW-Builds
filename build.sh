#!/bin/bash

set -eu

declare -r CURRENT_SOURCE_DIRECTORY="${PWD}"
declare -r LLVM_MINGW_SOURCE="$(mktemp --directory --dry-run)"

declare -r INSTALL_PREFIX='/tmp/llvm-mingw'
declare -r SHARE_DIRECTORY="${INSTALL_PREFIX}/usr/local/share/llvm-mingw"

declare build_type="${1}"

if [ -z "${build_type}" ]; then
	build_type='native'
fi

declare is_native='0'

if [ "${build_type}" = 'native' ]; then
	is_native='1'
fi

declare cross_compile_flags=''

if ! (( is_native )); then
	cross_compile_flags+="--host=${build_type}"
fi

if ! [ -d "${LLVM_MINGW_SOURCE}" ]; then
	git clone \
		--quiet \
		'https://github.com/mstorsjo/llvm-mingw.git' \
		"${LLVM_MINGW_SOURCE}"
	
	cd "${LLVM_MINGW_SOURCE}"
	git checkout --quiet 'f5a9041'
	
	 patch \
		--input="${CURRENT_SOURCE_DIRECTORY}/patches/llvm_mingw.patch" \
		--strip='1' \
		--directory="${LLVM_MINGW_SOURCE}"
fi

if ! (( is_native )) && ! [ -d "/usr/${build_type}" ]; then
	sudo ln --symbolic "${CROSS_COMPILE_SYSROOT}" "/usr/${build_type}"
fi

cd "${LLVM_MINGW_SOURCE}"

CHECKOUT_ONLY='1' bash './build-llvm.sh'

# Bundle both libstdc++ and libgcc within host tools
if ! (( is_native )); then
	[ -d "${INSTALL_PREFIX}/lib" ] || mkdir --parent "${INSTALL_PREFIX}/lib"
	
	# libstdc++
	declare name=$(realpath $("${CC}" --print-file-name='libstdc++.so'))
	
	# libestdc++
	if ! [ -f "${name}" ]; then
		declare name=$(realpath $("${CC}" --print-file-name='libestdc++.so'))
	fi
	
	declare soname=$("${READELF}" -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
	
	cp "${name}" "${INSTALL_PREFIX}/lib/${soname}"
	
	# OpenBSD does not have a libgcc library
	if [[ "${CROSS_COMPILE_TRIPLET}" != *'-openbsd'* ]]; then
		# libgcc_s
		declare name=$(realpath $("${CC}" --print-file-name='libgcc_s.so.1'))
		
		# libegCC
		if ! [ -f "${name}" ]; then
			declare name=$(realpath $("${CC}" --print-file-name='libegCC.so'))
		fi
		
		declare soname=$("${READELF}" -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
		
		cp "${name}" "${INSTALL_PREFIX}/lib/${soname}"
	fi
	
	sed --in-place '/export PATH/d; s|$PREFIX/bin/|/tmp/llvm-mingw-toolchain/bin/|g' \
		'./build-mingw-w64.sh' \
		'./build-mingw-w64-libraries.sh' \
		'./build-compiler-rt.sh' \
		'./build-libcxx.sh' \
		'./build-openmp.sh'
fi

bash './build-all.sh' \
	${cross_compile_flags} \
	--disable-lldb \
	--with-default-msvcrt='msvcrt' \
	"${INSTALL_PREFIX}"

mkdir --parent "${SHARE_DIRECTORY}"

cp --recursive "${CURRENT_SOURCE_DIRECTORY}/tools/dev/"* "${SHARE_DIRECTORY}"
