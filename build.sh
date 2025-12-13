#!/bin/bash

set -eu

declare -r toolchain_directory='/tmp/llvm-mingw'

declare -r CURRENT_SOURCE_DIRECTORY="${PWD}"
declare -r LLVM_MINGW_SOURCE="$(mktemp --directory --dry-run)"

declare -r SHARE_DIRECTORY="${toolchain_directory}/usr/local/share/llvm-mingw"

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
	git checkout --quiet '1ce1cf7'
	
	 patch \
		--input="${CURRENT_SOURCE_DIRECTORY}/patches/llvm_mingw.patch" \
		--strip='1' \
		--directory="${LLVM_MINGW_SOURCE}"
fi

if ! (( is_native )) && ! [ -d "/usr/${build_type}" ]; then
	sudo ln --symbolic "${OBGGCC_TOOLCHAIN}/${build_type}" "/usr/${build_type}"
fi

cd "${LLVM_MINGW_SOURCE}"

CHECKOUT_ONLY='1' bash './build-llvm.sh'

if ! (( is_native )); then
	declare cc="${build_type}-gcc"
	declare readelf='readelf'

	[ -d "${toolchain_directory}/lib" ] || mkdir "${toolchain_directory}/lib"
	
	# libestdc++
	declare name=$(realpath $("${cc}" --print-file-name='libestdc++.so'))
	
	# libstdc++
	if ! [ -f "${name}" ]; then
		declare name=$(realpath $("${cc}" --print-file-name='libstdc++.so'))
	fi
	
	declare soname=$("${readelf}" -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
	
	cp "${name}" "${toolchain_directory}/lib/${soname}"
	
	# libegcc
	declare name=$(realpath $("${cc}" --print-file-name='libegcc.so'))
	
	if ! [ -f "${name}" ]; then
		# libgcc_s
		declare name=$(realpath $("${cc}" --print-file-name='libgcc_s.so.1'))
	fi
	
	declare soname=$("${readelf}" -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
	
	cp "${name}" "${toolchain_directory}/lib/${soname}"
	
	# libatomic
	declare name=$(realpath $("${cc}" --print-file-name='libatomic.so'))
	
	declare soname=$("${readelf}" -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
	
	cp "${name}" "${toolchain_directory}/lib/${soname}"
	
	# libiconv
	declare name=$(realpath $("${cc}" --print-file-name='libiconv.so'))
	
	if [ -f "${name}" ]; then
		declare soname=$("${readelf}" -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
		cp "${name}" "${toolchain_directory}/lib/${soname}"
	fi
	
	# libcharset
	declare name=$(realpath $("${cc}" --print-file-name='libcharset.so'))
	
	if [ -f "${name}" ]; then
		declare soname=$("${readelf}" -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
		cp "${name}" "${toolchain_directory}/lib/${soname}"
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
	"${toolchain_directory}"

mkdir --parent "${SHARE_DIRECTORY}"

cp --recursive "${CURRENT_SOURCE_DIRECTORY}/tools/dev/"* "${SHARE_DIRECTORY}"
