#!/bin/bash

set -eu

declare -r CURRENT_SOURCE_DIRECTORY="${PWD}"

declare -r LLVM_MINGW_SOURCE="$(mktemp --directory --dry-run)"

declare -r INSTALL_PREFIX='/tmp/llvm-mingw'

declare build_type="${1}"

if [ -z "${build_type}" ]; then
	build_type='native'
fi

declare is_native='0'

if [ "${build_type}" == 'native' ]; then
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
	git checkout --quiet 'dc3e0ec'
	
	 patch \
		--input="${CURRENT_SOURCE_DIRECTORY}/patches/llvm_mingw.patch" \
		--strip='1' \
		--directory="${LLVM_MINGW_SOURCE}"
fi

if ! (( is_native )) && ! [ -d "/usr/${build_type}" ]; then
	sudo ln --symbolic "${OBGGCC_TOOLCHAIN}/${build_type}" "/usr/${build_type}"
fi

cd "${LLVM_MINGW_SOURCE}"

CHECKOUT_ONLY='1' /proc/self/exe './build-llvm.sh'

# patch --input="${CURRENT_SOURCE_DIRECTORY}/patches/project_llvm.patch" --strip=1 --directory='./llvm-project'

if ! (( is_native )); then
	[ -d "${INSTALL_PREFIX}/lib" ] || mkdir --parent "${INSTALL_PREFIX}/lib"
	
	# libstdc++.so
	declare name=$(realpath $("${build_type}-gcc" --print-file-name='libstdc++.so'))
	declare soname=$(readelf -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
	
	[ -f "${INSTALL_PREFIX}/lib/${soname}" ] || cp "${name}" "${INSTALL_PREFIX}/lib/${soname}"
	
	# libgcc_s.so
	declare name=$(realpath $("${build_type}-gcc" --print-file-name='libgcc_s.so.1'))
	declare soname=$(readelf -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
	
	[ -f "${INSTALL_PREFIX}/lib/${soname}" ] || cp "${name}" "${INSTALL_PREFIX}/lib/${soname}"
	
	sed --in-place '/export PATH/d; s|$PREFIX/bin/|/tmp/llvm-mingw-toolchain/bin/|g' \
		'./build-mingw-w64.sh' \
		'./build-mingw-w64-libraries.sh' \
		'./build-compiler-rt.sh' \
		'./build-libcxx.sh' \
		'./build-openmp.sh'
fi

sed --in-place 's/CMAKE_BUILD_TYPE=Release/CMAKE_BUILD_TYPE=MinSizeRel/g' \
	'./build-mingw-w64.sh' \
	'./build-mingw-w64-libraries.sh' \
	'./build-compiler-rt.sh' \
	'./build-libcxx.sh' \
	'./build-openmp.sh' \
	'./build-llvm.sh'

/proc/self/exe './build-all.sh' \
	${cross_compile_flags} \
	--disable-lldb \
	--with-default-msvcrt='msvcrt' \
	"${INSTALL_PREFIX}"
